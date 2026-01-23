import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart' as relay;

class ConnectionIndicator extends StatelessWidget {
  final relay.ConnectionState connectionState;
  final bool bridgeConnected;

  const ConnectionIndicator({
    super.key,
    required this.connectionState,
    required this.bridgeConnected,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String text;

    if (connectionState == relay.ConnectionState.connected && bridgeConnected) {
      color = AppColors.primary;
      text = 'Paired';
    } else if (connectionState == relay.ConnectionState.connected) {
      color = AppColors.warning;
      text = 'Waiting for Bridge';
    } else if (connectionState == relay.ConnectionState.connecting) {
      color = AppColors.warning;
      text = 'Connecting...';
    } else {
      color = AppColors.textSecondary;
      text = 'Disconnected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}