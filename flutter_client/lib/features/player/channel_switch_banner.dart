import 'package:flutter/material.dart';

import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Which way the user is surfing when the channel-switch banner appears.
///
/// Used by the banner to draw the right chevron next to the channel name
/// (up arrow = next channel, down arrow = previous channel) so the user
/// can sanity-check that the key they pressed is the key that fired.
enum ChannelSwitchDirection { up, down }

/// Brief on-screen confirmation that a channel swap has happened.
///
/// Pure presentational widget -- the parent owns when to show / hide and
/// how long it stays up (the player route drives it via a 1.5s timer).
/// Renders as a small dark pill in the upper-left of the player stack,
/// mirroring the visual treatment of [EpgOverlay] so the two read as
/// the same family of overlay chrome.
///
/// Visually:
///
///     ┌─────────────────────────────┐
///     │ ▲  CNN                       │
///     └─────────────────────────────┘
///
/// Excludes its decorative chevron from the semantics tree (it is
/// redundant with the channel name and the screen-reader would already
/// hear the "channel switched" intent from [Actions]).
class ChannelSwitchBanner extends StatelessWidget {
  const ChannelSwitchBanner({
    required this.channel,
    required this.direction,
    super.key,
  });

  final Channel channel;
  final ChannelSwitchDirection direction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final chevron = direction == ChannelSwitchDirection.up
        ? Icons.keyboard_arrow_up
        : Icons.keyboard_arrow_down;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  chevron,
                  size: 20,
                  color: colorScheme.onPrimary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              channel.name,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.9),
                shadows: const <Shadow>[
                  Shadow(
                    offset: Offset(1, 1),
                    blurRadius: 3,
                    color: Colors.black54,
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
