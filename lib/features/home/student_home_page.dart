import 'dart:convert';
import 'dart:io' show Directory, File;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/odoo_client.dart';
import '../../injection_container.dart';
import '../auth/auth_bloc.dart';
import '../webview/pdf_download_stub.dart'
    if (dart.library.js_interop) '../webview/pdf_download_web.dart';
import '../webview/web_action_page.dart';
import '../webview/web_iframe_stub.dart'
    if (dart.library.js_interop) '../webview/web_iframe_web.dart';

/// Portal home for student / parent users. Redesigned to match the new
/// mockup: header, teal student profile card, two-column stat row
/// (Progress report + Exam rank), four quick-action tiles, "Show More"
/// button, blue "Result / Make Challenge" card. Bottom nav is a
/// four-tab strip — Home / Notice / Messages / Logout.
class StudentHomePage extends StatefulWidget {
  const StudentHomePage({super.key});

  @override
  State<StudentHomePage> createState() => _StudentHomePageState();
}

class _StudentHomePageState extends State<StudentHomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Unauthenticated) context.go('/login');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        // Keep every tab alive with an IndexedStack so switching Home
        // ↔ Notice ↔ Messages doesn't reload the tab from scratch or
        // lose the profile / iframe state each time.
        body: IndexedStack(
          index: _tab,
          children: const [
            _HomeTab(),
            _WebTab(path: '/my/circulars', title: 'Notice'),
            _WebTab(path: '/my/queries', title: 'Messages'),
          ],
        ),
        bottomNavigationBar: _BottomNav(
          selected: _tab,
          onTap: (i) {
            if (i == 3) {
              context.read<AuthBloc>().add(const AuthLogoutRequested());
              return;
            }
            setState(() => _tab = i);
          },
        ),
      ),
    );
  }
}

// ── Web-tab wrapper for the Notice / Messages bottom-nav slots ─────────────

/// Lightweight tab body: just a header strip + the Odoo portal iframe.
/// We deliberately do NOT wrap this in [WebActionPage] because that
/// widget owns its own Scaffold + AppBar with a back button, which
/// would pop the whole portal shell (kicking the user back to /login)
/// as soon as they tapped it inside a bottom-nav tab.
class _WebTab extends StatelessWidget {
  const _WebTab({required this.path, required this.title});
  final String path;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: const Color(0xFF875A75),
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 12,
            16,
            12,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: WebIframe(url: path)),
      ],
    );
  }
}

// ── Home tab ────────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _StudentProfile {
  const _StudentProfile({
    required this.id,
    required this.name,
    required this.grNo,
    required this.rollNo,
    required this.standard,
    required this.division,
    required this.photoBase64,
  });
  final int? id;
  final String name;
  final String grNo;
  final String rollNo;
  final String standard;
  final String division;
  final String? photoBase64;
}

class _RankInfo {
  const _RankInfo({required this.rank});
  final int? rank;
}

class _ChallengeInfo {
  const _ChallengeInfo({
    required this.total,
    required this.wins,
    required this.losses,
  });
  final int total;
  final int wins;
  final int losses;
}

class _HomeData {
  const _HomeData({
    required this.profile,
    required this.rank,
    required this.progress,
    required this.challenge,
  });
  final _StudentProfile? profile;
  final _RankInfo rank;
  final double progress;
  final _ChallengeInfo challenge;
}

