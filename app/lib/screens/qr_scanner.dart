import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/theme.dart';
import '../components/qr_scanner_overlay.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _processQRCode(barcode.rawValue!);
        break;
      }
    }
  }

  void _processQRCode(String rawValue) {
    setState(() => _isProcessing = true);

    try {
      final data = jsonDecode(rawValue) as Map<String, dynamic>;

      // Validate QR data (must have server, room, and secret)
      if (!data.containsKey('server') ||
          !data.containsKey('room') ||
          !data.containsKey('secret')) {
        _showError('Invalid QR code format');
        setState(() => _isProcessing = false);
        return;
      }

      // Check version compatibility
      final version = data['v'] as int? ?? 1;
      if (version < 2) {
        _showError('QR code version not supported. Please regenerate.');
        setState(() => _isProcessing = false);
        return;
      }

      HapticFeedback.mediumImpact();
      Navigator.pop(context, data);
    } catch (e) {
      _showError('Could not parse QR code');
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera view
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay
          Container(
            decoration: ShapeDecoration(
              shape: QRScannerOverlayShape(
                borderColor: AppColors.primary,
                borderRadius: 16,
                borderLength: 40,
                borderWidth: 4,
                cutOutSize: 280,
                overlayColor: Colors.black.withOpacity(0.7),
              ),
            ),
          ),

          // Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Scan Bridge QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _controller.toggleTorch(),
                    icon: const Icon(
                      Icons.flash_on,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_isProcessing)
                  const CircularProgressIndicator(
                    color: AppColors.primary,
                  )
                else
                  const Text(
                    'Point your camera at the QR code\non your MT4 Bridge',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
