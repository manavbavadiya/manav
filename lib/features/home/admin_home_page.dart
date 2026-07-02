import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/odoo_edu_colors.dart';
import '../../core/widgets/odoo_app_drawer.dart';
import '../activity/activity_page.dart';
import '../auth/auth_bloc.dart';
import '../dashboard/admin_kpi_dashboard.dart';
import 'global_search.dart';

/// 4-tab shell for admin/faculty users: Dashboard / Search / Activity /
/// Profile. Wraps [OdooAppDrawer] so the module tree is always one swipe
/// away.
class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int _index = 0;
  static const _titles = ['Dashboard', 'Search', 'Activity', 'Profile'];

  Widget _body() {
    switch (_index) {
      case 0:
        return const AdminKpiDashboard();
      case 1:
        return const OdooGlobalSearch();
      case 2:
        return const ActivityPage();
      case 3:
        return const _ProfileTab();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) context.go('/login');
      },
      child: Scaffold(
        drawer: const OdooAppDrawer(),
        appBar: AppBar(
          backgroundColor: OdooEduColors.brand,
          foregroundColor: Colors.white,
          title: Text(
            _titles[_index],
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: _body(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          indicatorColor: OdooEduColors.brand.withValues(alpha: 0.15),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final s = authState is Authenticated ? authState.session : null;
    final name = s?.userName.isNotEmpty == true ? s!.userName : 'Signed in';
    final email = s?.login ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: OdooEduColors.brand.withValues(alpha: 0.12),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: OdooEduColors.brand,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: const TextStyle(
                      color: OdooEduColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            onTap: () =>
                context.read<AuthBloc>().add(const AuthLogoutRequested()),
            leading: const Icon(Icons.logout, color: OdooEduColors.danger),
            title: const Text(
              'Sign Out',
              style: TextStyle(
                color: OdooEduColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: const Text(
              'Disconnect Odoo session',
              style: TextStyle(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
      ],
    );
  }
}