class _HomeTabState extends State<_HomeTab> {
  late Future<_HomeData> _future;
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    _StudentProfile? profile;
    _RankInfo rank = const _RankInfo(rank: null);
    double progress = 0;
    _ChallengeInfo challenge = const _ChallengeInfo(
      total: 0,
      wins: 0,
      losses: 0,
    );
    int? studentId;
    try {
      final rows = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'edu.student',
        method: 'search_read',
        args: const [],
        kwargs: <String, dynamic>{
          'fields': const [
            'name',
            'surname',
            'full_name',
            'gr_no',
            'student_uid',
            'roll_no',
            'standard_id',
            'division_id',
            'image_1920',
          ],
          'limit': 1,
        },
      );
      if (rows.isNotEmpty) {
        final r = rows.first as Map;
        studentId = (r['id'] as num?)?.toInt();
        final display = _str(r['full_name']).isNotEmpty
            ? _str(r['full_name'])
            : _str(r['name']);
        profile = _StudentProfile(
          id: studentId,
          name: display.isEmpty ? 'Student' : display,
          // Prefer explicit GR / UID; fall back to Roll No so the row
          // never says "false" for a student whose school hasn't
          // populated one of the codes.
          grNo: _pick(r['gr_no'], r['student_uid']),
          rollNo: _str(r['roll_no']),
          standard: _rel(r['standard_id']),
          division: _rel(r['division_id']),
          photoBase64: r['image_1920'] is String
              ? r['image_1920'] as String
              : null,
        );
      }
    } catch (_) {}

    // Exam rank — try filtering to this student first; fall back to the
    // best rank the ACL exposes.
    try {
      final ranks = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'edu.exam.rank',
        method: 'search_read',
        args: [
          [
            if (studentId != null) ['student_id', '=', studentId],
          ],
        ],
        kwargs: const {
          'fields': ['rank'],
          'order': 'rank asc',
          'limit': 1,
        },
      );
      if (ranks.isNotEmpty) {
        final v = (ranks.first as Map)['rank'];
        rank = _RankInfo(rank: v is num ? v.toInt() : null);
      }
    } catch (_) {}

    // Attendance-based progress. Portal ACL blocks direct
    // `edu.attendance` access for students, so fall back to scraping
    // the numbers OpenEducat's own /my/attendance template already
    // renders (Days Present / Days Absent).
    try {
      int total = 0;
      int attended = 0;
      final atts = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'edu.attendance',
        method: 'search_read',
        args: [
          [
            if (studentId != null) ['student_id', '=', studentId],
          ],
        ],
        kwargs: const {'fields': ['state'], 'limit': 500},
      );
      total = atts.length;
      attended = atts
          .where((a) => a is Map && '${a['state']}' == 'present')
          .length;
      if (total > 0) progress = attended / total;
    } catch (_) {
      // ACL block — try the /my/attendance portal HTML fallback.
      try {
        final html = await sl<OdooClient>().fetchHtml('/my/attendance');
        final stats = _extractPortalNumbers(html, [
          'Days Present',
          'Days Absent',
          'Late Arrivals',
        ]);
        final present = stats['Days Present'] ?? 0;
        final absent = stats['Days Absent'] ?? 0;
        final late = stats['Late Arrivals'] ?? 0;
        final total = present + absent + late;
        if (total > 0) progress = present / total;
      } catch (_) {}
    }

    // Challenges — try direct RPC first, then fall back to the
    // /my/competitions portal HTML.
    try {
      final matches = await sl<OdooClient>().callKw<List<dynamic>>(
        model: 'edu.exam.competition.match',
        method: 'search_read',
        args: const [],
        kwargs: const {
          'fields': ['state', 'name'],
          'limit': 500,
        },
      );
      final total = matches.length;
      int wins = 0;
      int losses = 0;
      for (final m in matches) {
        if (m is! Map) continue;
        final s = '${m['state']}'.toLowerCase();
        if (s.contains('win') || s.contains('won')) wins++;
        if (s.contains('loss') || s.contains('lost')) losses++;
      }
      challenge = _ChallengeInfo(total: total, wins: wins, losses: losses);
    } catch (_) {
      try {
        final html = await sl<OdooClient>().fetchHtml('/my/competitions');
        final stats = _extractPortalNumbers(html, [
          'Total Matches',
          'Wins',
          'Losses',
          'Won',
          'Lost',
        ]);
        challenge = _ChallengeInfo(
          total: stats['Total Matches'] ?? 0,
          wins: stats['Wins'] ?? stats['Won'] ?? 0,
          losses: stats['Losses'] ?? stats['Lost'] ?? 0,
        );
      } catch (_) {}
    }

    return _HomeData(
      profile: profile,
      rank: rank,
      progress: progress,
      challenge: challenge,
    );
  }

  static String _rel(dynamic v) {
    if (v is List && v.length > 1) return '${v[1]}';
    return '';
  }

  /// Odoo returns `false` for empty many2one / char fields — we don't
  /// want that literal string showing up in the profile card.
  static String _str(dynamic v) {
    if (v == null || v == false || v == 'false') return '';
    return '$v';
  }

  /// First non-empty value in [candidates], stringified. Used when the
  /// same slot in the profile card might come from any of several
  /// columns (e.g. `gr_no` or `student_uid`).
  static String _pick(dynamic a, [dynamic b, dynamic c]) {
    for (final v in [a, b, c]) {
      final s = _str(v);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_HomeData>(
          future: _future,
          builder: (context, snap) {
            // First load: show a centered spinner. Once we have data
            // (or a pull-to-refresh is in flight), fall through to the
            // normal layout — RefreshIndicator handles the top wheel.
            if (snap.connectionState != ConnectionState.done &&
                snap.data == null) {
              return const Center(
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF139794)),
                  ),
                ),
              );
            }
            final d = snap.data;
            final profile = d?.profile;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SchoolHeader(
                  studentId: profile?.id,
                  studentName: profile?.name,
                ),
                const SizedBox(height: 12),
                _ProfileCard(profile: profile),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _ProgressCard(value: d?.progress ?? 0),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ExamRankCard(rank: d?.rank.rank),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _QuickActionsRow(),
                if (_showMore) ...[
                  const SizedBox(height: 12),
                  const _MoreActionsGrid(),
                ],
                const SizedBox(height: 12),
                _ShowMoreButton(
                  expanded: _showMore,
                  onTap: () => setState(() => _showMore = !_showMore),
                ),
                const SizedBox(height: 14),
                _ChallengeCard(info: d?.challenge),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SchoolHeader extends StatelessWidget {
  const _SchoolHeader({this.studentId, this.studentName});
  final int? studentId;
  final String? studentName;

  /// Save [bytes] as a PDF to a user-visible location and return the
  /// path we ended up writing to. Tries the shared Android Downloads
  /// folder first; falls back to the app's own documents directory
  /// when the emulated Download path isn't writable (iOS, sandboxed
  /// Android storage).
  static Future<String> _saveNativePdf(
    Uint8List bytes,
    String filename,
  ) async {
    // Prefer the shared Downloads directory so the user finds the PDF
    // in their phone's file manager.
    for (final path in [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
    ]) {
      final dir = Directory(path);
      if (await dir.exists()) {
        try {
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        } catch (_) {
          // Permission denied on newer Android — fall through.
        }
      }
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// First alphabetic character of [name], upper-cased. Falls back to
  /// `?` so the ID-card silhouette always has something inside.
  static String _initial(String? name) {
    if (name == null) return '?';
    for (final ch in name.trim().split('')) {
      if (RegExp(r'[A-Za-z]').hasMatch(ch)) return ch.toUpperCase();
    }
    return '?';
  }

  Future<void> _openIdCard(BuildContext context) async {
    final id = studentId;
    if (id == null) return; // Student record not loaded yet.
    final url = '/report/pdf/edu_student_mgmt.report_student_id_card/$id';
    final safe = (studentName ?? 'ID Card')
        .replaceAll(RegExp(r'[<>:"/\\|?*]+'), '')
        .trim();
    final filename = '${safe.isEmpty ? 'ID Card' : safe}.pdf';
    if (kIsWeb) {
      await downloadPdf(url, filename: filename);
      return;
    }
    // Native (Android APK / iOS): fetch the PDF bytes via Dio (session
    // cookie is already attached by OdooClient's jar) and drop them
    // straight into a shared Downloads directory so the file shows up
    // in the phone's file manager without bouncing through a WebView.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Downloading ID Card…'),
        duration: Duration(seconds: 2),
      ),
    );
    try {
      final bytes = await sl<OdooClient>().downloadBytes(url);
      final saved = await _saveNativePdf(bytes, filename);
      if (context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Saved to $saved'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text('Could not download: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Your School Name',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF16324F),
            ),
          ),
        ),
        InkWell(
          onTap: studentId == null ? null : () => _openIdCard(context),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              children: [
                // Lanyard clip — the small blue tab at the top.
                Container(
                  width: 6,
                  height: 12,
                  decoration: const BoxDecoration(color: Color(0xFF1F82BC)),
                ),
                // The ID card body — tall white rectangle with the
                // student initial + a short name/label stack.
                Container(
                  width: 38,
                  height: 52,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1F82BC),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _initial(studentName),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 26,
                        height: 2,
                        color: const Color(0xFFCBD5E1),
                      ),
                      Container(
                        width: 22,
                        height: 2,
                        color: const Color(0xFFCBD5E1),
                      ),
                      Container(
                        width: 14,
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F82BC),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ID Card',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF16324F),
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final _StudentProfile? profile;

  @override
  Widget build(BuildContext context) {
    final name = profile?.name ?? '—';
    final grNo = profile?.grNo ?? '';
    final rollNo = profile?.rollNo ?? '';
    final std = profile?.standard ?? '';
    final div = profile?.division ?? '';
    final photo = profile?.photoBase64;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/list/profile'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF139794), Color(0xFF0B7C79)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: ClipOval(
              child: photo != null && photo.isNotEmpty
                  ? Image.memory(
                      _decodeBase64(photo),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _AvatarFallback(name: name),
                    )
                  : _AvatarFallback(name: name),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _kv('GR No', grNo),
                const SizedBox(height: 4),
                _kv('Roll No', rollNo),
                const SizedBox(height: 6),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _kv('STD', std)),
                    Expanded(child: _kv('Class', div)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) {
    final display = v.trim().isEmpty ? '-' : v;
    return Row(
      children: [
        Text(
          '$k :- ',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          display,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name});
  final String name;

  /// First letter of the first word + first letter of the last word,
  /// upper-cased. "Susan David Vyas" → "SV". Single-word names return
  /// just the first letter. Any non-letter noise is stripped.
  String _initials() {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    String first(String w) {
      for (final ch in w.split('')) {
        if (RegExp(r'[A-Za-z]').hasMatch(ch)) return ch.toUpperCase();
      }
      return '';
    }
    if (parts.length == 1) return first(parts.first).isEmpty
        ? '?'
        : first(parts.first);
    final a = first(parts.first);
    final b = first(parts.last);
    final combined = '$a$b';
    return combined.isEmpty ? '?' : combined;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F82BC), Color(0xFF139794)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).clamp(0, 100).round();
    return Container(
      height: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFDDEEF7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Progress\nreport',
              style: TextStyle(
                color: Color(0xFF16324F),
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(76, 76),
                  painter: _RingPainter(value: value.clamp(0.0, 1.0)),
                ),
                Text(
                  '$pct %',
                  style: const TextStyle(
                    color: Color(0xFF16324F),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value});
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(6), 0, math.pi * 2, false, track);
    final progress = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF17B36B), Color(0xFF1F82BC)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(6),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

class _ExamRankCard extends StatelessWidget {
  const _ExamRankCard({required this.rank});
  final int? rank;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/list/exam-results'),
      child: Container(
        height: 130,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE7E2FA),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Exam',
              style: TextStyle(
                color: Color(0xFF16324F),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD34D), Color(0xFFE39A2A)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE39A2A).withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      rank == null ? '-' : '$rank',
                      style: const TextStyle(
                        color: Color(0xFF16324F),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE53935),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Your Rank',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1F82BC),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Result ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.title,
    required this.icon,
    required this.color,
    required this.route,
  });
  final String title;
  final IconData icon;
  final Color color;
  final String route;
}

