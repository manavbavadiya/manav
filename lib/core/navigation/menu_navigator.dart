import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/domain/odoo_module.dart';

/// Currently-active module id, threaded to the drawer so tiles that point
/// at the page the user is on can render in red. In-memory only — the
/// marker is about the live nav stack, not durable state.
final ValueNotifier<int?> activeMenuId = ValueNotifier<int?>(null);

/// Decides what to push when a module tile is tapped.
///
///   1. Folder menu (has children) → `/menus/:id`.
///   2. Leaf with an action → `/web_action/<id>?title=…`.
///   3. Fallback → `/menus/:id` (page-level handler).
void navigateToMenuWithRouter(GoRouter router, OdooModule m) {
  activeMenuId.value = m.id;
  final hasChildren =
      m.children.isNotEmpty || (m.childIds != null && m.childIds!.isNotEmpty);
  if (hasChildren) {
    router.push('/menus/${m.id}', extra: m);
    return;
  }
  final actionId = extractActionId(m);
  if (actionId != null) {
    final title = Uri.encodeQueryComponent(m.displayName);
    router.push('/web_action/$actionId?title=$title');
    return;
  }
  router.push('/menus/${m.id}', extra: m);
}

/// Same decision as [navigateToMenuWithRouter] but returns the target path
/// (no query string) instead of pushing. Used by the drawer's highlight to
/// compare each tile against the router's current location.
String menuTargetRoute(OdooModule m) {
  final hasChildren =
      m.children.isNotEmpty || (m.childIds != null && m.childIds!.isNotEmpty);
  if (hasChildren) return '/menus/${m.id}';
  final actionId = extractActionId(m);
  if (actionId != null) return '/web_action/$actionId';
  return '/menus/${m.id}';
}

int? extractActionId(OdooModule m) {
  final raw = m.action ?? '';
  if (raw.contains(',')) {
    return int.tryParse(raw.split(',')[1]);
  }
  return null;
}

void navigateToMenu(BuildContext context, OdooModule m) {
  navigateToMenuWithRouter(GoRouter.of(context), m);
}
