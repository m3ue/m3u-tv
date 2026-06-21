import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

/// A [DpadEffect] that paints an animated gradient border on focus.
///
/// The gradient runs from [ColorScheme.primary] at the top-right corner to
/// [ColorScheme.secondary] at the bottom-left, fading in/out on focus state.
class GradientBorderEffect extends DpadEffect {
  const GradientBorderEffect({
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.width = 2.5,
    this.duration = const Duration(milliseconds: 150),
  });

  final BorderRadius borderRadius;
  final double width;
  final Duration duration;

  @override
  Widget build(BuildContext context, DpadFocusState state, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: state.focused ? 1.0 : 0.0,
              duration: duration,
              child: CustomPaint(
                painter: GradientBorderPainter(
                  borderRadius: borderRadius,
                  width: width,
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [scheme.primary, scheme.secondary],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class GradientBorderPainter extends CustomPainter {
  const GradientBorderPainter({
    required this.borderRadius,
    required this.width,
    required this.gradient,
  });

  final BorderRadius borderRadius;
  final double width;
  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect).deflate(width / 2);
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(GradientBorderPainter old) =>
      old.borderRadius != borderRadius ||
      old.width != width ||
      old.gradient != gradient;
}
