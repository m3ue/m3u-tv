import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';

/// Small pill badge indicating that a channel supports catchup / archive
/// playback. Used in the EPG channel column and the simple EPG list/grid.
class CatchupBadge extends StatelessWidget {
  const CatchupBadge({super.key, this.days, this.compact = false});

  final int? days;

  /// Shrinks the icon/text/padding for tight spots (e.g. the EPG timeline's
  /// Channels column, where the badge floats over a small logo).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = days == null
        ? l10n.catchupBadgeAvailable
        : l10n.catchupBadgeAvailableDays(days!);
    final iconSize = compact ? 9.0 : 12.0;
    final fontSize = compact ? 8.0 : 10.0;
    return Tooltip(
      message: label,
      child: EpgIconPill(
        color: colorScheme.tertiaryContainer,
        borderColor: colorScheme.tertiary.withValues(alpha: 0.55),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 3 : 4,
          vertical: compact ? 1 : 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay_rounded,
              size: iconSize,
              color: colorScheme.onTertiaryContainer,
            ),
            if (days != null) ...[
              const SizedBox(width: 2),
              Text(
                '${days}d',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
