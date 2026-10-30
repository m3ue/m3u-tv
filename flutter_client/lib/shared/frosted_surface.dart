import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// A dark "frosted glass" panel for chrome that floats over artwork (the
/// Home spotlight clock, a detail page's title pill). Blurs what is behind
/// it where [ImageQualityScope.allowsBlurOf] allows, and otherwise falls back
/// to a near-opaque tint so the text stays legible without the blur's
/// per-frame cost.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.borderRadius,
    required this.child,
    this.sigma = 14,
    this.tintAlpha = 0.5,
    this.borderAlpha = 0.12,
    this.padding,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final double sigma;

  /// Tint opacity over the blur. Without the blur the tint is raised to at
  /// least 0.85, since nothing softens the artwork behind it.
  final double tintAlpha;
  final double borderAlpha;
  final EdgeInsetsGeometry? padding;

  static const Color _tint = Color(0xFF09090b);

  @override
  Widget build(BuildContext context) {
    final blur = ImageQualityScope.allowsBlurOf(context);
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _tint.withValues(
          alpha: blur || tintAlpha >= 0.85 ? tintAlpha : 0.85,
        ),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: borderAlpha)),
      ),
      child: child,
    );
    return ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: panel,
            )
          : panel,
    );
  }
}