const _quickActions = <_QuickAction>[
  _QuickAction(
    title: 'Attendance',
    icon: Icons.groups,
    color: Color(0xFF139794),
    route: '/list/attendance',
  ),
  _QuickAction(
    title: 'Home Work',
    icon: Icons.menu_book,
    color: Color(0xFF1F82BC),
    route: '/list/homework',
  ),
  _QuickAction(
    title: 'Circulars',
    icon: Icons.article_outlined,
    color: Color(0xFFE57B1F),
    route: '/list/notice',
  ),
  _QuickAction(
    title: 'Queries',
    icon: Icons.help_outline,
    color: Color(0xFF1565C0),
    route: '/list/remarks',
  ),
];

const _moreActions = <_QuickAction>[
  _QuickAction(
    title: 'Timetable',
    icon: Icons.grid_view_rounded,
    color: Color(0xFF7B3FE4),
    route: '/list/timetable',
  ),
  _QuickAction(
    title: 'Your Fees',
    icon: Icons.account_balance_wallet_outlined,
    color: Color(0xFF17A67A),
    route: '/list/fees',
  ),
  _QuickAction(
    title: 'Transport',
    icon: Icons.directions_bus_filled_outlined,
    color: Color(0xFFC62828),
    route: '/list/transport',
  ),
  _QuickAction(
    title: 'Meetings',
    icon: Icons.calendar_month_outlined,
    color: Color(0xFFE57B1F),
    route: '/list/meetings',
  ),
  _QuickAction(
    title: 'Certificates',
    icon: Icons.picture_as_pdf_outlined,
    color: Color(0xFFC62828),
    route: '/list/certificates',
  ),
  _QuickAction(
    title: 'Holidays',
    icon: Icons.flight_takeoff,
    color: Color(0xFFE57B1F),
    route: '/list/holidays',
  ),
  _QuickAction(
    title: 'Leaves',
    icon: Icons.event_busy,
    color: Color(0xFFC62828),
    route: '/list/leaves',
  ),
  _QuickAction(
    title: 'Exam Results',
    icon: Icons.emoji_events_outlined,
    color: Color(0xFF2E8B4A),
    route: '/list/exam-results',
  ),
  _QuickAction(
    title: 'Addresses',
    icon: Icons.place_outlined,
    color: Color(0xFF1565C0),
    route: '/list/addresses',
  ),
  _QuickAction(
    title: 'Connection & Security',
    icon: Icons.lock_outline,
    color: Color(0xFF1565C0),
    route: '/list/security',
  ),
];

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _quickActions.length; i++) ...[
            Expanded(child: _QuickTile(item: _quickActions[i])),
            if (i < _quickActions.length - 1)
              Container(
                width: 1,
                height: 40,
                color: const Color(0xFFE1E5EB),
              ),
          ],
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item});
  final _QuickAction item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(item.route),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, color: item.color, size: 26),
            const SizedBox(height: 6),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF16324F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreActionsGrid extends StatelessWidget {
  const _MoreActionsGrid();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E5EB)),
      ),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.9,
        children: [
          for (final a in _moreActions) _QuickTile(item: a),
        ],
      ),
    );
  }
}

