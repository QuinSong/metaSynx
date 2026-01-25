import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF00D4AA);
  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF161B22);
  static const Color border = Color(0xFF30363D);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF9CA3AF); // Brighter (was 0xFF6B7280)
  static const Color textMuted = Color(0xFF8B949E);
  static const Color error = Colors.red;
  static const Color warning = Colors.orange;

  // With opacity helpers
  static Color primaryWithOpacity(double opacity) => primary.withOpacity(opacity);
  static Color borderWithOpacity(double opacity) => border.withOpacity(opacity);
}

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
    color: AppColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    color: AppColors.textPrimary,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    letterSpacing: 2,
    color: AppColors.textSecondary,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );
}