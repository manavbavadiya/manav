// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../core/theme/odoo_edu_colors.dart';

/// Web-only iframe wrapper. Registers one platform view per URL and hands
/// it to Flutter via [HtmlElementView], plus draws a spinner overlay
/// until the iframe fires its `load` event.
class WebIframe extends StatefulWidget {
  const WebIframe({super.key, required this.url, this.pointerEnabled});
  final String url;

  /// When non-null, the iframe's DOM `pointer-events` is toggled to
  /// `none` while [pointerEnabled] is `false`. Used to let overlays
  /// (e.g. a Flutter drawer sliding over the iframe) receive taps —
  /// otherwise the iframe swallows every pointer event over its area
  /// and the drawer items appear frozen.
  final ValueListenable<bool>? pointerEnabled;

  @override
  State<WebIframe> createState() => _WebIframeState();
}

class _WebIframeState extends State<WebIframe> {
  bool _loading = true;
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  StreamSubscription<web.Event>? _loadSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'odoo-iframe-${widget.url.hashCode}-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final iframe = web.HTMLIFrameElement()
        ..src = widget.url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = true;
      _iframe = iframe;
      _applyPointerEnabled();
      _loadSub = iframe.onLoad.listen((_) {
        if (mounted) setState(() => _loading = false);
      });
      return iframe;
    });
    widget.pointerEnabled?.addListener(_applyPointerEnabled);
  }

  void _applyPointerEnabled() {
    final iframe = _iframe;
    if (iframe == null) return;
    final enabled = widget.pointerEnabled?.value ?? true;
    iframe.style.pointerEvents = enabled ? 'auto' : 'none';
  }

  @override
  void didUpdateWidget(WebIframe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pointerEnabled != widget.pointerEnabled) {
      oldWidget.pointerEnabled?.removeListener(_applyPointerEnabled);
      widget.pointerEnabled?.addListener(_applyPointerEnabled);
      _applyPointerEnabled();
    }
  }

  @override
  void dispose() {
    widget.pointerEnabled?.removeListener(_applyPointerEnabled);
    _loadSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(OdooEduColors.brand),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
