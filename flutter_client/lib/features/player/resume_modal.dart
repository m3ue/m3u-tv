import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/dialog_option_tiles.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

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
  return showAppDialog<ResumeModalResult>(
    context: context,
    builder: (_) => _ResumeModal(
      title: title,
      positionSeconds: positionSeconds,
      showManageActions: showManageActions,
    ),
  );
}

/// Shows the dialog for a Continue Watching "up next" episode, which has no
/// position to resume: Play (resolves [ResumeAction.startOver]) or Mark
/// watched (resolves [ResumeAction.markWatched]) to skip past it. Null when
/// dismissed.
Future<ResumeModalResult?> showUpNextModal(
  BuildContext context, {
  required String title,
}) {
  return showAppDialog<ResumeModalResult>(
    context: context,
    builder: (_) => _ResumeModal(
      title: title,
      positionSeconds: 0,
      showManageActions: true,
      upNext: true,
    ),
  );
}

class _ResumeModal extends StatelessWidget {
  const _ResumeModal({
    required this.title,
    required this.positionSeconds,
    required this.showManageActions,
    this.upNext = false,
  });

  final String title;
  final int positionSeconds;
  final bool showManageActions;

  /// Nothing to resume: offers Play and Mark watched only.
  final bool upNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);

    final scale = FontSizeScope.scaleOf(context);
    const playFromStart = ResumeModalResult(ResumeAction.startOver);
    final resume = upNext
        ? playFromStart
        : ResumeModalResult(
            ResumeAction.resume,
            startPositionSeconds: positionSeconds.toDouble(),
          );

    return OptionsDialog(
      maxWidth: 400 * scale,
      children: [
        Text(
          upNext ? l.homeUpNext : l.playerResumeWatching,
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
        DialogPrimaryOption(
          icon: Icons.play_arrow,
          title: upNext ? l.playerPlay : l.playerContinue,
          subtitle: upNext
              ? null
              : l.playerFromTime(
                  formatTime(Duration(seconds: positionSeconds)),
                ),
          onTap: () => Navigator.of(context).pop(resume),
        ),
        if (!upNext) ...[
          const SizedBox(height: 8),
          DialogActionTile(
            icon: Icons.replay,
            label: l.playerStartFromBeginning,
            onTap: () => Navigator.of(context).pop(playFromStart),
          ),
        ],
        if (showManageActions) ...[
          if (!upNext) ...[
            const SizedBox(height: 8),
            DialogActionTile(
              icon: Icons.remove_done,
              label: l.playerClearProgress,
              onTap: () => Navigator.of(context).pop(
                const ResumeModalResult(ResumeAction.clearProgress),
              ),
            ),
          ],
          const SizedBox(height: 8),
          DialogActionTile(
            icon: Icons.done_all,
            label: l.seriesMarkWatched,
            onTap: () => Navigator.of(context).pop(
              const ResumeModalResult(ResumeAction.markWatched),
            ),
          ),
        ],
        const SizedBox(height: 20),
        OptionsDialogActions(
          children: [
            AppButton(
              label: l.cancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              autofocus: true,
              variant: AppButtonVariant.primary,
              label: upNext ? l.playerPlay : l.playerResume,
              onPressed: () => Navigator.of(context).pop(resume),
            ),
          ],
        ),
      ],
    );
  }
}
