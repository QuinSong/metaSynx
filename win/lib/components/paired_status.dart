import 'package:flutter/material.dart';
import '../core/theme.dart';

class PairedStatus extends StatelessWidget {
  final String? deviceName;

  const PairedStatus({
    super.key,
    this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryWithOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primaryWithOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.primary,
              size: 64,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Successfully Paired',
            style: AppTextStyles.title,
          ),
          const SizedBox(height: 8),
          Text(
            deviceName ?? 'Mobile Device',
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}
