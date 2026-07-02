import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Central runtime config — server URL + Odoo database. Everything else in the
/// app reads from here so switching the target server is a single write.
class AppConfig {
  AppConfig._();

  /// Where Odoo lives. Native builds embed the production URL; web builds
  /// default to the empty string so Dio issues requests relative to the page
  /// origin (behind the CORS proxy).
  static String serverUrl = _platformDefaultUrl;
  static String defaultDatabase = 'EducationManagement';
  static const int defaultPageSize = 50;

  /// Production Odoo endpoint used on native and as the in-app default.
  static const String productionUrl = 'http://188.245.169.118:20064';

  static String get _platformDefaultUrl => kIsWeb ? '' : productionUrl;

  /// Reads any overrides the user saved through the "Change Server" screen.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('odoo_url');
      if (kIsWeb && stored == productionUrl) {
        serverUrl = _platformDefaultUrl;
      } else {
        serverUrl = stored ?? _platformDefaultUrl;
      }
      defaultDatabase = prefs.getString('odoo_db') ?? 'EducationManagement';
    } catch (_) {
      // Fall back to compile-time defaults on any error.
    }
  }

  static Future<void> saveUrl(String url) async {
    var formatted = url.trim();
    if (formatted.endsWith('/')) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    serverUrl = formatted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('odoo_url', formatted);
  }

  static Future<void> saveDb(String db) async {
    defaultDatabase = db.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('odoo_db', db.trim());
  }
}
