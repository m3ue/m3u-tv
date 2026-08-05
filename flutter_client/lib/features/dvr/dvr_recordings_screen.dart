import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class DvrRecordingsScreen extends StatelessWidget {
  const DvrRecordingsScreen({
    super.key,
    required this.recordings,
    required this.isLoading,
    required this.isConfigured,
    required this.onPlay,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final bool isLoading;
  final bool isConfigured;
  final void Function(PlayerArgs args) onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!isConfigured) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.dvrRecordingsTitle)),
        body: Center(
          child: Text(
            l10n.dvrNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dvrRecordingsTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.dvrRecordingsSubtitle,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : recordings.isEmpty
                  ? Center(
                      child: Text(
                        l10n.dvrNoRecordings,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : _RecordingList(
                      recordings: recordings,
                      onPlay: onPlay,
                      onCancelRecording: onCancelRecording,
                      onCancelAndDeleteRecording: onCancelAndDeleteRecording,
                      onDeleteRecording: onDeleteRecording,
                      onSidebarActivate: onSidebarActivate,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingList extends StatelessWidget {
  const _RecordingList({
    required this.recordings,
    required this.onPlay,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args) onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      memoryKey: 'dvr/recordings',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) onSidebarActivate?.call();
      },
      child: ScrollbarListView(
        itemCount: recordings.length,
        itemBuilder: (context, index) {
          final recording = recordings[index];
          return Padding(
            padding: const EdgeInsets.only(
              bottom: MediaBrowsingMetrics.itemGap,
            ),
            child: _RecordingCard(
              recording: recording,
              autofocus: index == 0,
              onTap: () => _openRecording(recording),
              onCancel: onCancelRecording == null
                  ? null
                  : () => onCancelRecording!(recording.uuid),
              onCancelAndDelete: onCancelAndDeleteRecording == null
                  ? null
                  : () => onCancelAndDeleteRecording!(recording.uuid),
              onDelete: onDeleteRecording == null
                  ? null
                  : () => onDeleteRecording!(recording.uuid),
            ),
          );
        },
      ),
    );
  }

  void _openRecording(DvrRecording recording) {
    final playbackUrl = recording.playbackUrl;
    if (playbackUrl == null || playbackUrl.isEmpty) return;
    onPlay(
      PlayerArgs(
        streamUrl: playbackUrl,
        title: recording.title,
        type: recording.isInProgress ? 'live' : 'vod',
        metadata: <String, Object?>{
          'dvr_uuid': recording.uuid,
          'dvr_status': recording.status.name,
          if (recording.subtitle != null) 'subtitle': recording.subtitle,
          if (recording.channelName != null)
            'channel_name': recording.channelName,
          if (recording.seasonNumber != null)
            'season_number': recording.seasonNumber,
          if (recording.episodeNumber != null)
            'episode_number': recording.episodeNumber,
          if (recording.edlUrl != null) 'edl_url': recording.edlUrl,
        },
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.recording,
    required this.onTap,
    this.onCancel,
    this.onCancelAndDelete,
    this.onDelete,
    this.autofocus = false,
  });

  final DvrRecording recording;
  final VoidCallback onTap;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onCancelAndDelete;
  final Future<void> Function()? onDelete;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playable = recording.isPlayable;
    // The play tap-target and the trailing action buttons must be sibling
    // DpadFocusables beside each other, not one nested inside the other:
    // DpadFocusable excludes descendant focus by default (one widget, one
    // focus target), so a button nested inside the row's own DpadInkWell
    // would be permanently unreachable by remote.
    return Row(
      children: [
        Expanded(
          child: DpadInkWell(
            autofocus: autofocus,
            onTap: playable ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(
                MediaBrowsingMetrics.contentPadding,
              ),
              child: Row(
                children: [
                  _StatusIcon(recording: recording),
                  const SizedBox(width: MediaBrowsingMetrics.contentPadding),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recording.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (recording.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            recording.subtitle!,
                            style: theme.textTheme.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _Badge(label: recording.status.label),
                            if (recording.channelName != null)
                              _Badge(label: recording.channelName!),
                            if (recording.seasonNumber != null ||
                                recording.episodeNumber != null)
                              _Badge(label: _episodeLabel(recording)),
                            if (recording.durationSeconds != null)
                              _Badge(
                                label: _durationLabel(
                                  recording.durationSeconds!,
                                ),
                              ),
                            if (recording.fileSizeBytes != null &&
                                recording.fileSizeBytes! > 0)
                              _Badge(
                                label: _sizeLabel(recording.fileSizeBytes!),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (playable) ...[
                    const SizedBox(
                      width: MediaBrowsingMetrics.contentPadding,
                    ),
                    const _PlayIndicator(),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: MediaBrowsingMetrics.contentPadding),
        _CardTrailing(
          recording: recording,
          onCancel: onCancel,
          onCancelAndDelete: onCancelAndDelete,
          onDelete: onDelete,
        ),
      ],
    );
  }

  String _episodeLabel(DvrRecording recording) {
    final season = recording.seasonNumber;
    final episode = recording.episodeNumber;
    if (season != null && episode != null) return 'S$season E$episode';
    if (season != null) return 'Season $season';
    return 'Episode $episode';
  }

  String _durationLabel(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }

  String _sizeLabel(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(1)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(0)} MB';
  }
}

enum _StopRecordingChoice { keep, delete, back }

class _CardTrailing extends StatelessWidget {
  const _CardTrailing({
    required this.recording,
    this.onCancel,
    this.onCancelAndDelete,
    this.onDelete,
  });

  final DvrRecording recording;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onCancelAndDelete;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cancelHandler = onCancel;
    final cancelAndDeleteHandler = onCancelAndDelete;
    final deleteHandler = onDelete;
    final canCancel =
        cancelHandler != null &&
        (recording.status == DvrRecordingStatus.scheduled ||
            recording.status == DvrRecordingStatus.recording);
    final canDelete =
        deleteHandler != null &&
        (recording.status == DvrRecordingStatus.completed ||
            recording.status == DvrRecordingStatus.failed ||
            recording.status == DvrRecordingStatus.cancelled);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canDelete)
          AppIconButton(
            tooltip: l10n.dvrDelete,
            icon: Icons.delete,
            variant: AppButtonVariant.destructive,
            onPressed: () => _confirmDelete(context, recording, deleteHandler),
          ),
        if (canCancel) ...[
          if (canDelete) const SizedBox(width: 8),
          AppIconButton(
            tooltip: l10n.dvrCancel,
            icon: Icons.close,
            variant: AppButtonVariant.destructive,
            onPressed: () => _confirmCancel(
              context,
              recording,
              cancelHandler,
              cancelAndDeleteHandler,
            ),
          ),
        ],
      ],
    );
  }

  /// Offers a choice instead of a plain confirm: the server's cancel action
  /// only stops the recording and keeps it (status → Cancelled), while
  /// deleting is a distinct, explicit follow-up action (see
  /// AppShell._cancelAndDeleteRecording). AppShell always wires both
  /// callbacks together; [deleteAction] is nullable only so this widget
  /// degrades gracefully in isolation (e.g. tests) — when absent, cancels
  /// immediately with no dialog, since there is nothing to choose between.
  Future<void> _confirmCancel(
    BuildContext context,
    DvrRecording recording,
    Future<void> Function() keepAction,
    Future<void> Function()? deleteAction,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (deleteAction == null) {
      await _runWithFeedback(
        context,
        keepAction,
        successMessage: l10n.dvrCancelSuccess,
        failureMessage: l10n.dvrCancelFailed,
      );
      return;
    }

    final choice = await showDialog<_StopRecordingChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dvrStopTitle(recording.title)),
        content: Text(l10n.dvrStopMessage),
        actions: [
          DpadRegion(
            memoryKey: 'dvr/stop-dialog-actions',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: l10n.dvrStopBack,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_StopRecordingChoice.back),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.dvrStopDelete,
                  variant: AppButtonVariant.destructive,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_StopRecordingChoice.delete),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.dvrStopKeep,
                  variant: AppButtonVariant.primary,
                  autofocus: true,
                  onPressed: () => Navigator.of(
                    dialogContext,
                  ).pop(_StopRecordingChoice.keep),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || choice == _StopRecordingChoice.back) return;
    if (!context.mounted) return;

    if (choice == _StopRecordingChoice.keep) {
      await _runWithFeedback(
        context,
        keepAction,
        successMessage: l10n.dvrCancelSuccess,
        failureMessage: l10n.dvrCancelFailed,
      );
    } else {
      await _runWithFeedback(
        context,
        deleteAction,
        successMessage: l10n.dvrDeleteSuccess,
        failureMessage: l10n.dvrDeleteFailed,
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DvrRecording recording,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.dvrDeleteTitle),
        content: Text(l10n.dvrDeleteMessage),
        actions: [
          DpadRegion(
            memoryKey: 'dvr/delete-dialog-actions',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: l10n.dvrDeleteDismiss,
                  autofocus: true,
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: l10n.dvrDeleteConfirm,
                  variant: AppButtonVariant.destructive,
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    await _runWithFeedback(
      context,
      action,
      successMessage: l10n.dvrDeleteSuccess,
      failureMessage: l10n.dvrDeleteFailed,
    );
  }

  Future<void> _runWithFeedback(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
    required String failureMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } on Object catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.recording});

  final DvrRecording recording;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (recording.status) {
      DvrRecordingStatus.recording => Icons.fiber_manual_record,
      DvrRecordingStatus.postProcessing => Icons.sync,
      DvrRecordingStatus.completed => Icons.check_circle,
      DvrRecordingStatus.scheduled => Icons.schedule,
      DvrRecordingStatus.failed => Icons.error,
      DvrRecordingStatus.cancelled => Icons.cancel,
      // Never actually rendered — deleted recordings are removed from the
      // list before they reach this widget. See _onDvrStatusPush.
      DvrRecordingStatus.deleted => Icons.delete,
      DvrRecordingStatus.unknown => Icons.radio_button_unchecked,
    };
    final color = switch (recording.status) {
      DvrRecordingStatus.recording => Colors.redAccent,
      DvrRecordingStatus.postProcessing => colorScheme.secondary,
      DvrRecordingStatus.completed => colorScheme.primary,
      DvrRecordingStatus.scheduled => colorScheme.secondary,
      DvrRecordingStatus.failed => colorScheme.error,
      DvrRecordingStatus.cancelled => colorScheme.onSurfaceVariant,
      DvrRecordingStatus.deleted => colorScheme.onSurfaceVariant,
      DvrRecordingStatus.unknown => colorScheme.onSurfaceVariant,
    };
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }
}

/// A soft, non-interactive badge indicating whether selecting the card plays
/// it. Lives inside the card's own tappable content area (not beside the
/// cancel/delete buttons) since it describes what the card itself does.
class _PlayIndicator extends StatelessWidget {
  const _PlayIndicator();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow, color: color),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}
