import '../../../core/config/app_config.dart';
import '../../../core/network/odoo_client.dart';
import '../../../core/session/session_storage.dart';

/// Snapshot of the student profile shown on the portal home card, plus the
/// derived exam rank pulled from `edu.exam.rank`. One shape simplifies the
/// FutureBuilder in the page.
class StudentProfile {
  const StudentProfile({
    required this.studentId,
    required this.name,
    required this.grNo,
    required this.rollNo,
    required this.standard,
    required this.className,
    required this.photoUrl,
    required this.schoolName,
    required this.examRank,
  });

  final int? studentId;
  final String name;
  final String grNo;
  final String rollNo;
  final String standard;
  final String className;
  final String? photoUrl;
  final String schoolName;

  /// Best available rank from the materialised `edu.exam.rank` view.
  /// Null when the student has no attempts or the model isn't installed.
  final int? examRank;

  static const empty = StudentProfile(
    studentId: null,
    name: '',
    grNo: '',
    rollNo: '',
    standard: '',
    className: '',
    photoUrl: null,
    schoolName: '',
    examRank: null,
  );
}

/// Reads `edu.student` for the signed-in user and pulls a matching
/// `edu.exam.rank` row for the header medal. Every RPC is wrapped in a
/// try/catch so ACL errors on portal users degrade gracefully — a student
/// without a linked record still sees a usable dashboard.
class StudentProfileDataSource {
  StudentProfileDataSource(this._client, this._session);
  final OdooClient _client;
  final SessionStorage _session;

  Future<StudentProfile> load() async {
    final meta = await _session.getMeta();
    final uid = meta.uid;
    if (uid == null) return StudentProfile.empty;

    // School name — `res.company.name` for the user's default company.
    String schoolName = '';
    try {
      final companies = await _client.callKw<List<dynamic>>(
        model: 'res.company',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'domain': const [],
          'fields': const ['name'],
          'limit': 1,
        },
      );
      if (companies.isNotEmpty && companies.first is Map) {
        schoolName = (companies.first as Map)['name']?.toString() ?? '';
      }
    } catch (_) {}

    // Student — `edu.student.user_id = uid` is the canonical link.
    Map<String, dynamic>? row;
    try {
      final rows = await _client.callKw<List<dynamic>>(
        model: 'edu.student',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'domain': [
            ['user_id', '=', uid],
          ],
          'fields': const [
            'id',
            'full_name',
            'name',
            'gr_no',
            'roll_no',
            'standard_id',
            'division_id',
            'image_1920',
            'partner_id',
          ],
          'limit': 1,
        },
      );
      if (rows.isNotEmpty && rows.first is Map) {
        row = Map<String, dynamic>.from(rows.first as Map);
      }
    } catch (_) {}

    final data = row ?? const <String, dynamic>{};
    final studentId = data['id'] is num ? (data['id'] as num).toInt() : null;
    final grNo = (data['gr_no'] is String) ? data['gr_no'] as String : '';
    final rollNo = data['roll_no']?.toString() ?? '';
    final standard = _many2oneLabel(data['standard_id']);
    final className = _many2oneLabel(data['division_id']);
    final nameFromFull = (data['full_name'] is String)
        ? data['full_name'] as String
        : '';
    final nameFromShort = (data['name'] is String)
        ? data['name'] as String
        : '';
    final userName = (nameFromFull.isNotEmpty
        ? nameFromFull
        : (nameFromShort.isNotEmpty ? nameFromShort : (meta.userName ?? '')));

    // Photo — served through /web/image so cookies / CORS proxy handle
    // auth. `image_1920` returns `false` when unset, so we only build the
    // URL when we actually have an id AND a non-false marker.
    String? photoUrl;
    if (studentId != null && data['image_1920'] != false) {
      final base = AppConfig.serverUrl.endsWith('/')
          ? AppConfig.serverUrl.substring(0, AppConfig.serverUrl.length - 1)
          : AppConfig.serverUrl;
      photoUrl =
          '$base/web/image?model=edu.student&field=image_1920&id=$studentId&unique=1';
    }

    // Rank — `edu.exam.rank` is keyed by `student_id` (a res.partner).
    // If we don't have the student's partner id we can't join; skip.
    int? rank;
    final partner = data['partner_id'];
    final partnerId = partner is List && partner.isNotEmpty && partner[0] is num
        ? (partner[0] as num).toInt()
        : null;
    if (partnerId != null) {
      try {
        final rows = await _client.callKw<List<dynamic>>(
          model: 'edu.exam.rank',
          method: 'search_read',
          args: const [],
          kwargs: <String, dynamic>{
            'domain': [
              // student_id on edu.exam.rank is a res.partner (verified in
              // addons repo — matches the student.partner_id link above).
              ['student_id', '=', partnerId],
            ],
            'fields': const ['rank'],
            'order': 'rank asc',
            'limit': 1,
          },
        );
        if (rows.isNotEmpty && rows.first is Map) {
          final r = (rows.first as Map)['rank'];
          if (r is num) rank = r.toInt();
        }
      } catch (_) {}
    }

    return StudentProfile(
      studentId: studentId,
      name: userName,
      grNo: grNo,
      rollNo: rollNo,
      standard: standard,
      className: className,
      photoUrl: photoUrl,
      schoolName: schoolName,
      examRank: rank,
    );
  }

  String _many2oneLabel(dynamic v) {
    if (v is List && v.length >= 2 && v[1] is String) return v[1] as String;
    return '';
  }
}
