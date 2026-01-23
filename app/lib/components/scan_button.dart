import 'package:flutter/material.dart';
import '../core/theme.dart';

class ScanButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ScanButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 24),
            SizedBox(width: 12),
            Text(
              'Scan QR Code',
              style: AppTextStyles.button,
            ),
          ],
        ),
      ),
    );
  }
}
