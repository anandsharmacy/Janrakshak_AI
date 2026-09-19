import 'dart:math' as math;
import 'package:flutter/material.dart';

/// AshokaChakra — custom painter that draws an accurate 24-spoke Dharma wheel.
/// Used on the Splash screen (full size, animated spin) and Login screen
/// (watermark behind the glass card at ~5.7% opacity).
class AshokaChakra extends StatelessWidget {
  final double size;
  final Color color;

  const AshokaChakra({
    super.key,
    required this.size,
    this.color = const Color(0xFF000080), // Navy blue (standard flag color)
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _ChakraPainter(color: color)),
    );
  }
}

/// Spinning variant used on the Splash screen.
class SpinningAshokaChakra extends StatefulWidget {
  final double size;
  final Color color;
  final Duration duration;

  const SpinningAshokaChakra({
    super.key,
    required this.size,
    this.color = const Color(0xFF0E2A47),
    this.duration = const Duration(seconds: 18),
  });

  @override
  State<SpinningAshokaChakra> createState() => _SpinningState();
}

class _SpinningState extends State<SpinningAshokaChakra>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: AshokaChakra(size: widget.size, color: widget.color),
    );
  }
}

class _ChakraPainter extends CustomPainter {
  final Color color;
  const _ChakraPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.455;
    final r2 = size.width * 0.305;
    final r3 = size.width * 0.16;
    final spokeCount = 24;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Outer circle
    paint
      ..strokeWidth = size.width * 0.04
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Inner ring (faint)
    paint
      ..strokeWidth = size.width * 0.014
      ..color = color.withOpacity(0.4);
    canvas.drawCircle(Offset(cx, cy), r2, paint);

    // Hub circle
    paint
      ..color = color
      ..strokeWidth = size.width * 0.03;
    canvas.drawCircle(Offset(cx, cy), r3, paint);

    // Centre dot
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.065, paint);

    // Spokes
    for (int i = 0; i < spokeCount; i++) {
      final angle = (i * 2 * math.pi / spokeCount) - math.pi / 2;
      final isMain = i % 3 == 0;
      final outerR = isMain ? r - size.width * 0.02 : r2;

      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = isMain ? size.width * 0.028 : size.width * 0.015
        ..color = isMain ? color : color.withOpacity(0.6);

      canvas.drawLine(
        Offset(cx + r3 * math.cos(angle), cy + r3 * math.sin(angle)),
        Offset(cx + outerR * math.cos(angle), cy + outerR * math.sin(angle)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ChakraPainter old) => old.color != color;
}
