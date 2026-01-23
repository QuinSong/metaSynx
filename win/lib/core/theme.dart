import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF00D4AA);
  static const Color background = Color(0xFF0A0E14);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceAlt = Color(0xFF0D1117);
  static const Color border = Color(0xFF30363D);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF8B949E);
  static const Color error = Colors.red;
  static const Color warning = Colors.orange;

  static Color primaryWithOpacity(double opacity) => primary.withOpacity(opacity);
}

class AppTextStyles {
  static const TextStyle heading = TextStyle(
    fontSize: 20,
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
    fontSize: 14,
    letterSpacing: 3,
    color: AppColors.textSecondary,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 13,
    color: AppColors.textMuted,
  );

  static const TextStyle monoLarge = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 18,
    fontWeight: FontWeight.bold,
    letterSpacing: 2,
    color: AppColors.textPrimary,
  );

  static const TextStyle logEntry = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 13,
    color: AppColors.textMuted,
  );
}
