import 'package:flutter/material.dart';

import '../../core/network/odoo_client.dart';
import '../../core/theme/odoo_edu_colors.dart';
import '../../injection_container.dart';

/// Generic list view over any Odoo model. Used to back the student
/// dashboard's four quick actions (Attendance / Home Work / Notice /
/// Remarks) without spinning up a dedicated feature folder per model.
///
/// - `model` + `fields` + `domain` decide what to fetch.
/// - `titleField` / `subtitleField` / `trailingField` decide what to show
///   on each row. Any of them can be null → the row degrades gracefully.
class OdooListPage extends StatefulWidget {
  const OdooListPage({
    super.key,
    required this.pageTitle,
    required this.model,
    required this.fields,
    this.domain = const [],
    this.order,
    this.limit = 100,
    this.titleField = 'name',
    this.subtitleField,
    this.trailingField,
    this.leadingIcon = Icons.circle_outlined,
  });

  final String pageTitle;
  final String model;
  final List<String> fields;
  final List<dynamic> domain;
  final String? order;
  final int limit;
  final String titleField;
  final String? subtitleField;
  final String? trailingField;
  final IconData leadingIcon;

  @override
  State<OdooListPage> createState() => _OdooListPageState();
}

class _OdooListPageState extends State<OdooListPage> {
  late Future<_LoadResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoadResult> _load() async {
    try {
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: widget.model,
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'domain': widget.domain,
          'fields': widget.fields,
          if (widget.order != null) 'order': widget.order,
          'limit': widget.limit,
        },
      );
      return _LoadResult(
        rows: [
          for (final r in rows)
            if (r is Map) Map<String, dynamic>.from(r),
        ],
      );
    } catch (e) {
      // Surface the friendly Dio / Odoo message so ACL / missing-model
      // situations are debuggable instead of silently returning zero.
      return _LoadResult(rows: const [], error: e.toString());
    }
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: OdooEduColors.brand,
        foregroundColor: Colors.white,
        title: Text(widget.pageTitle),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_LoadResult>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snap.data ?? const _LoadResult(rows: []);
            final items = result.rows;
            if (items.isEmpty) {
              return _EmptyState(
                title: widget.pageTitle,
                error: result.error,
                model: widget.model,
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: Color(0x11000000)),
              itemBuilder: (_, i) {
                final row = items[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: OdooEduColors.brand.withValues(
                      alpha: 0.12,
                    ),
                    child: Icon(widget.leadingIcon, color: OdooEduColors.brand),
                  ),
                  title: Text(
                    _stringify(row[widget.titleField]),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: widget.subtitleField == null
                      ? null
                      : Text(_stringify(row[widget.subtitleField!])),
                  trailing: widget.trailingField == null
                      ? null
                      : Text(
                          _stringify(row[widget.trailingField!]),
                          style: const TextStyle(
                            fontSize: 12,
                            color: OdooEduColors.textMuted,
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Odoo returns Many2one as `[id, "Display Name"]`, date/datetime as
  /// String, ints as num, `false` for null. Squeeze it all into a readable
  /// short string.
  String _stringify(dynamic v) {
    if (v == null || v == false) return '—';
    if (v is List) {
      if (v.length >= 2 && v[1] is String) return v[1] as String;
      return v.join(', ');
    }
    return v.toString();
  }
}

class _LoadResult {
  const _LoadResult({required this.rows, this.error});
  final List<Map<String, dynamic>> rows;
  final String? error;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.model, this.error});
  final String title;
  final String model;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final failed = error != null;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(
          failed ? Icons.error_outline : Icons.inbox_outlined,
          size: 64,
          color: failed ? OdooEduColors.danger : Colors.black26,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            failed ? 'Could not load $title' : 'No $title yet',
            style: TextStyle(
              fontSize: 15,
              color: failed ? OdooEduColors.danger : OdooEduColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Model: $model',
            style: const TextStyle(
              fontSize: 11,
              color: OdooEduColors.textMuted,
            ),
          ),
        ),
        if (failed) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: OdooEduColors.textMuted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
