import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Shows a resume/start-over dialog before opening a VOD or Series episode.
///
/// Returns the start position in seconds: the saved position to resume from,
/// 0.0 to start from the beginning, or null if the user dismissed the dialog.
Future<double?> showResumeModal(
  BuildContext context, {
  required String title,
  required int positionSeconds,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) =>
        _ResumeModal(title: title, positionSeconds: positionSeconds),
  );
}

class _ResumeModal extends StatelessWidget {
  const _ResumeModal({required this.title, required this.positionSeconds});

  final String title;
  final int positionSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DpadRegion(
          verticalEdge: DpadEdgeBehavior.stop,
          horizontalEdge: DpadEdgeBehavior.stop,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resume Watching', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: colorScheme.primary,
                          child: Icon(
                            Icons.play_arrow,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Continue',
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(
                              'From ${formatTime(Duration(seconds: positionSeconds))}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                DpadFocusable(
                  // ignore: prefer_int_literals
                  onSelect: () => Navigator.of(context).pop(0.0),
                  effects: const [
                    GradientBorderEffect(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ],
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      child: Icon(Icons.replay, color: colorScheme.onSurface),
                    ),
                    title: const Text('Start from Beginning'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    // ignore: prefer_int_literals
                    onTap: () => Navigator.of(context).pop(0.0),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DpadFocusable(
                      onSelect: () => Navigator.of(context).pop(),
                      effects: const [
                        GradientBorderEffect(
                          borderRadius: BorderRadius.all(Radius.circular(50)),
                        ),
                      ],
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DpadFocusable(
                      autofocus: true,
                      onSelect: () =>
                          Navigator.of(context).pop(positionSeconds.toDouble()),
                      effects: const [
                        GradientBorderEffect(
                          borderRadius: BorderRadius.all(Radius.circular(50)),
                        ),
                      ],
                      child: FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(positionSeconds.toDouble()),
                        child: const Text('Resume'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
