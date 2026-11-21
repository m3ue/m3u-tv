import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/l10n/timeshift_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/dialog_option_tiles.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// Which end of an in-progress recording's growing HLS window to open.
enum InProgressPlaybackChoice {
  /// Seek to window start (segment 0) after open.
  fromBeginning,

  /// Join at the live edge (ExoPlayer's default for a dynamic playlist).
  watchLiveEdge,
}

/// Offers "Start from beginning" / "Watch live edge" before opening a
/// recording that is still (or just finished) writing its growing HLS
/// window. Null when dismissed.
///
/// The playlist already retains every segment from the start
/// (`hls_list_size=0`); the player otherwise defaults a dynamic playlist
/// to the live edge, which is why joining mid-recording used to land
/// partway through with no way back to 0:00.
Future<InProgressPlaybackChoice?> showInProgressRecordingStartModal(
  BuildContext context, {
  required String title,
}) {
  return showAppDialog<InProgressPlaybackChoice>(
    context: context,
    builder: (_) => _InProgressRecordingStartModal(title: title),
  );
}

class _InProgressRecordingStartModal extends StatelessWidget {
  const _InProgressRecordingStartModal({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);

    return OptionsDialog(
      maxWidth: 400 * scale,
      children: [
        Text(l.dvrRecordingInProgress, style: theme.textTheme.titleLarge),
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
          icon: Icons.replay,
          title: l.playerStartFromBeginning,
          onTap: () =>
              Navigator.of(context).pop(InProgressPlaybackChoice.fromBeginning),
        ),
        const SizedBox(height: 8),
        DialogActionTile(
          icon: Icons.live_tv,
          label: l.playerWatchLiveEdge,
          onTap: () =>
              Navigator.of(context).pop(InProgressPlaybackChoice.watchLiveEdge),
        ),
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
              label: l.playerStartFromBeginning,
              onPressed: () => Navigator.of(
                context,
              ).pop(InProgressPlaybackChoice.fromBeginning),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shared open path for the DVR Recordings screen and Search: shows the
/// in-progress choice dialog when the recording still serves a growing
/// window, then hands the chosen [PlayerArgs] to [onPlay]. Completed
/// recordings open immediately (no dialog).
Future<void> openDvrRecordingPlayback(
  BuildContext context, {
  required DvrRecording recording,
  required void Function(PlayerArgs args) onPlay,
}) async {
  if (!recording.isPlayable || !context.mounted) return;

  var startFromBeginning = false;
  if (recording.playsLiveWindow) {
    final choice = await showInProgressRecordingStartModal(
      context,
      title: recording.title,
    );
    if (choice == null || !context.mounted) return;
    startFromBeginning = choice == InProgressPlaybackChoice.fromBeginning;
  }

  onPlay(
    PlayerArgs.dvrRecording(recording, startFromBeginning: startFromBeginning),
  );
}
