import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/odoo_client.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

/// Admin "Dashboard" tab. Matches the old app's screenshot pixel-by-pixel:
///   1. **Six large colored stat cards** (Students, Staff, Holidays,
///      Attendance, Queries, Leaves)
///   2. **QUICK ACCESS** grid — 4×2 icon tiles for common actions
///   3. **Section cards** with descriptions + colored action buttons
///      (FEE, STUDENT, STAFF, ACADEMICS)
///
/// All numbers come from `edu.dashboard.get_stats()`; if the RPC fails or
/// the key isn't present, we show `0` (never crash).
class AdminKpiDashboard extends StatefulWidget {
  const AdminKpiDashboard({super.key});

  @override
  State<AdminKpiDashboard> createState() => _AdminKpiDashboardState();
}

class _AdminKpiDashboardState extends State<AdminKpiDashboard> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    try {
      final raw = await sl<OdooClient>().callKw<dynamic>(
        model: 'edu.dashboard',
        method: 'get_stats',
        args: const [],
      );
      return raw is Map ? Map<String, dynamic>.from(raw) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  int _int(Map<String, dynamic> d, String key) {
    final v = d[key];
    if (v is num) return v.toInt();
    return 0;
  }

  double _money(Map<String, dynamic> d, String key) {
    final v = d[key];
    if (v is num) return v.toDouble();
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data ?? const <String, dynamic>{};
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              // ── Row 1: Students / Staff ────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFF2F86C6),
                      icon: Icons.groups,
                      value: '${_int(d, 'student_count')}',
                      label: 'STUDENTS',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFF23B899),
                      icon: Icons.person,
                      value: '${_int(d, 'faculty_count')}',
                      label: 'STAFF',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Row 2: Holidays / Attendance ───────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFF56B84A),
                      icon: Icons.calendar_month,
                      value: '${_int(d, 'upcoming_holidays')}',
                      label: 'HOLIDAYS',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFFE39A2A),
                      icon: Icons.check_circle_outline,
                      value:
                          '${_int(d, 'present_count')}/${_int(d, 'attendance_count')}',
                      label: 'ATTENDANCE',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Row 3: Queries / Leaves ────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFF9C4EBD),
                      icon: Icons.help_outline,
                      value:
                          '${_int(d, 'query_new')}/${_int(d, 'query_new') + _int(d, 'query_inprogress')}',
                      label: 'QUERIES',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      color: const Color(0xFFC0332B),
                      icon: Icons.hotel,
                      value:
                          '${_int(d, 'leave_new')}/${_int(d, 'leave_new') + _int(d, 'leave_active')}',
                      label: 'LEAVES',
                    ),
                  ),
                ],
              ),
              // ── QUICK ACCESS ──────────────────────────────────────
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'QUICK ACCESS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Color(0xFF7F8CA0),
                  ),
                ),
              ),
              const _QuickAccessGrid(),
              // ── Section cards ────────────────────────────────────
              const SizedBox(height: 20),
              _FeeSectionCard(
                collected: _money(d, 'total_fees_collected'),
                due: _money(d, 'total_fees_due'),
              ),
              const SizedBox(height: 12),
              const _StudentSectionCard(),
              const SizedBox(height: 12),
              const _StaffSectionCard(),
              const SizedBox(height: 12),
              const _AcademicsSectionCard(),
            ],
          );
        },
      ),
    );
  }
}

// ── Stat card ───────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.color,
    required this.icon,
    required this.value,
    required this.label,
  });
  final Color color;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const Spacer(),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick Access grid ──────────────────────────────────────────────────────

class _QuickAccessGrid extends StatelessWidget {
  const _QuickAccessGrid();

