import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Rounded-square leading icon tile for list rows, shared by the DVR section
/// (recordings, series rules) and the Shows episode list. Centralizing the
/// shape keeps row visual treatment consistent across feature surfaces.
///
/// In normal mode renders [icon] in an alpha-tinted background of [tileColor].
/// In select mode (DVR rows, when the parent screen enables multi-select)
/// renders a checkbox instead; episodes use normal mode only and don't need
/// the select-mode behavior. Both [selected] and [selectMode] default to false
/// so non-DVR callers can pass just [icon] and [tileColor].
class LeadingTile extends StatelessWidget {
  const LeadingTile({
    super.key,
    required this.icon,
    required this.tileColor,
    this.selected = false,
    this.selectMode = false,
  });

  final IconData icon;
  final Color tileColor;
  final bool selected;
  final bool selectMode;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final scaledSize = size * scale;

    if (selectMode) {
      final accent = selected ? colorScheme.primary : colorScheme.outline;
      return Container(
        width: scaledSize,
        height: scaledSize,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 2),
        ),
        child: Icon(
          selected ? Icons.check_box : Icons.check_box_outline_blank,
          color: accent,
          size: 24 * scale,
        ),
      );
    }

    return Container(
      width: scaledSize,
      height: scaledSize,
      decoration: BoxDecoration(
        color: tileColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: tileColor, size: 24 * scale),
    );
  }
}
