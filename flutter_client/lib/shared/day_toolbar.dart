import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// "Today" / "Tomorrow" / "Yesterday", else the localized weekday name.
String epgRelativeDayLabel(
  BuildContext context,
  DateTime day,
  DateTime today,
) {
  final l10n = AppLocalizations.of(context);
  final a = DateTime(day.year, day.month, day.day);
  final b = DateTime(today.year, today.month, today.day);
  // Calendar-day difference that ignores a DST hour either way.
  final delta = (a.difference(b).inHours / 24).round();
  return switch (delta) {
    0 => l10n.epgToday,
    1 => l10n.epgTomorrow,
    -1 => l10n.epgYesterday,
    _ => DateFormat.EEEE(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(day),
  };
}

/// One day at a time: previous, the day shown, next, and a jump back to now.
/// Shared by the guide and the Sports screen.
class DayToolbar extends StatelessWidget {
  const DayToolbar({
    super.key,
    this.keyPrefix = 'timeline',
    this.nowFocusNode,
    this.nowLabel,
    this.blockUp = false,
    required this.selectedDate,
    required this.today,
    required this.compact,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNow,
    required this.onNext,
  });

  /// Prefixes the keys of the toolbar's controls.
  final String keyPrefix;

  /// Focus for the Now button, which is the one control always enabled, for
  /// moving focus here from elsewhere on the page.
  final FocusNode? nowFocusNode;

  /// The Now button's label, where another word suits better than "Now".
  final String? nowLabel;

  /// Swallow D-pad Up here. With the preview panel above there's nothing
  /// focusable directly up, so traversal would otherwise jump sideways into
  /// the middle of the category strip.
  final bool blockUp;
  final DateTime selectedDate;
  final DateTime today;
  final bool compact;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNow;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();

    Widget chevron({
      required Key key,
      required IconData icon,
      required bool enabled,
      required VoidCallback onTap,
      required String label,
    }) {
      return DpadInkWell(
        key: key,
        onTap: enabled ? onTap : null,
        enabled: enabled,
        autoScroll: false,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6 * scale),
          child: Center(
            child: Icon(
              icon,
              size: 26 * scale,
              color: enabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.3),
              semanticLabel: label,
            ),
          ),
        ),
      );
    }

    final toolbar = Container(
      height: (compact ? 50 : 58) * scale,
      padding: EdgeInsets.symmetric(
        horizontal: (compact ? 8 : 12) * scale,
        vertical: 6 * scale,
      ),
      // crossAxisAlignment.stretch gives every focusable the same rect
      // height, so D-pad Down from any of them reads as leaving the row
      // (dpad's edge-based "is this candidate below me" check) instead of
      // hopping to a taller neighbour.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          chevron(
            key: ValueKey('$keyPrefix-previous-day'),
            icon: Icons.chevron_left,
            enabled: canGoPrevious,
            onTap: onPrevious,
            label: l10n.epgPreviousDay,
          ),
          SizedBox(
            width: (compact ? 118 : 150) * scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  epgRelativeDayLabel(context, selectedDate, today),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  DateFormat.yMMMd(locale).format(selectedDate),
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          chevron(
            key: ValueKey('$keyPrefix-next-day'),
            icon: Icons.chevron_right,
            enabled: canGoNext,
            onTap: onNext,
            label: l10n.epgNextDay,
          ),
          SizedBox(width: 12 * scale),
          DpadInkWell(
            key: ValueKey('$keyPrefix-now'),
            focusNode: nowFocusNode,
            onTap: onNow,
            autoScroll: false,
            borderRadius: BorderRadius.circular(50),
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.today,
                    size: 18 * scale,
                    color: colorScheme.onPrimaryContainer,
                  ),
                  SizedBox(width: 6 * scale),
                  Text(
                    nowLabel ?? l10n.epgNow,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (!blockUp) return toolbar;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) =>
          event is! KeyUpEvent &&
              Dpad.keySetOf(context).directionOf(event.logicalKey) ==
                  TraversalDirection.up
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: toolbar,
    );
  }
}
