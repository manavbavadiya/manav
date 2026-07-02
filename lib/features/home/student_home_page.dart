import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/odoo_edu_colors.dart';
import '../auth/auth_bloc.dart';

/// Portal home for student / parent users. Two tabs matching the actual
/// old-app screenshots: Portal (card list) + Me (profile + sign out).
/// No module tree drawer — student never sees backend chrome.
class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) context.go('/login');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F4F5),
        body: _tab == 0 ? const _PortalTab() : const _MeTab(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          backgroundColor: Colors.white,
          indicatorColor: OdooEduColors.brand.withValues(alpha: 0.15),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Portal',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Me',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Portal tab ─────────────────────────────────────────────────────────────

class _PortalTab extends StatelessWidget {
  const _PortalTab();

  // Cards mirror the old app's portal list order and copy — see
  // `/tmp/old_screens/student/*.png` for the source screenshots.
  static const _cards = <_PortalCard>[
    _PortalCard(
      title: 'Your Fees',
      description: 'Follow, download or pay your invoices.',
      icon: Icons.account_balance_wallet_outlined,
      iconBg: Color(0xFFDDF3EC),
      iconColor: Color(0xFF17A67A),
      route: '/list/fees',
    ),
    _PortalCard(
      title: 'Student Profile',
      description: 'View and manage your personal student profile information.',
      icon: Icons.person_outline,
      iconBg: Color(0xFFEFEFEF),
      iconColor: Color(0xFF5D5D5D),
      route: '/list/profile',
    ),
    _PortalCard(
      title: 'Circulars',
      description: 'View important announcements and circulars.',
      icon: Icons.article_outlined,
      iconBg: Color(0xFFEFEFEF),
      iconColor: Color(0xFF5D5D5D),
      route: '/list/notice',
    ),
    _PortalCard(
      title: 'Homework',
      description: 'View your assigned homework and due dates.',
      icon: Icons.assignment_outlined,
      iconBg: Color(0xFFFDE4CE),
      iconColor: Color(0xFFE57B1F),
      route: '/list/homework',
    ),
    _PortalCard(
      title: 'Attendance',
      description: 'Check your daily attendance records and status.',
      icon: Icons.event_available_outlined,
      iconBg: Color(0xFFD8ECD8),
      iconColor: Color(0xFF2E8B4A),
      route: '/list/attendance',
    ),
    _PortalCard(
      title: 'Timetable',
      description: 'View your class schedule and subject timings.',
      icon: Icons.grid_view_rounded,
      iconBg: Color(0xFFEEE0FA),
      iconColor: Color(0xFF7B3FE4),
      route: '/list/timetable',
    ),
    _PortalCard(
      title: 'Transportation',
      description: 'Transportation routes, vehicles, and driver details.',
      icon: Icons.directions_bus_filled_outlined,
      iconBg: Color(0xFFFAD9D6),
      iconColor: Color(0xFFC62828),
      route: '/list/transport',
    ),
    _PortalCard(
      title: 'Parents Meetings',
      description: 'Scheduled meetings and announcements.',
      icon: Icons.calendar_month_outlined,
      iconBg: Color(0xFFFCE4C3),
      iconColor: Color(0xFFE57B1F),
      route: '/list/meetings',
    ),
    _PortalCard(
      title: 'Certificates',
      description: 'Download your competition certificates.',
      icon: Icons.picture_as_pdf_outlined,
      iconBg: Color(0xFFFCDCDA),
      iconColor: Color(0xFFC62828),
      route: '/list/certificates',
    ),
    _PortalCard(
      title: 'Queries & Complaints',
      description: 'Submit applications, queries, or complaints.',
      icon: Icons.help_outline,
      iconBg: Color(0xFFD9EAFB),
      iconColor: Color(0xFF1565C0),
      route: '/list/remarks',
    ),
    _PortalCard(
      title: 'Holidays',
      description: 'View upcoming holidays and academic breaks.',
      icon: Icons.flight_takeoff,
      iconBg: Color(0xFFFCE4C3),
      iconColor: Color(0xFFE57B1F),
      route: '/list/holidays',
    ),
    _PortalCard(
      title: 'Leaves',
      description: 'Request and view student leaves.',
      icon: Icons.event_busy,
      iconBg: Color(0xFFFCDCDA),
      iconColor: Color(0xFFC62828),
      route: '/list/leaves',
    ),
    _PortalCard(
      title: 'Exam Results',
      description: 'View and download your exam results.',
      icon: Icons.emoji_events_outlined,
      iconBg: Color(0xFFD8ECD8),
      iconColor: Color(0xFF2E8B4A),
      route: '/list/exam-results',
    ),
    _PortalCard(
      title: 'Addresses',
      description: 'Add, remove or modify your addresses.',
      icon: Icons.place_outlined,
      iconBg: Color(0xFFD9EAFB),
      iconColor: Color(0xFF1565C0),
      route: '/list/addresses',
    ),
    _PortalCard(
      title: 'Connection & Security',
      description: 'Configure your connection parameters.',
      icon: Icons.lock_outline,
      iconBg: Color(0xFFD9EAFB),
      iconColor: Color(0xFF1565C0),
      route: '/list/security',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const _PortalHeader(),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: _cards.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PortalCardView(card: _cards[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalHeader extends StatelessWidget {
  const _PortalHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: const [
          Icon(Icons.school, size: 24, color: OdooEduColors.brand),
          SizedBox(width: 10),
          Text(
            'My Portal',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: OdooEduColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalCard {
  const _PortalCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.route,
  });
  final String title;
  final String description;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String route;
}

class _PortalCardView extends StatelessWidget {
  const _PortalCardView({required this.card});
  final _PortalCard card;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push(card.route),
        // IntrinsicHeight lets the left "stretch" stripe pick up the row's
        // intrinsic height — without it, cross-axis stretch inside an
        // unbounded ListView collapses the whole tile to 0 px.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left purple stripe — signature of the old app.
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: OdooEduColors.brand,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    bottomLeft: Radius.circular(10),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: card.iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(card.icon, color: card.iconColor, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              card.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF16324F),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              card.description,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7F8CA0),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Me tab ─────────────────────────────────────────────────────────────────

class _MeTab extends StatelessWidget {
  const _MeTab();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthBloc>().state;
    final session = auth is Authenticated ? auth.session : null;
    final name = session?.userName.trim().isNotEmpty == true
        ? session!.userName
        : (session?.login ?? '');
    final email = session?.login ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return SafeArea(
      child: Column(
        children: [
          const _PortalHeaderMe(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: OdooEduColors.brand.withValues(
                          alpha: 0.10,
                        ),
                        child: Text(
                          initial,
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            color: OdooEduColors.brand,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF16324F),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F8CA0),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: OdooEduColors.brand.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          (session?.role.displayLabel ?? 'STUDENT')
                              .toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: OdooEduColors.brand,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.read<AuthBloc>().add(
                      const AuthLogoutRequested(),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.logout, color: OdooEduColors.danger),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sign Out',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: OdooEduColors.danger,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Disconnect from your school account',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7F8CA0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Color(0xFF7F8CA0)),
                        ],
                      ),
                    ),
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

class _PortalHeaderMe extends StatelessWidget {
  const _PortalHeaderMe();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: const [
          Icon(Icons.school, size: 24, color: OdooEduColors.brand),
          SizedBox(width: 10),
          Text(
            'Me',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: OdooEduColors.brand,
            ),
          ),
        ],
      ),
    );
  }
}