class _ShowMoreButton extends StatelessWidget {
  const _ShowMoreButton({required this.expanded, required this.onTap});
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF117FB2),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                expanded ? 'Show Less' : 'Show More',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({required this.info});
  final _ChallengeInfo? info;

  @override
  Widget build(BuildContext context) {
    final total = info?.total ?? 0;
    final wins = info?.wins ?? 0;
    final losses = info?.losses ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF124962), Color(0xFF1A6E92)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            top: 6,
            child: Text(
              '🏆',
              style: TextStyle(
                fontSize: 72,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(
                child: Text(
                  'Result',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Center(
                child: Text(
                  'Challenge Yourself, Achieve More !',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Challenge',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$total',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Win / Loss',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$wins / $losses',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => context.push('/list/competitions'),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F82BC),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Make Challenge  ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bottom nav ──────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.selected, required this.onTap});
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE1E5EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              label: 'Home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              selected: selected == 0,
              onTap: () => onTap(0),
            ),
            _NavItem(
              label: 'Notice',
              icon: Icons.notifications_none,
              selectedIcon: Icons.notifications,
              selected: selected == 1,
              onTap: () => onTap(1),
            ),
            _NavItem(
              label: 'Messages',
              icon: Icons.chat_bubble_outline,
              selectedIcon: Icons.chat_bubble,
              selected: selected == 2,
              onTap: () => onTap(2),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => onTap(3),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF117FB2),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  children: [
                    Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, color: Colors.white, size: 16),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF117FB2) : const Color(0xFF7F8CA0);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

/// Extract stat cards like "<h2><span>4</span></h2>...Days Present" from
/// an OpenEducat portal HTML page. Returns `{ label: number }` for every
/// [labels] entry that we find. The pattern intentionally allows some
/// slop between the number and the label so template tweaks don't
/// break scraping.
Map<String, int> _extractPortalNumbers(String html, List<String> labels) {
  final out = <String, int>{};
  for (final label in labels) {
    final rx = RegExp(
      r'<h[1-6][^>]*>\s*(?:<span[^>]*>)?\s*(\d+)\s*(?:</span>)?\s*</h[1-6]>[\s\S]{0,300}?'
      + RegExp.escape(label),
      caseSensitive: false,
    );
    final m = rx.firstMatch(html);
    if (m != null) {
      out[label] = int.tryParse(m.group(1) ?? '') ?? 0;
    }
  }
  return out;
}

Uint8List _decodeBase64(String s) {
  try {
    return base64Decode(s);
  } catch (_) {
    return Uint8List(0);
  }
}
