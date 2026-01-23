import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart';

class QrCodeDisplay extends StatelessWidget {
  final String? qrData;
  final ConnectionStatus status;
  final VoidCallback onRetry;

  const QrCodeDisplay({
    super.key,
    required this.qrData,
    required this.status,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (qrData == null || status != ConnectionStatus.connected) {
      return _buildLoadingOrError();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryWithOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: QrImageView(
        data: qrData!,
        version: QrVersions.auto,
        size: 220,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: AppColors.background,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: AppColors.background,
        ),
      ),
    );
  }

  Widget _buildLoadingOrError() {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: status == ConnectionStatus.error
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Connection Error',
                    style: TextStyle(color: AppColors.error),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              )
            : const CircularProgressIndicator(
                color: AppColors.primary,
              ),
      ),
    );
  }
}
