import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/navigation/menu_navigator.dart';
import '../../core/network/odoo_client.dart';
import '../../core/session/session_storage.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../core/widgets/odoo_app_drawer.dart';
import '../../injection_container.dart';
import 'web_iframe_stub.dart'
    if (dart.library.js_interop) 'web_iframe_web.dart';

/// Embedded Odoo web client for `/web_action/:id`.
///
/// Native (Android): uses `webview_flutter` with the Odoo session_id
/// cookie injected on load, so the embedded page authenticates as the
/// signed-in user.
///
/// Web: we can't nest an iframe with cross-origin cookies reliably from
/// the debug bundle, so we render a "Open in new tab" placeholder that
/// points the user at the Odoo action URL directly.
class WebActionPage extends StatefulWidget {
  const WebActionPage({
    super.key,
    this.actionId,
    this.model,
    this.portalPath,
    this.path,
    this.title,
  }) : assert(
          actionId != null || model != null || path != null,
          'One of actionId, model, or path is required',
        );

  /// Odoo action id — resolved to `/odoo/action-<id>` when [path] is null.
  final int? actionId;

  /// Odoo model name — internal-user route. Resolved to an action id at
  /// open time.
  final String? model;

  /// Portal user route — the `/my/<slug>` URL. WebActionPage embeds
  /// this instead of the model→action lookup when the signed-in user is
  /// a portal user (student / parent). Backend `/odoo/*` bounces them
  /// to `/web/login`; `/my/*` is what they have ACL for.
  final String? portalPath;

  /// Explicit relative URL — hard override, takes precedence over
  /// everything else.
  final String? path;

  final String? title;

  @override
  State<WebActionPage> createState() => _WebActionPageState();
}

class _WebActionPageState extends State<WebActionPage> {
  String? _path;
  bool _lookupFailed = false;
  int? _count;
  int _reloadTick = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // When drawer is open, we flip this to false so the iframe's
  // pointer-events go to `none` and taps land on the drawer items
  // instead of being swallowed by the embedded Odoo page.
  final ValueNotifier<bool> _iframePointerEnabled = ValueNotifier<bool>(true);

  @override
  void dispose() {
    _iframePointerEnabled.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bootstrapPath();
    if (widget.model != null) _loadCount();
  }

  /// Append `#view_type=kanban` to backend action URLs so Odoo renders
  /// the mobile-friendly kanban card view (like Timetables) instead of
  /// the desktop table (like Leaves). Falls back to list automatically
  /// when the action's model has no kanban view defined.
  String _preferKanban(String path) {
    if (!path.startsWith('/odoo/action-')) return path;
    if (path.contains('#')) return path;
    return '$path#view_type=kanban';
  }

  Future<void> _bootstrapPath() async {
    // Hard override wins.
    if (widget.path != null) {
      setState(() => _path = widget.path);
      return;
    }
    // Portal (student / parent) users can't access /odoo/action-N —
    // they get bounced to /web/login. Prefer the /my/<slug> portal URL
    // when we know it.
    final meta = await sl<SessionStorage>().getMeta();
    if (meta.isPortal && widget.portalPath != null) {
      if (!mounted) return;
      setState(() => _path = widget.portalPath);
      return;
    }
    if (widget.actionId != null) {
      if (!mounted) return;
      setState(() => _path = _preferKanban('/odoo/action-${widget.actionId}'));
      _syncActiveMenu(widget.actionId!);
      return;
    }
    // Portal path missing but portal user + model — still worth trying
    // /my/<model-slug> before giving up.
    if (meta.isPortal && widget.model != null) {
      if (!mounted) return;
      setState(() => _lookupFailed = true);
      return;
    }
    _resolveModel();
  }

