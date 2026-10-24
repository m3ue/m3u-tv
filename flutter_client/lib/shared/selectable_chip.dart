import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Compact single-select pill - a leading check icon marks the selected
/// chip, matching `AppButton`'s primary/tonal colour language without
/// `AppButton`'s larger primary-action sizing. Scales with the app's
/// display-size setting via [FontSizeScope], so a row of several of these
/// stays usable at "Very Large".
///
/// For a *multi*-select checkbox-style chip (e.g. the Requests screen's
/// season picker, where several seasons can be chosen at once), see
/// `_SeasonToggle` in `request_detail_screen.dart` - a related but distinct
/// widget, not a drop-in replacement for this one.
class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return DpadInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14 * scale,
          vertical: 8 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 16 * scale, color: foreground),
              SizedBox(width: 6 * scale),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
