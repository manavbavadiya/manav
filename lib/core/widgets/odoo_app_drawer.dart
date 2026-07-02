import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_bloc.dart';
import '../../features/home/domain/odoo_module.dart';
import '../../features/home/presentation/module_grid_bloc.dart';
import '../../injection_container.dart';
import '../navigation/menu_navigator.dart';
import '../theme/odoo_edu_colors.dart';

/// Left drawer that mirrors Odoo's own app menu. Each top-level module is
/// an [ExpansionTile] and tapping a leaf delegates to [navigateToMenu] so
/// destination logic stays identical to the home grid.
class OdooAppDrawer extends StatelessWidget {
  const OdooAppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: BlocProvider(
        create: (_) => sl<ModuleGridBloc>()..add(const LoadModules()),
        child: SafeArea(
          child: Column(
            children: [
              const _DrawerHeader(),
              Expanded(
                child: BlocBuilder<ModuleGridBloc, ModuleGridState>(
                  builder: (context, state) {
                    if (state is ModuleGridLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is ModuleGridError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            state.message,
                            style: const TextStyle(
                              color: OdooEduColors.textMuted,
                            ),
                          ),
                        ),
                      );
                    }
                    if (state is ModuleGridLoaded) {
                      return _DrawerTree(modules: state.modules);
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
              const _DrawerFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthBloc>().state;
    final s = state is Authenticated ? state.session : null;
    final name = s?.userName ?? 'Signed in';
    final db = s?.database ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        color: OdooEduColors.brand,
        border: Border(bottom: BorderSide(color: Color(0x22000000))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: OdooEduColors.brand,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (db.isNotEmpty)
                  Text(
                    db,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

  Future<void> _resetOnboarding(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', false);
    await prefs.remove('odoo_url');
    if (!context.mounted) return;
    Navigator.of(context).pop();
    // Force a fresh logout so the app rewinds all the way back to
    // /onboarding via the splash.
    context.read<AuthBloc>().add(const AuthLogoutRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.home_outlined, color: Color(0xFF16324F)),
          title: const Text(
            'Home',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () {
            Navigator.of(context).pop();
            context.go('/admin');
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: OdooEduColors.danger),
          title: const Text(
            'Sign out',
            style: TextStyle(
              color: OdooEduColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
          onTap: () {
            Navigator.of(context).pop();
            context.read<AuthBloc>().add(const AuthLogoutRequested());
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh, color: OdooEduColors.textMuted),
          title: const Text(
            'Reset app (re-run onboarding)',
            style: TextStyle(color: OdooEduColors.textMuted, fontSize: 13),
          ),
          onTap: () => _resetOnboarding(context),
        ),
      ],
    );
  }
}

class _DrawerTree extends StatefulWidget {
  const _DrawerTree({required this.modules});
  final List<OdooModule> modules;

  @override
  State<_DrawerTree> createState() => _DrawerTreeState();
}

class _DrawerTreeState extends State<_DrawerTree> {
  /// Id of the currently-open top-level section. Only one at a time —
  /// opening another collapses the previous.
  int? _openId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: activeMenuId,
      builder: (context, activeId, _) {
        return SingleChildScrollView(
          child: Column(
            children: [
              for (final m in widget.modules)
                _ModuleTile(
                  key: ValueKey('drawer-${m.id}'),
                  module: m,
                  activeId: activeId,
                  isOpen: _openId == m.id,
                  onOpen: () => setState(() => _openId = m.id),
                  onClose: () {
                    if (_openId == m.id) {
                      setState(() => _openId = null);
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    super.key,
    required this.module,
    required this.activeId,
    this.isOpen = false,
    this.onOpen,
    this.onClose,
  });
  final OdooModule module;
  final int? activeId;
  final bool isOpen;
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  bool _isActive(OdooModule m) => activeId != null && m.id == activeId;

  bool _isOrContainsActive(OdooModule m) {
    if (activeId == null) return false;
    if (m.id == activeId) return true;
    for (final c in m.children) {
      if (_isOrContainsActive(c)) return true;
    }
    final ids = m.childIds;
    if (ids != null && ids.contains(activeId)) return true;
    return false;
  }

  bool get _hasChildren =>
      module.children.isNotEmpty ||
      (module.childIds != null && module.childIds!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!_hasChildren) {
      final active = _isActive(module);
      return ListTile(
        leading: _Icon(url: module.iconUrl),
        title: Text(
          module.displayName,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: active ? Colors.red : null,
          ),
        ),
        onTap: () => _go(context, module),
      );
    }
    return ExpansionTile(
      // Accordion behavior — only one top-level section stays open at a
      // time. Encoding `isOpen` into the ValueKey forces Flutter to
      // discard the old ExpansionTile widget when the parent's
      // currently-open id switches, so `initiallyExpanded` re-applies
      // and all other sections collapse.
      key: ValueKey('m-${module.id}-$isOpen'),
      initiallyExpanded: isOpen,
      maintainState: false,
      onExpansionChanged: (expanded) {
        if (expanded) {
          onOpen?.call();
          Future.delayed(const Duration(milliseconds: 260), () {
            if (!context.mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          });
        } else {
          onClose?.call();
        }
      },
      leading: _Icon(url: module.iconUrl),
      title: Text(
        module.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: _isOrContainsActive(module) ? Colors.red : null,
        ),
      ),
      iconColor: OdooEduColors.brand,
      collapsedIconColor: OdooEduColors.textMuted,
      childrenPadding: const EdgeInsets.only(left: 16),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        for (final c in module.children)
          ListTile(
            dense: true,
            title: Text(
              c.displayName,
              style: TextStyle(color: _isActive(c) ? Colors.red : null),
            ),
            leading: const SizedBox(width: 20),
            onTap: () => _go(context, c),
          ),
        if (module.action != null && module.action!.isNotEmpty)
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.dashboard_outlined,
              size: 18,
              color: OdooEduColors.textMuted,
            ),
            title: Text(
              'Open this module',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: _isActive(module) ? Colors.red : OdooEduColors.textMuted,
              ),
            ),
            onTap: () => _go(context, module),
          ),
      ],
    );
  }

  void _go(BuildContext context, OdooModule m) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    navigateToMenuWithRouter(router, m);
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const Icon(Icons.description_outlined, color: OdooEduColors.brand);
    }
    return Image.network(
      url!,
      width: 24,
      height: 24,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.description_outlined, color: OdooEduColors.brand),
    );
  }
}