  /// Look up the `ir.ui.menu` row whose `action` points at [actionId]
  /// and set it as the drawer's `activeMenuId` so the module row
  /// renders in red when the user opens the drawer from this page.
  Future<void> _syncActiveMenu(int actionId) async {
    try {
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'ir.ui.menu',
        method: 'search_read',
        args: [
          [
            ['action', '=', 'ir.actions.act_window,$actionId'],
          ],
          ['id'],
        ],
        kwargs: const {'limit': 1},
      );
      if (rows.isNotEmpty) {
        activeMenuId.value = (rows.first as Map)['id'] as int;
      }
    } catch (_) {
      // Menu lookup is best-effort — drawer just won't highlight.
    }
  }

  Future<void> _resolveModel() async {
    try {
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'ir.actions.act_window',
        method: 'search_read',
        args: [
          [
            ['res_model', '=', widget.model],
          ],
          ['id'],
        ],
        kwargs: const {'limit': 1},
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        setState(() => _lookupFailed = true);
        return;
      }
      final id = (rows.first as Map)['id'] as int;
      setState(() => _path = _preferKanban('/odoo/action-$id'));
      _syncActiveMenu(id);
    } catch (_) {
      if (mounted) setState(() => _lookupFailed = true);
    }
  }

  Future<void> _loadCount() async {
    try {
      final n = await sl<OdooClient>().callKw<int>(
        model: widget.model!,
        method: 'search_count',
        args: const [[]],
      );
      if (mounted) setState(() => _count = n);
    } catch (_) {
      // Model may not exist or ACL denies — keep badge hidden.
    }
  }

  void _refresh() {
    setState(() => _reloadTick++);
    if (widget.model != null) _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = widget.title ??
        (widget.actionId != null
            ? 'Action ${widget.actionId}'
            : (widget.model ?? ''));
    // Odoo's own /my/* portal templates render their own page heading
    // (e.g. "Connection & Security", "Student Fees"). Showing our
    // Flutter title on top of that would duplicate the heading. Hide
    // the AppBar title for /my/* pages so only Odoo's own heading is
    // visible.
    final isPortalRoute = _path?.startsWith('/my/') ?? false;
    final displayTitle = isPortalRoute ? '' : resolvedTitle;
    // Odoo's global `search_count` runs against the backend model and
    // often disagrees with what the portal template actually shows
    // (its domain is filtered further by student ownership). Only
    // display the badge when the iframe is a backend /odoo/action-N
    // page — those match one-for-one.
    final showCountBadge = !isPortalRoute && _count != null && _count! > 0;
    return Scaffold(
      key: _scaffoldKey,
      drawer: const OdooAppDrawer(),
      onDrawerChanged: (open) => _iframePointerEnabled.value = !open,
      appBar: AppBar(
        backgroundColor: OdooEduColors.brand,
        foregroundColor: Colors.white,
        // Keep the back button on the left even though a `drawer:` is
        // defined — Flutter would normally swap the leading for a
        // hamburger when a drawer is present. The user wants back on
        // the left and the ≡ menu button (right) to open the SAME
        // left-side drawer.
        leading: const BackButton(),
        centerTitle: false,
        titleSpacing: 4,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(displayTitle, overflow: TextOverflow.ellipsis),
            ),
            if (showCountBadge) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$_count',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          // Only surface the modules drawer on admin action pages —
          // portal users have nothing to browse there.
          if (!isPortalRoute)
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Menu',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
        ],
      ),
      body: _lookupFailed
          ? _NoActionState(title: resolvedTitle)
          : (_path == null
              ? const Center(child: CircularProgressIndicator())
              : (kIsWeb
                  ? _WebFallback(
                      key: ValueKey('web-$_reloadTick'),
                      path: _path!,
                      title: displayTitle,
                      pointerEnabled: _iframePointerEnabled,
                    )
                  : _NativeWebView(
                      key: ValueKey('native-$_reloadTick'),
                      path: _path!,
                    ))),
    );
  }
}

class _NoActionState extends StatelessWidget {
  const _NoActionState({this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    final displayTitle = title ?? 'Nothing here';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E5EB)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF6F8FB),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B7BC7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Track and manage your records here.',
                    style: TextStyle(
                      color: OdooEduColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE1F1EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: Color(0xFF7CA69A),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No records found',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16324F),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "You have no pending or past records.",
                      style: TextStyle(
                        color: Color(0xFF16324F),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NativeWebView extends StatefulWidget {
  const _NativeWebView({super.key, required this.path});
  final String path;

  @override
  State<_NativeWebView> createState() => _NativeWebViewState();
}

class _NativeWebViewState extends State<_NativeWebView> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) async {
            try {
              await _controller.runJavaScript(_hideChromeJs);
            } catch (_) {}
            if (mounted) setState(() => _loading = false);
          },
        ),
      );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Inject the stored session_id cookie so the WebView starts
    // authenticated. Without this the embedded page bounces to Odoo's
    // /web/login instead of showing the action.
    final sid = await sl<SessionStorage>().getSessionId();
    if (sid != null && sid.isNotEmpty) {
      final host = Uri.parse(AppConfig.serverUrl).host;
      await WebViewCookieManager().setCookie(
        WebViewCookie(name: 'session_id', value: sid, domain: host, path: '/'),
      );
    }
    await _controller.loadRequest(
      Uri.parse('${AppConfig.serverUrl}${widget.path}'),
    );
  }

  static const String _hideChromeJs = '''
    (function () {
      var id = 'flutter-hide-odoo-chrome';
      if (document.getElementById(id)) return;
      var s = document.createElement('style');
      s.id = id;
      s.textContent =
        '.o_main_navbar, .o_navbar { display: none !important; }' +
        '.o_action_manager { top: 0 !important; }' +
        'header.o_header_standard, header#top, #wrapwrap > header, ' +
        'nav.navbar, .o_header_standard ' +
        '{ display: none !important; }' +
        'footer#footer, footer.o_footer, #wrapwrap > footer ' +
        '{ display: none !important; }' +
        'body, #wrapwrap ' +
        '{ margin-top: 0 !important; padding-top: 0 !important; }';
      document.head.appendChild(s);
    })();
  ''';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Positioned.fill(
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

/// On web we serve everything through the local CORS proxy (`/`), so an
/// iframe pointing at `/odoo/action-N` embeds Odoo's own web client with
/// the session cookie in scope automatically. The proxy also strips
/// X-Frame-Options so the embed isn't blocked.
class _WebFallback extends StatelessWidget {
  const _WebFallback({
    super.key,
    required this.path,
    required this.title,
    this.pointerEnabled,
  });
  final String path;
  final String title;
  final ValueListenable<bool>? pointerEnabled;

  @override
  Widget build(BuildContext context) {
    return WebIframe(url: path, pointerEnabled: pointerEnabled);
  }
}
