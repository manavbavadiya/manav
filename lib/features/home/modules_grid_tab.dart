import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/menu_navigator.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';
import 'domain/odoo_module.dart';
import 'presentation/module_grid_bloc.dart';

/// Admin "Modules" tab body — grid of every top-level installed module,
/// exactly what the drawer offers but rendered as a launchpad-style
/// GridView. Tap a tile → uses the same `navigateToMenu` decision as the
/// drawer so both paths stay in lockstep.
class ModulesGridTab extends StatelessWidget {
  const ModulesGridTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ModuleGridBloc>()..add(const LoadModules()),
      child: BlocBuilder<ModuleGridBloc, ModuleGridState>(
        builder: (context, state) {
          if (state is ModuleGridLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ModuleGridError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: OdooEduColors.textMuted),
                ),
              ),
            );
          }
          if (state is ModuleGridLoaded) {
            final modules = state.modules;
            if (modules.isEmpty) {
              return const Center(
                child: Text(
                  'No modules available.',
                  style: TextStyle(color: OdooEduColors.textMuted),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.9,
              ),
              itemCount: modules.length,
              itemBuilder: (_, i) => _ModuleTile(module: modules[i]),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.module});
  final OdooModule module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => navigateToMenuWithRouter(GoRouter.of(context), module),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE1E5EB)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Icon(url: module.iconUrl),
            const SizedBox(height: 8),
            Text(
              module.displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF16324F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Icon extends StatelessWidget {
  const _Icon({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return const Icon(Icons.description_outlined, color: OdooEduColors.brand, size: 40);
    }
    return Image.network(
      url!,
      width: 40,
      height: 40,
      errorBuilder: (_, _, _) =>
          const Icon(Icons.description_outlined, color: OdooEduColors.brand, size: 40),
    );
  }
}
