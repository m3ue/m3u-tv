import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';

/// "Up next" card shown late in a series episode (a few seconds past the
/// credits mark, or ~90% in when TheIntroDB has no credits segment). It rides
/// inside the player's control overlay (same `DpadRegion` as the transport
/// bar) so it's reachable by D-pad. Selecting Play swaps the player to the
/// next episode in place; Dismiss hides it for the rest of the episode.
class UpNextOverlay extends StatelessWidget {
  const UpNextOverlay({
    required this.eyebrowLabel,
    required this.title,
    required this.playLabel,
    required this.dismissLabel,
    required this.onPlay,
    required this.onDismiss,
    this.subtitle,
    this.plot,
    this.thumbnailUrl,
    this.playFocusNode,
    super.key,
  });

  /// Short "Up next" eyebrow above the title.
  final String eyebrowLabel;

  /// Next episode's title.
  final String title;

  /// Season/episode line, e.g. "S2 · E5".
  final String? subtitle;

  /// Next episode's plot/overview (truncated to two lines).
  final String? plot;

  /// Next episode thumbnail, if any.
  final String? thumbnailUrl;

  final String playLabel;
  final String dismissLabel;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;

  /// Focus node for the Play button, so the player can move focus onto the
  /// card the moment it appears.
  final FocusNode? playFocusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final thumb = thumbnailUrl;

    return Container(
      width: 380,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumb != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedMediaThumbnail(
                    url: thumb,
                    width: 112,
                    height: 63,
                    fit: BoxFit.cover,
                    fallback: const ColoredBox(color: Colors.white10),
                  ),
                ),
              if (thumb != null) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrowLabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (plot != null && plot!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plot!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: playLabel,
                  icon: Icons.play_arrow,
                  variant: AppButtonVariant.primaryInverted,
                  autofocus: true,
                  focusNode: playFocusNode,
                  onPressed: onPlay,
                ),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: dismissLabel,
                onPressed: onDismiss,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
