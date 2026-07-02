import 'package:flutter/material.dart';

/// Palette shared across the app. Centralised so re-branding the tenant
/// only touches one file.
class OdooEduColors {
  OdooEduColors._();

  // Odoo's own brand purple — matches the old app's AppBar / drawer /
  // primary buttons. The teal accents inside the student mockup card
  // stay teal (hardcoded there on purpose to match the design), so this
  // only affects app chrome.
  static const Color brand = Color(0xFF875A7B);
  static const Color brandDark = Color(0xFF5E3F55);
  static const Color accent = Color(0xFF1E88E5);
  static const Color danger = Color(0xFFE53935);
  static const Color warning = Color(0xFFF57C00);
  static const Color success = Color(0xFF2ECC71);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color surfaceMuted = Color(0xFFF5F7FA);
}
