import '../../../core/config/app_config.dart';
import '../../../core/network/odoo_client.dart';
import '../domain/odoo_module.dart';

/// Reads Odoo's menu tree (`ir.ui.menu`) and turns it into [OdooModule]s that
/// the module grid and drawer can render.
class ModuleRemoteDataSource {
  ModuleRemoteDataSource(this._client);
  final OdooClient _client;

  /// Top-level modules with children **eagerly materialised**. We pull
  /// EVERY `ir.ui.menu` row in one call and rebuild the parent→child tree
  /// in memory so the drawer's expansion tiles show real leaves instead
  /// of an empty child list.
  ///
  /// Odoo's `child_id` field is a One2many; search_read returns only ids
  /// for it — that's why folder menus were expanding into nothing.
  Future<List<OdooModule>> getModuleTree() async {
    final base = AppConfig.serverUrl;
    try {
      final rows = await _client.callKw<List<dynamic>>(
        model: 'ir.ui.menu',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'domain': const [],
          'fields': const [
            'id',
            'name',
            'web_icon',
            'action',
            'parent_id',
            'sequence',
          ],
          'order': 'sequence, id',
          'limit': 2000,
        },
      );
      return _buildTree(rows, base);
    } catch (_) {
      return const [];
    }
  }

  /// Groups the flat menu rows by `parent_id` and returns the roots with
  /// each parent's `children` fully populated.
  List<OdooModule> _buildTree(List<dynamic> rows, String base) {
    final byId = <int, Map<String, dynamic>>{};
    final childrenByParent = <int?, List<int>>{};
    for (final r in rows) {
      if (r is! Map) continue;
      final data = Map<String, dynamic>.from(r);
      final id = (data['id'] as num?)?.toInt();
      if (id == null) continue;
      byId[id] = data;
      final parentRaw = data['parent_id'];
      final parent = parentRaw is List && parentRaw.isNotEmpty
          ? (parentRaw[0] as num).toInt()
          : null;
      childrenByParent.putIfAbsent(parent, () => []).add(id);
    }

    OdooModule build(int id) {
      final data = byId[id]!;
      final childIds = childrenByParent[id] ?? const [];
      final parsed = _parse(data, base);
      return OdooModule(
        id: parsed.id,
        displayName: parsed.displayName,
        iconUrl: parsed.iconUrl,
        action: parsed.action,
        technicalName: parsed.technicalName,
        children: [for (final c in childIds) build(c)],
        childIds: childIds,
      );
    }

    final rootIds = childrenByParent[null] ?? const [];
    return [for (final id in rootIds) build(id)];
  }

  /// Reads child rows for a given [parentId] — used when the user taps a
  /// folder menu that only came back with `childIds`.
  Future<List<OdooModule>> getChildren(List<int> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final rows = await _client.callKw<List<dynamic>>(
        model: 'ir.ui.menu',
        method: 'read',
        args: [ids],
        kwargs: <String, dynamic>{
          'fields': const ['id', 'name', 'web_icon', 'action', 'child_id'],
        },
      );
      return [
        for (final r in rows)
          if (r is Map)
            _parse(Map<String, dynamic>.from(r), AppConfig.serverUrl),
      ];
    } catch (_) {
      return const [];
    }
  }

  OdooModule _parse(Map<String, dynamic> json, String baseUrl) {
    String? icon;
    final webIcon = json['web_icon'];
    if (webIcon is String && webIcon.isNotEmpty) {
      final parts = webIcon.split(',');
      if (parts.length == 2) {
        final mod = parts[0].trim();
        var path = parts[1].trim();
        if (path.startsWith('/')) path = path.substring(1);
        final trimmedBase = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;
        icon = '$trimmedBase/$mod/$path';
      } else {
        icon = webIcon.startsWith('http') ? webIcon : '$baseUrl$webIcon';
      }
    }

    final actionVal = json['action'];
    final actionStr = (actionVal is String && actionVal.isNotEmpty)
        ? actionVal
        : null;

    final children = json['child_id'];
    final childIds = children is List
        ? [
            for (final c in children)
              if (c is int) c,
          ]
        : null;

    return OdooModule(
      id: (json['id'] as num).toInt(),
      displayName: (json['name'] as String?) ?? 'Untitled',
      iconUrl: icon,
      action: actionStr,
      technicalName: actionStr ?? '',
      childIds: childIds,
    );
  }
}
