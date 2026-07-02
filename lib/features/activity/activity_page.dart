import 'package:flutter/material.dart';

import '../../core/network/odoo_client.dart';
import '../../core/session/session_storage.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

class _Activity {
  const _Activity({
    required this.id,
    required this.summary,
    required this.resName,
    required this.resModel,
    required this.date,
    required this.state,
    required this.activityType,
  });
  final int id;
  final String summary;
  final String resName;
  final String resModel;
  final String date;
  final String state;
  final String activityType;
}

/// Activity tab body — lists the signed-in user's pending `mail.activity`
/// records, ordered by deadline. Pull-to-refresh re-runs the search_read.
class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late Future<List<_Activity>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_Activity>> _load() async {
    try {
      final meta = await sl<SessionStorage>().getMeta();
      final uid = meta.uid;
      if (uid == null) return const [];
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'mail.activity',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'domain': [
            ['user_id', '=', uid],
          ],
          'fields': const [
            'id',
            'summary',
            'res_model',
            'res_name',
            'date_deadline',
            'state',
            'activity_type_id',
          ],
          'order': 'date_deadline asc',
          'limit': 50,
        },
      );
      return [
        for (final r in rows)
          if (r is Map) _fromJson(Map<String, dynamic>.from(r)),
      ];
    } catch (_) {
      return const [];
    }
  }

  _Activity _fromJson(Map<String, dynamic> j) {
    final t = j['activity_type_id'];
    final typeName = t is List && t.length >= 2 ? '${t[1]}' : '';
    final date = j['date_deadline'];
    return _Activity(
      id: (j['id'] as num).toInt(),
      summary: (j['summary'] is String) ? j['summary'] as String : '',
      resName: (j['res_name'] as String?) ?? '',
      resModel: (j['res_model'] as String?) ?? '',
      date: date is String ? date : '',
      state: (j['state'] as String?) ?? '',
      activityType: typeName,
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
      child: FutureBuilder<List<_Activity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: Color(0x11000000)),
            itemBuilder: (_, i) => _Tile(activity: items[i]),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.activity});
  final _Activity activity;

  Color get _color {
    switch (activity.state) {
      case 'overdue':
        return OdooEduColors.danger;
      case 'today':
        return OdooEduColors.warning;
      case 'planned':
        return OdooEduColors.brand;
      default:
        return OdooEduColors.textMuted;
    }
  }

  String get _headline {
    if (activity.summary.trim().isNotEmpty) return activity.summary;
    if (activity.activityType.isNotEmpty) return activity.activityType;
    return 'Activity';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _color.withValues(alpha: 0.15),
        child: Icon(Icons.event_note, color: _color),
      ),
      title: Text(
        _headline,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        activity.resName.isNotEmpty ? activity.resName : activity.resModel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: OdooEduColors.textMuted),
      ),
      trailing: activity.date.isEmpty
          ? null
          : Text(activity.date, style: TextStyle(fontSize: 12, color: _color)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'No new activity',
            style: TextStyle(
              fontSize: 15,
              color: OdooEduColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'Mail and activity notifications will appear here.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }
}
