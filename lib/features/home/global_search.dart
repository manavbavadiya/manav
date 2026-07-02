import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/odoo_client.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

/// Global search across the key Odoo models the app already renders.
/// Each model probe uses `search_read` with `name` ilike + a small limit
/// so a single query fans out to eight parallel RPCs. Missing / ACL-denied
/// models silently drop out of the results.
class OdooGlobalSearch extends StatefulWidget {
  const OdooGlobalSearch({super.key});

  @override
  State<OdooGlobalSearch> createState() => _OdooGlobalSearchState();
}

class _OdooGlobalSearchState extends State<OdooGlobalSearch> {
  final _ctrl = TextEditingController();
  Future<List<_Hit>>? _future;

  static const _targets = <({String model, String label, String route})>[
    (model: 'edu.student', label: 'Students', route: '/list/students'),
    (model: 'edu.homework', label: 'Homework', route: '/list/homework'),
    (model: 'edu.circular', label: 'Notices', route: '/list/notice'),
    (model: 'edu.query', label: 'Queries', route: '/list/remarks'),
    (model: 'edu.attendance', label: 'Attendance', route: '/list/attendance'),
    (model: 'edu.student.fee', label: 'Fees', route: '/list/fees'),
    (model: 'edu.exam.session', label: 'Exams', route: '/list/exam'),
    (model: 'res.partner', label: 'Contacts', route: '/list/partner'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<List<_Hit>> _search(String q) async {
    if (q.trim().isEmpty) return const [];
    final hits = <_Hit>[];
    final futures = _targets.map((t) async {
      try {
        final rows = await sl<OdooClient>().callKw<List<dynamic>>(
          model: t.model,
          method: 'search_read',
          args: const [],
          kwargs: <String, dynamic>{
            'domain': [
              ['name', 'ilike', q],
            ],
            'fields': const ['id', 'name'],
            'limit': 5,
          },
        );
        for (final r in rows) {
          if (r is Map) {
            final name = r['name']?.toString() ?? '(no name)';
            final id = r['id'] is num ? (r['id'] as num).toInt() : 0;
            hits.add(
              _Hit(
                model: t.model,
                label: t.label,
                title: name,
                id: id,
                route: t.route,
              ),
            );
          }
        }
      } catch (_) {
        // ACL / missing model → skip.
      }
    });
    await Future.wait(futures);
    hits.sort((a, b) => a.label.compareTo(b.label));
    return hits;
  }

  void _submit(String q) {
    setState(() => _future = _search(q));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Search students, homework, fees…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _submit(_ctrl.text),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        if (_future == null)
          const Expanded(child: _EmptyIntro())
        else
          Expanded(
            child: FutureBuilder<List<_Hit>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final hits = snap.data ?? const [];
                if (hits.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matches.',
                      style: TextStyle(color: OdooEduColors.textMuted),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final h = hits[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: OdooEduColors.brand.withValues(
                          alpha: 0.12,
                        ),
                        child: const Icon(
                          Icons.article_outlined,
                          color: OdooEduColors.brand,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        h.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        h.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: OdooEduColors.textMuted,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(h.route),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Hit {
  const _Hit({
    required this.model,
    required this.label,
    required this.title,
    required this.id,
    required this.route,
  });
  final String model;
  final String label;
  final String title;
  final int id;
  final String route;
}

class _EmptyIntro extends StatelessWidget {
  const _EmptyIntro();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.black26),
          SizedBox(height: 12),
          Text(
            'Type a query and press search.',
            style: TextStyle(color: OdooEduColors.textMuted),
          ),
        ],
      ),
    );
  }
}
