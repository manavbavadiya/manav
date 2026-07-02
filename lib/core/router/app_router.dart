import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/auth/onboarding_page.dart';
import '../../features/auth/server_config_page.dart';
import '../../features/auth/splash_page.dart';
import '../../features/home/admin_home_page.dart';
import '../../features/home/domain/odoo_module.dart';
import '../../features/home/presentation/menu_page.dart';
import '../../features/home/student_home_page.dart';
import '../../features/webview/web_action_page.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/server_config',
        builder: (context, state) => const ServerConfigPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/student',
        builder: (context, state) => const StudentHomePage(),
      ),
      // Alias — UserRole.postLoginRoute returns `/portal` for both student
      // and parent, so map it to the same page.
      GoRoute(
        path: '/portal',
        builder: (context, state) => const StudentHomePage(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminHomePage(),
      ),
      GoRoute(
        path: '/menus/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final parent = state.extra is OdooModule
              ? state.extra as OdooModule
              : null;
          return MenuPage(menuId: id, parent: parent);
        },
      ),
      GoRoute(
        path: '/web_action/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          final title = state.uri.queryParameters['title'];
          return WebActionPage(actionId: id, title: title);
        },
      ),
      // Generic list routes for the student dashboard's quick-action tiles.
      // Each `kind` maps to a curated (model, fields, order) tuple in
      // `_listPageFor` — keeps route definitions declarative and avoids a
      // dedicated feature folder per model until we truly need one.
      GoRoute(
        path: '/list/:kind',
        builder: (context, state) =>
            _listPageFor(state.pathParameters['kind']!),
      ),
    ],
  );
}

/// Portal / quick-access card → Odoo destination.
///
/// - `model`: internal user route. `WebActionPage` looks up the first
///   `ir.actions.act_window` whose `res_model` matches and embeds
///   `/odoo/action-<id>` — the backend admin URL.
/// - `portalPath`: portal user route. Same page embedded via
///   `/my/<slug>` — the OpenEducat portal template, which is what
///   students / parents have ACL for. `/odoo/*` bounces them to
///   `/web/login`, so the page comes up empty.
/// - `path`: hard override that skips both. Used for pages that only
///   exist under `/my/` (Addresses, Security).
///
/// WebActionPage picks the right one at open time by reading the stored
/// `isPortal` flag from SessionStorage.
typedef PortalPathEntry = ({
  String title,
  String? model,
  String? portalPath,
  String? path,
});

const _portalPaths = <String, PortalPathEntry>{
  'attendance': (
    title: 'Attendance',
    model: 'edu.attendance',
    portalPath: '/my/attendance',
    path: null,
  ),
  'homework': (
    title: 'Home Work',
    model: 'edu.homework',
    portalPath: '/my/homework',
    path: null,
  ),
  'notice': (
    title: 'Circulars',
    model: 'edu.circular',
    portalPath: '/my/circular',
    path: null,
  ),
  'remarks': (
    title: 'Queries & Complaints',
    model: 'edu.query',
    portalPath: '/my/query',
    path: null,
  ),
  'fees': (
    title: 'Your Fees',
    model: 'edu.student.fee',
    portalPath: '/my/fees',
    path: null,
  ),
  'activity': (
    title: 'Activity',
    model: 'mail.activity',
    portalPath: null,
    path: null,
  ),
  'timetable': (
    title: 'Timetable',
    model: 'edu.timetable',
    portalPath: '/my/timetable',
    path: null,
  ),
  'transport': (
    title: 'Transportation',
    model: 'edu.transport',
    portalPath: '/my/transportation',
    path: null,
  ),
  'meetings': (
    title: 'Parents Meetings',
    model: 'edu.parents.meeting',
    portalPath: '/my/parents_meeting',
    path: null,
  ),
  'holidays': (
    title: 'Holidays',
    model: 'holiday.holiday',
    portalPath: '/my/holidays',
    path: null,
  ),
  'leaves': (
    title: 'Leaves',
    model: 'student.leave',
    portalPath: '/my/leaves',
    path: null,
  ),
  'exam-results': (
    title: 'Exam Results',
    model: 'edu.exam.rank',
    portalPath: '/my/exam_result',
    path: null,
  ),
  'certificates': (
    title: 'Certificates',
    model: 'edu.exam.rank',
    portalPath: '/my/certificate',
    path: null,
  ),
  'students': (
    title: 'Students',
    model: 'edu.student',
    portalPath: null,
    path: null,
  ),
  'profile': (
    title: 'Student Profile',
    model: null,
    portalPath: null,
    path: '/my/account',
  ),
  'addresses': (
    title: 'Addresses',
    model: null,
    portalPath: null,
    path: '/my/account',
  ),
  'security': (
    title: 'Connection & Security',
    model: null,
    portalPath: null,
    path: '/my/security',
  ),
  'partner': (
    title: 'Contacts',
    model: 'res.partner',
    portalPath: null,
    path: null,
  ),
  'exam': (
    title: 'Exams',
    model: 'edu.exam.session',
    portalPath: null,
    path: null,
  ),
  'competitions': (
    title: 'Competitions',
    model: 'edu.exam.competition.match',
    portalPath: null,
    path: null,
  ),
};

Widget _listPageFor(String kind) {
  final entry = _portalPaths[kind];
  if (entry == null) {
    return Scaffold(
      appBar: AppBar(title: Text(kind)),
      body: const Center(child: Text('Unknown list target.')),
    );
  }
  return WebActionPage(
    title: entry.title,
    model: entry.model,
    portalPath: entry.portalPath,
    path: entry.path,
  );
}
