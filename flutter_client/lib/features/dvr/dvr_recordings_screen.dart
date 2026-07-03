import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class DvrRecordingsScreen extends StatelessWidget {
  const DvrRecordingsScreen({
    super.key,
    required this.recordings,
    required this.isLoading,
    required this.isConfigured,
    required this.onPlay,
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final bool isLoading;
  final bool isConfigured;
  final void Function(PlayerArgs args) onPlay;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    if (!isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('DVR Recordings')),
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
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
              'DVR Recordings',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Completed recordings and currently recording programmes',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : recordings.isEmpty
                  ? Center(
                      child: Text(
                        'No DVR recordings available',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : _RecordingList(
                      recordings: recordings,
                      onPlay: onPlay,
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
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args) onPlay;
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
    this.autofocus = false,
  });

  final DvrRecording recording;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playable = recording.isPlayable;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: playable ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
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
                          label: _durationLabel(recording.durationSeconds!),
                        ),
                      if (recording.fileSizeBytes != null &&
                          recording.fileSizeBytes! > 0)
                        _Badge(label: _sizeLabel(recording.fileSizeBytes!)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Icon(
              playable ? Icons.play_arrow : Icons.block,
              color: playable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
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

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.recording});

  final DvrRecording recording;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (recording.status) {
      DvrRecordingStatus.recording => Icons.fiber_manual_record,
      DvrRecordingStatus.completed => Icons.check_circle,
      DvrRecordingStatus.scheduled => Icons.schedule,
      DvrRecordingStatus.failed => Icons.error,
      DvrRecordingStatus.cancelled => Icons.cancel,
      DvrRecordingStatus.unknown => Icons.radio_button_unchecked,
    };
    final color = switch (recording.status) {
      DvrRecordingStatus.recording => Colors.redAccent,
      DvrRecordingStatus.completed => colorScheme.primary,
      DvrRecordingStatus.scheduled => colorScheme.secondary,
      DvrRecordingStatus.failed => colorScheme.error,
      DvrRecordingStatus.cancelled => colorScheme.onSurfaceVariant,
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
