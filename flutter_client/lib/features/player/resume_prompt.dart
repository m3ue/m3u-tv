import 'package:flutter/material.dart';

/// Resume prompt dialog shown when startPosition > 30 seconds.
///
/// Mirrors the RN PlayerScreen resume behavior: when a VOD/episode has
/// stored progress exceeding 30 seconds, the user is asked whether to
/// resume from that position or start over.
class ResumePrompt extends StatelessWidget {
  const ResumePrompt({
    required this.position,
    required this.onResume,
    required this.onStartOver,
    super.key,
  });

  /// The stored resume position to display.
  final Duration position;

  /// Called when the user chooses to resume from [position].
  final VoidCallback onResume;

  /// Called when the user chooses to start from the beginning.
  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Card(
        color: colorScheme.surfaceContainerHigh,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 48,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Resume Playback?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You were watching at ${_formatPosition(position)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Resume'),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: onStartOver,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Start Over'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPosition(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    final minutesPadded = minutes.toString().padLeft(2, '0');
    final secondsPadded = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutesPadded:$secondsPadded';
    }
    return '$minutes:$secondsPadded';
  }
}