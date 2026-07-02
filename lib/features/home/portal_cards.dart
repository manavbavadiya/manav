import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/odoo_client.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

/// Config for one portal card: a model probe + how to render + where to
/// tap through. Purely declarative so the grid stays boring.
class PortalCardSpec {
  const PortalCardSpec({
    required this.title,
    required this.description,
    required this.model,
    required this.icon,
    required this.stripeColor,
    required this.listRoute,
    this.domain = const [],
  });

  final String title;
  final String description;
  final String model;
  final IconData icon;
  final Color stripeColor;
  final String listRoute;
  final List<dynamic> domain;
}

/// The "portal cards" section that used to live at the bottom of the
/// student home in the old app. Each card runs `search_count` on its
/// model — an ACL-denied or missing-model probe returns 0 and the card
/// gracefully shows `0` instead of an error.
class PortalCardsGrid extends StatefulWidget {
  const PortalCardsGrid({super.key});

  @override
  State<PortalCardsGrid> createState() => _PortalCardsGridState();
}

class _PortalCardsGridState extends State<PortalCardsGrid> {
  static const _specs = <PortalCardSpec>[
    PortalCardSpec(
      title: 'My Attendance',
      description: 'Daily attendance history',
      model: 'edu.attendance',
      icon: Icons.groups,
      stripeColor: Color(0xFF23A9AA),
      listRoute: '/list/attendance',
    ),
    PortalCardSpec(
      title: 'My Homework',
      description: 'Assignments and due dates',
      model: 'edu.homework',
      icon: Icons.menu_book,
      stripeColor: Color(0xFFF57C00),
      listRoute: '/list/homework',
    ),
    PortalCardSpec(
      title: 'Notices',
      description: 'Circulars from the school',
      model: 'edu.circular',
      icon: Icons.campaign,
      stripeColor: Color(0xFFE53935),
      listRoute: '/list/notice',
    ),
    PortalCardSpec(
      title: 'Remarks',
      description: 'Queries and feedback',
      model: 'edu.query',
      icon: Icons.chat_bubble_outline,
      stripeColor: Color(0xFF1976D2),
      listRoute: '/list/remarks',
    ),
    PortalCardSpec(
      title: 'Fees',
      description: 'Balance and receipts',
      model: 'edu.student.fee',
      icon: Icons.receipt_long,
      stripeColor: Color(0xFF7B1FA2),
      listRoute: '/list/fees',
    ),
    PortalCardSpec(
      title: 'Activity',
      description: 'Assigned tasks and reminders',
      model: 'mail.activity',
      icon: Icons.notifications,
      stripeColor: Color(0xFFFB8C00),
      listRoute: '/list/activity',
    ),
  ];

  late Future<Map<String, _Probe>> _counts;

  @override
  void initState() {
    super.initState();
    _counts = _loadCounts();
  }

  Future<Map<String, _Probe>> _loadCounts() async {
    final result = <String, _Probe>{};
    final futures = _specs.map((s) async {
      try {
        final n = await sl<OdooClient>().callKw<int>(
          model: s.model,
          method: 'search_count',
          args: [s.domain],
        );
        result[s.model] = _Probe.ok(n);
      } catch (_) {
        result[s.model] = const _Probe.failed();
      }
    });
    await Future.wait(futures);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, _Probe>>(
      future: _counts,
      builder: (context, snap) {
        final counts = snap.data ?? const <String, _Probe>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8, left: 4),
              child: Text(
                'My Portal',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                for (final s in _specs) _Card(spec: s, probe: counts[s.model]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Probe {
  const _Probe.ok(this.count) : failed = false;
  const _Probe.failed() : count = 0, failed = true;
  final int count;
  final bool failed;
}

class _Card extends StatelessWidget {
  const _Card({required this.spec, required this.probe});
  final PortalCardSpec spec;
  final _Probe? probe;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push(spec.listRoute),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left-side colored stripe — the old app's signature detail.
            Container(width: 6, color: spec.stripeColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(spec.icon, color: spec.stripeColor, size: 22),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: spec.stripeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            probe == null
                                ? '…'
                                : (probe!.failed ? '!' : '${probe!.count}'),
                            style: TextStyle(
                              color: probe?.failed == true
                                  ? OdooEduColors.danger
                                  : spec.stripeColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      spec.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      spec.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: OdooEduColors.textMuted,
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
