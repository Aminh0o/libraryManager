import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// Renders a sharp, native vector barcode (Code 128) onto a Flutter Canvas.
class BarcodeVectorWidget extends StatelessWidget {
  final String data;
  final double width;
  final double height;
  final Color color;
  final bool drawText;
  final TextStyle? textStyle;

  const BarcodeVectorWidget({
    super.key,
    required this.data,
    this.width = 240,
    this.height = 70,
    this.color = Colors.black,
    this.drawText = true,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    try {
      final bc = Barcode.code128();
      // Calculate drawing elements
      final elements = bc.make(
        data,
        width: width,
        height: height - (drawText ? 18 : 0),
        drawText: false,
      );

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(width, height - (drawText ? 18 : 0)),
            painter: _BarcodePainter(elements: elements, color: color),
          ),
          if (drawText) ...[
            const SizedBox(height: 4),
            Text(
              data,
              style:
                  textStyle ??
                  TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: color,
                    fontFamily: 'monospace',
                  ),
            ),
          ],
        ],
      );
    } catch (_) {
      // Fallback for strings that cannot be represented in Code128
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Text(
          data,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
  }
}

class _BarcodePainter extends CustomPainter {
  final Iterable<BarcodeElement> elements;
  final Color color;

  _BarcodePainter({required this.elements, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final element in elements) {
      if (element is BarcodeBar) {
        if (element.black) {
          canvas.drawRect(
            Rect.fromLTWH(
              element.left,
              element.top,
              element.width,
              element.height,
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.elements != elements;
}
