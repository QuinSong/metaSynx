import 'package:flutter/material.dart';

class QRScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QRScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = Colors.black54,
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final cutOut = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    canvas.drawPath(getOuterPath(rect), paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    // Top left
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.left, cutOut.top + borderLength)
        ..lineTo(cutOut.left, cutOut.top + borderRadius)
        ..quadraticBezierTo(
            cutOut.left, cutOut.top, cutOut.left + borderRadius, cutOut.top)
        ..lineTo(cutOut.left + borderLength, cutOut.top),
      borderPaint,
    );

    // Top right
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.right - borderLength, cutOut.top)
        ..lineTo(cutOut.right - borderRadius, cutOut.top)
        ..quadraticBezierTo(
            cutOut.right, cutOut.top, cutOut.right, cutOut.top + borderRadius)
        ..lineTo(cutOut.right, cutOut.top + borderLength),
      borderPaint,
    );

    // Bottom right
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.right, cutOut.bottom - borderLength)
        ..lineTo(cutOut.right, cutOut.bottom - borderRadius)
        ..quadraticBezierTo(cutOut.right, cutOut.bottom,
            cutOut.right - borderRadius, cutOut.bottom)
        ..lineTo(cutOut.right - borderLength, cutOut.bottom),
      borderPaint,
    );

    // Bottom left
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.left + borderLength, cutOut.bottom)
        ..lineTo(cutOut.left + borderRadius, cutOut.bottom)
        ..quadraticBezierTo(
            cutOut.left, cutOut.bottom, cutOut.left, cutOut.bottom - borderRadius)
        ..lineTo(cutOut.left, cutOut.bottom - borderLength),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return QRScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}