  static const _items = <_QuickItem>[
    _QuickItem(
      icon: Icons.calendar_month_outlined,
      label: 'Timetable',
      route: '/list/timetable',
    ),
    _QuickItem(
      icon: Icons.flight_takeoff,
      label: 'Holidays',
      route: '/list/holidays',
    ),
    _QuickItem(
      icon: Icons.account_balance_wallet_outlined,
      label: 'Fees',
      route: '/list/fees',
    ),
    _QuickItem(
      icon: Icons.verified_outlined,
      label: 'Faculty Cert.',
      route: '/list/certificates',
    ),
    _QuickItem(
      icon: Icons.emoji_events_outlined,
      label: 'Competitions',
      route: '/list/competitions',
    ),
    _QuickItem(
      icon: Icons.campaign_outlined,
      label: 'Circulars',
      route: '/list/notice',
    ),
    _QuickItem(
      icon: Icons.school_outlined,
      label: 'Exam Results',
      route: '/list/exam-results',
    ),
    _QuickItem(icon: Icons.event_busy, label: 'Leaves', route: '/list/leaves'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.85,
        children: [for (final it in _items) _QuickTile(item: it)],
      ),
    );
  }
}

class _QuickItem {
  const _QuickItem({
    required this.icon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final String label;
  final String route;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item});
  final _QuickItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE1E5EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 24, color: const Color(0xFF16324F)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                item.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16324F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section cards ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.body,
    required this.buttons,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String description;
  final Widget? body;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: Color(0xFF16324F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE1E5EB)),
          const SizedBox(height: 10),
          if (body != null) ...[body!, const SizedBox(height: 10)],
          Text(
            description,
            style: const TextStyle(fontSize: 13, color: Color(0xFF7F8CA0)),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: buttons),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeeSectionCard extends StatelessWidget {
  const _FeeSectionCard({required this.collected, required this.due});
  final double collected;
  final double due;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.attach_money,
      iconBg: const Color(0xFFDCF4EC),
      iconColor: const Color(0xFF17A67A),
      title: 'FEE',
      description: 'Track collections and outstanding balances.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Collected: ₹${collected.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF17A67A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Due: ₹${due.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFC0332B),
            ),
          ),
        ],
      ),
      buttons: [
        _PillButton(
          icon: Icons.list,
          label: 'List',
          color: const Color(0xFF17A67A),
          onTap: () => context.push('/list/fees'),
        ),
        _PillButton(
          icon: Icons.add,
          label: 'Register',
          color: const Color(0xFF2ECC71),
          onTap: () => context.push('/list/fees'),
        ),
      ],
    );
  }
}

class _StudentSectionCard extends StatelessWidget {
  const _StudentSectionCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.school,
      iconBg: const Color(0xFFDBEBF9),
      iconColor: const Color(0xFF2F86C6),
      title: 'STUDENT',
      description: 'Manage student admissions, profiles, and details.',
      body: null,
      buttons: [
        _PillButton(
          icon: Icons.list,
          label: 'List',
          color: const Color(0xFF17A67A),
          onTap: () => context.push('/list/students'),
        ),
        _PillButton(
          icon: Icons.person_add_alt,
          label: 'Admission',
          color: const Color(0xFF2F86C6),
          onTap: () => context.push('/list/students'),
        ),
      ],
    );
  }
}

class _StaffSectionCard extends StatelessWidget {
  const _StaffSectionCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.groups,
      iconBg: const Color(0xFFD4F1EA),
      iconColor: const Color(0xFF23B899),
      title: 'STAFF',
      description: 'Manage faculty, principals, and staff members.',
      body: null,
      buttons: [
        _PillButton(
          icon: Icons.list,
          label: 'List',
          color: const Color(0xFFE39A2A),
          onTap: () => context.push('/list/partner'),
        ),
      ],
    );
  }
}

class _AcademicsSectionCard extends StatelessWidget {
  const _AcademicsSectionCard();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.menu_book,
      iconBg: const Color(0xFFE6E1EE),
      iconColor: const Color(0xFF16324F),
      title: 'ACADEMICS',
      description: 'Manage subjects, standards, and divisions.',
      body: null,
      buttons: [
        _PillButton(
          icon: Icons.menu_book_outlined,
          label: 'Subjects',
          color: OdooEduColors.textMuted,
          onTap: () => context.push('/list/exam'),
        ),
        _PillButton(
          icon: Icons.class_,
          label: 'Classes',
          color: const Color(0xFF16324F),
          onTap: () => context.push('/list/students'),
        ),
      ],
    );
  }
}
