import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart' as relay;

class ConnectionCard extends StatelessWidget {
  final relay.ConnectionState connectionState;
  final bool bridgeConnected;
  final String? roomId;
  final VoidCallback onDisconnect;

  const ConnectionCard({
    super.key,
    required this.connectionState,
    required this.bridgeConnected,
    required this.roomId,
    required this.onDisconnect,
  });

  void _showDisconnectDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.primary.withOpacity(0.5), width: 1),
        ),
        title: const Text('Disconnect', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to disconnect from the VPS?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDisconnect();
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (connectionState == relay.ConnectionState.connected && bridgeConnected) {
      return _buildConnectedCard(context);
    }

    if (connectionState == relay.ConnectionState.connected) {
      return _buildWaitingCard();
    }

    if (connectionState == relay.ConnectionState.connecting) {
      return _buildConnectingCard();
    }

    return _buildDisconnectedCard();
  }

  Widget _buildConnectedCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryWithOpacity(0.15),
            AppColors.primaryWithOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryWithOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryWithOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.link, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text('VPS Connected', style: AppTextStyles.title),
          ),
          IconButton(
            onPressed: () => _showDisconnectDialog(context),
            icon: const Icon(Icons.link_off, color: AppColors.textSecondary),
            tooltip: 'Disconnect',
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppColors.warning,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          const Text('Waiting for VPS', style: AppTextStyles.title),
          const SizedBox(height: 8),
          const Text(
            'Make sure the Windows Bridge is running',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: onDisconnect,
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 16),
          Text('Connecting...', style: AppTextStyles.title),
        ],
      ),
    );
  }

  Widget _buildDisconnectedCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.qr_code_scanner, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 16),
          const Text('No VPS Connected', style: AppTextStyles.title),
          const SizedBox(height: 8),
          const Text(
            'Scan the QR code on your VPS to connect',
            style: AppTextStyles.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
