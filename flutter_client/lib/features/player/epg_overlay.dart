import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// EPG overlay widget showing current/next program info for live TV.
///
/// Mirrors the VOD/series NowPlayingOverlay's badge + title header
/// (badge = "LIVE", title = channel name, plus the channel logo), with the
/// current program title, progress bar, and next program title beneath it.
class EpgOverlay extends StatelessWidget {
  const EpgOverlay({
    required this.currentTitle,
    required this.currentProgress,
    this.nextTitle,
    this.channelName,
    this.logoUrl,
    super.key,
  });

  /// Title of the currently airing program.
  final String currentTitle;

  /// Progress of the current program, 0.0 to 1.0.
  final double currentProgress;

  /// Title of the next program, or null if unknown.
  final String? nextTitle;

  /// Name of the channel currently playing.
  final String? channelName;

  /// Channel logo URL, or null if unavailable.
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final logoSize = 64 * FontSizeScope.scaleOf(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Channel logo, spanning the full height of the text column
            // beside it so it can be shown larger. The background lives on
            // this wrapping box (not on ResilientMediaImage's own, which is
            // made transparent) so the icon can be inset from it via
            // padding instead of filling it edge to edge.
            ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: logoSize),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                // Explicit size (the box's width minus its padding): without
                // it ResilientMediaImage measures through a LayoutBuilder,
                // which the IntrinsicHeight above can't lay out.
                child: ResilientMediaImage(
                  imageUrl: logoUrl,
                  width: logoSize - 16,
                  height: logoSize - 16,
                  fallbackIcon: Icons.tv,
                  fit: BoxFit.contain,
                  oversample: 2,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header row: LIVE badge + channel name
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'LIVE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          channelName ?? currentTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.9,
                            ),
                            shadows: const [
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
                      ),
                    ],
                  ),
                  if (channelName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      currentTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 4,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  // Progress bar
                  EpgProgressBar(progress: currentProgress.clamp(0.0, 1.0)),
                  if (nextTitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Next: $nextTitle',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.75),
                        shadows: const [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 4,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress bar for the EPG overlay showing current program progress.
class EpgProgressBar extends StatelessWidget {
  const EpgProgressBar({required this.progress, super.key});

  /// Progress value from 0.0 to 1.0.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: progress,
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
