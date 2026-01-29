import 'package:flutter/material.dart';
import '../core/theme.dart';

class PairedStatus extends StatelessWidget {
  final String? deviceName;
  final bool isActive;
  final bool isConnected;

  const PairedStatus({
    super.key,
    this.deviceName,
    this.isActive = true,
    this.isConnected = true,
  });

  @override
  Widget build(BuildContext context) {
    // Determine color and status based on connection and activity
    Color color;
    String statusText;
    IconData icon;
    
    if (!isConnected) {
      // Disconnected (network error, etc.) - show red
      color = AppColors.error;
      statusText = 'Connection Lost';
      icon = Icons.error_outline;
    } else if (isActive) {
      // Connected and active - show green
      color = AppColors.primary;
      statusText = 'Successfully Paired';
      icon = Icons.check_circle;
    } else {
      // Connected but idle - show orange
      color = AppColors.warning;
      statusText = 'Idle';
      icon = Icons.pause_circle_filled;
    }
    
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 64,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            statusText,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
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