/// User role classification mirroring the old app's decision tree:
///
///   is_internal_user == true  → classify(groupNames)
///                                  ├─ admin       → admin
///                                  ├─ teacher     → teacher
///                                  └─ anything    → unknown
///
///   is_internal_user == false → classify(groupNames)
///                                  ├─ admin   → downgrade → student  (safety override)
///                                  ├─ teacher → downgrade → student  (safety override)
///                                  ├─ student → student
///                                  ├─ parent  → parent
///                                  └─ unknown → student            (share=true implies portal)
///
/// The `share == true` override at the top means even if a portal user is in
/// some custom group named "Faculty Assistant" or "Admin Helper" by mistake,
/// we never route them to /admin — Odoo's ACL would block them at the API
/// level anyway; this just narrows the UI to match.
enum UserRole {
  admin,
  teacher,
  student,
  parent,
  unknown;

  /// Where a session with this role should land after login.
  String get postLoginRoute {
    switch (this) {
      case UserRole.admin:
      case UserRole.teacher:
        return '/admin';
      case UserRole.student:
      case UserRole.parent:
        return '/portal';
      case UserRole.unknown:
        return '/portal';
    }
  }

  bool get isInternal => this == UserRole.admin || this == UserRole.teacher;
  bool get isPortal => !isInternal;

  String get displayLabel {
    switch (this) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.student:
        return 'Student';
      case UserRole.parent:
        return 'Parent';
      case UserRole.unknown:
        return 'User';
    }
  }

  String get storageKey => name;

  static UserRole fromStorage(String? raw) {
    if (raw == null) return UserRole.unknown;
    return UserRole.values.firstWhere(
      (r) => r.name == raw,
      orElse: () => UserRole.unknown,
    );
  }

  /// Classify a user given their raw group names + the `is_internal_user`
  /// flag from Odoo's authenticate response. See the file-level doc for
  /// the full decision tree.
  static UserRole classify(
    Iterable<String> groupNames, {
    required bool isInternalUser,
  }) {
    final lower = groupNames.map((g) => g.toLowerCase()).toList();
    final looksAdmin = lower.any(
      (g) =>
          g.contains('administrator') ||
          g.contains('settings') ||
          g.contains('internal user') && g.contains('administrator'),
    );
    final looksTeacher = lower.any(
      (g) =>
          g.contains('faculty') ||
          g.contains('teacher') ||
          g.contains('back office'),
    );
    final looksStudent = lower.any(
      (g) => g.contains('student') || g.contains('op / student'),
    );
    final looksParent = lower.any(
      (g) => g.contains('parent') || g.contains('guardian'),
    );

    if (isInternalUser) {
      if (looksAdmin) return UserRole.admin;
      if (looksTeacher) return UserRole.teacher;
      return UserRole.unknown;
    }

    // is_internal_user == false ⇒ portal-shaped user.
    // Downgrade any accidental admin/teacher group memberships.
    if (looksAdmin || looksTeacher) return UserRole.student;
    if (looksStudent) return UserRole.student;
    if (looksParent) return UserRole.parent;
    return UserRole.student;
  }
}
