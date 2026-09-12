import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// What the viewer chose in the resume dialog.
enum ResumeAction {
  /// Resume from the saved position.
  resume,

  /// Play from the start, keeping the existing progress row.
  startOver,

  /// Zero the progress row (drops the title out of Continue Watching) and
  /// do not play.
  clearProgress,

  /// Mark the title finished and do not play.
  markWatched,
}

/// Result of [showResumeModal]. [startPositionSeconds] is only meaningful for
/// [ResumeAction.resume]; it is 0 for every other action.
class ResumeModalResult {
  const ResumeModalResult(this.action, {this.startPositionSeconds = 0});

  final ResumeAction action;
  final double startPositionSeconds;
}

/// Shows a resume/start-over dialog before opening a VOD or Series episode.
///
/// Returns the viewer's choice, or null if they dismissed the dialog. When
/// [showManageActions] is true the dialog also offers "Clear progress" and
/// "Mark watched" - callers that pass it must handle
/// [ResumeAction.clearProgress] / [ResumeAction.markWatched] in the result.
Future<ResumeModalResult?> showResumeModal(
  BuildContext context, {
  required String title,
  required int positionSeconds,
  bool showManageActions = false,
}) {
  return showDialog<ResumeModalResult>(
    context: context,
    builder: (_) => _ResumeModal(
      title: title,
      positionSeconds: positionSeconds,
      showManageActions: showManageActions,
    ),
  );
}

class _ResumeModal extends StatelessWidget {
  const _ResumeModal({
    required this.title,
    required this.positionSeconds,
    required this.showManageActions,
  });

  final String title;
  final int positionSeconds;
  final bool showManageActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final scale = FontSizeScope.scaleOf(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 400 * scale),
        child: DpadRegion(
          verticalEdge: DpadEdgeBehavior.stop,
          horizontalEdge: DpadEdgeBehavior.stop,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.playerResumeWatching,
                  style: theme.textTheme.titleLarge,
                ),
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
                DpadInkWell(
                  onTap: () => Navigator.of(context).pop(
                    ResumeModalResult(
                      ResumeAction.resume,
                      startPositionSeconds: positionSeconds.toDouble(),
                    ),
                  ),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  child: Card(
                    margin: EdgeInsets.zero,
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
                                l.playerContinue,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                l.playerFromTime(
                                  formatTime(
                                    Duration(seconds: positionSeconds),
                                  ),
                                ),
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
                ),
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.replay,
                  label: l.playerStartFromBeginning,
                  onTap: () => Navigator.of(
                    context,
                  ).pop(const ResumeModalResult(ResumeAction.startOver)),
                ),
                if (showManageActions) ...[
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.remove_done,
                    label: l.playerClearProgress,
                    onTap: () => Navigator.of(context).pop(
                      const ResumeModalResult(ResumeAction.clearProgress),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.done_all,
                    label: l.seriesMarkWatched,
                    onTap: () => Navigator.of(context).pop(
                      const ResumeModalResult(ResumeAction.markWatched),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: l.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      autofocus: true,
                      variant: AppButtonVariant.primary,
                      label: l.playerResume,
                      onPressed: () => Navigator.of(context).pop(
                        ResumeModalResult(
                          ResumeAction.resume,
                          startPositionSeconds: positionSeconds.toDouble(),
                        ),
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

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadFocusable(
      onSelect: onTap,
      effects: const [
        GradientBorderEffect(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.surfaceContainerHighest,
          child: Icon(icon, color: colorScheme.onSurface),
        ),
        title: Text(label),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: onTap,
      ),
    );
  }
}
