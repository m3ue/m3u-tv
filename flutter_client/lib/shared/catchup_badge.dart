import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/epg_icon_pill.dart';

/// Small pill badge indicating that a channel supports catchup / archive
/// playback. Used in the EPG channel column and the simple EPG list/grid.
class CatchupBadge extends StatelessWidget {
  const CatchupBadge({super.key, this.days});

  final int? days;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = days == null
        ? l10n.catchupBadgeAvailable
        : l10n.catchupBadgeAvailableDays(days!);
    return Tooltip(
      message: label,
      child: EpgIconPill(
        color: colorScheme.tertiaryContainer,
        borderColor: colorScheme.tertiary.withValues(alpha: 0.55),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.replay_rounded,
              size: 12,
              color: colorScheme.onTertiaryContainer,
            ),
            if (days != null) ...[
              const SizedBox(width: 2),
              Text(
                '${days}d',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontSize: 10,
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
