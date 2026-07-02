/// Slim view of an `ir.ui.menu` row — the tree that drives the module drawer
/// and the module grid.
class OdooModule {
  const OdooModule({
    required this.id,
    required this.displayName,
    this.iconUrl,
    this.action,
    this.technicalName = '',
    this.children = const [],
    this.childIds,
  });

  final int id;
  final String displayName;
  final String? iconUrl;

  /// Raw Odoo action reference, e.g. `"ir.actions.act_window,123"` — used to
  /// build the WebView URL when there's no native renderer for the menu.
  final String? action;

  /// Best-effort model / technical name (`op.student`, etc.) used to route
  /// to the universal browser when supported.
  final String technicalName;

  /// Children materialised as full entities (top-level tree fetch).
  final List<OdooModule> children;

  /// Children references left as bare ids (lazy trees).
  final List<int>? childIds;
}
