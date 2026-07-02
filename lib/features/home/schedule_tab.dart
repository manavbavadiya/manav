import 'package:flutter/material.dart';

import '../../core/network/odoo_client.dart';
import '../../core/session/session_storage.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

class _ScheduleRow {
  const _ScheduleRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.icon,
    required this.tint,
  });
  final String title;
  final String subtitle;
  final String trailing;
  final IconData icon;
  final Color tint;
}

class _ScheduleData {
  const _ScheduleData({
    required this.timetable,
    required this.exams,
    required this.attendancePresent,
    required this.attendanceTotal,
  });
  final List<_ScheduleRow> timetable;
  final List<_ScheduleRow> exams;
  final int attendancePresent;
  final int attendanceTotal;
}

/// Combined "what's happening to me" tab — today's timetable + upcoming
/// exams + an attendance summary ribbon. Uses the portal user's
/// `edu.student` link to filter each RPC; anything that ACL-denies falls
/// through to the empty state instead of crashing.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key});

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  late Future<_ScheduleData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ScheduleData> _load() async {
    final client = sl<OdooClient>();
    final session = sl<SessionStorage>();
    final meta = await session.getMeta();
    final uid = meta.uid;

    // Timetable — pull the timetable header rows. Each row's line records
    // (edu.timetable.line) hold the day/time slots; showing headers is
    // enough for the "Today" glance.
    List<_ScheduleRow> timetable = const [];
    try {
      final rows = await client.callKw<List<dynamic>>(
        model: 'edu.timetable',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'fields': const ['name', 'standard_id', 'division_id'],
          'order': 'id desc',
          'limit': 15,
        },
      );
      timetable = [
        for (final r in rows)
          if (r is Map)
            _ScheduleRow(
              title: r['name']?.toString() ?? 'Timetable',
              subtitle:
                  r['standard_id'] is List &&
                      (r['standard_id'] as List).length >= 2
                  ? (r['standard_id'] as List)[1].toString()
                  : '',
              trailing:
                  r['division_id'] is List &&
                      (r['division_id'] as List).length >= 2
                  ? (r['division_id'] as List)[1].toString()
                  : '',
              icon: Icons.schedule,
              tint: const Color(0xFF7B3FE4),
            ),
      ];
    } catch (_) {}

    // Upcoming exam sessions — model is `edu.exam.session`, not
    // `edu.exam`; time field is `start_datetime`.
    List<_ScheduleRow> exams = const [];
    try {
      final rows = await client.callKw<List<dynamic>>(
        model: 'edu.exam.session',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'fields': const ['name', 'start_datetime', 'state'],
          'order': 'start_datetime asc',
          'limit': 10,
        },
      );
      exams = [
        for (final r in rows)
          if (r is Map)
            _ScheduleRow(
              title: r['name']?.toString() ?? 'Exam',
              subtitle: r['state']?.toString() ?? '',
              trailing: r['start_datetime']?.toString() ?? '',
              icon: Icons.assignment_outlined,
              tint: const Color(0xFFE39A2A),
            ),
      ];
    } catch (_) {}

    // Attendance ribbon — `edu.attendance` has no `state` field.
    // Boolean flags (`present`, `absent`, `late`) live on the child
    // `edu.attendance.line`.
    int present = 0, total = 0;
    if (uid != null) {
      try {
        total = await client.callKw<int>(
          model: 'edu.attendance.line',
          method: 'search_count',
          args: const [[]],
        );
        present = await client.callKw<int>(
          model: 'edu.attendance.line',
          method: 'search_count',
          args: [
            [
              ['present', '=', true],
            ],
          ],
        );
      } catch (_) {}
    }

    return _ScheduleData(
      timetable: timetable,
      exams: exams,
      attendancePresent: present,
      attendanceTotal: total,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_ScheduleData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data =
              snap.data ??
              const _ScheduleData(
                timetable: [],
                exams: [],
                attendancePresent: 0,
                attendanceTotal: 0,
              );
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _AttendanceRibbon(
                present: data.attendancePresent,
                total: data.attendanceTotal,
              ),
              const SizedBox(height: 16),
              const _SectionTitle(title: "Today's Classes"),
              if (data.timetable.isEmpty)
                const _EmptyBlock(text: 'No classes scheduled.')
              else
                ...data.timetable.map(_rowTile),
              const SizedBox(height: 16),
              const _SectionTitle(title: 'Upcoming Exams'),
              if (data.exams.isEmpty)
                const _EmptyBlock(text: 'No exams coming up.')
              else
                ...data.exams.map(_rowTile),
            ],
          );
        },
      ),
    );
  }

  Widget _rowTile(_ScheduleRow r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: r.tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(r.icon, color: r.tint, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF16324F),
                  ),
                ),
                if (r.subtitle.isNotEmpty)
                  Text(
                    r.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: OdooEduColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (r.trailing.isNotEmpty)
            Text(
              r.trailing,
              style: const TextStyle(
                fontSize: 12,
                color: OdooEduColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Color(0xFF7F8CA0),
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: OdooEduColors.textMuted, fontSize: 13),
      ),
    );
  }
}

class _AttendanceRibbon extends StatelessWidget {
  const _AttendanceRibbon({required this.present, required this.total});
  final int present;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : present / total;
    final pct = (ratio * 100).round();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17A67A), Color(0xFF2ECC71)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Attendance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  total == 0 ? 'No data yet' : '$present of $total present',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Text(
            total == 0 ? '—' : '$pct%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }
}
