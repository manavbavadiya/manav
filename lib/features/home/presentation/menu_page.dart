import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/menu_navigator.dart';
import '../../../core/theme/odoo_edu_colors.dart';
import '../../../injection_container.dart';
import '../data/module_remote_datasource.dart';
import '../domain/odoo_module.dart';

/// Second-level menu view. If [parent] arrived with children materialised
/// we render them straight away, otherwise we lazy-load via `childIds`.
class MenuPage extends StatefulWidget {
  const MenuPage({super.key, required this.menuId, this.parent});
  final int menuId;
  final OdooModule? parent;

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Future<List<OdooModule>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<OdooModule>> _load() async {
    final p = widget.parent;
    if (p != null && p.children.isNotEmpty) return p.children;
    final ids = p?.childIds ?? [];
    if (ids.isEmpty) return const [];
    return sl<ModuleRemoteDataSource>().getChildren(ids);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.parent?.displayName ?? 'Menu';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: OdooEduColors.brand,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: FutureBuilder<List<OdooModule>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'No child items.',
                style: TextStyle(color: OdooEduColors.textMuted),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final m = items[i];
              return ListTile(
                leading: m.iconUrl == null
                    ? const Icon(Icons.description_outlined, color: OdooEduColors.brand)
                    : Image.network(
                        m.iconUrl!,
                        width: 24,
                        height: 24,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.description_outlined,
                          color: OdooEduColors.brand,
                        ),
                      ),
                title: Text(m.displayName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => navigateToMenuWithRouter(GoRouter.of(context), m),
              );
            },
          );
        },
      ),
    );
  }
}

/// Wrap the FutureBuilder in a BlocProvider so any deep child widgets that
/// want access to auth still get it.
class MenuPageRoute extends StatelessWidget {
  const MenuPageRoute({super.key, required this.menuId, this.parent});
  final int menuId;
  final OdooModule? parent;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: const [],
      child: MenuPage(menuId: menuId, parent: parent),
    );
  }
}
