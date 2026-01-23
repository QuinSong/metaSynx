import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart';

class StatusIndicator extends StatelessWidget {
  final ConnectionStatus status;

  const StatusIndicator({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case ConnectionStatus.connected:
        color = AppColors.primary;
        break;
      case ConnectionStatus.connecting:
        color = AppColors.warning;
        break;
      case ConnectionStatus.error:
        color = AppColors.error;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}
