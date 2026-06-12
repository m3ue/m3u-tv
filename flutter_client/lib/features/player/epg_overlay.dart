import 'package:flutter/material.dart';

/// EPG overlay widget showing current/next program info for live TV.
///
/// Mirrors the RN PlayerScreen EPG overlay with:
/// - LIVE badge
/// - Current program title and progress bar
/// - Next program title (when available)
class EpgOverlay extends StatelessWidget {
  const EpgOverlay({
    required this.currentTitle,
    required this.currentProgress,
    this.nextTitle,
    super.key,
  });

  /// Title of the currently airing program.
  final String currentTitle;

  /// Progress of the current program, 0.0 to 1.0.
  final double currentProgress;

  /// Title of the next program, or null if unknown.
  final String? nextTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current program row: LIVE badge + title
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                currentTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.9),
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