import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// Track selector widget for audio and subtitle track selection.
///
/// Mirrors the RN PlayerScreen track selectors that show native
/// ActionSheet/Alert dialogs. In Flutter, we use a simple dialog
/// with track options.
class TrackSelector extends StatelessWidget {
  const TrackSelector({
    required this.audioTracks,
    required this.subtitleTracks,
    required this.selectedAudioTrackId,
    required this.selectedSubtitleTrackId,
    required this.onAudioTrackSelected,
    required this.onSubtitleTrackSelected,
    super.key,
  });

  /// Available audio tracks.
  final List<PlaybackTrack> audioTracks;

  /// Available subtitle tracks.
  final List<PlaybackTrack> subtitleTracks;

  /// Currently selected audio track ID, or null for disabled.
  final String? selectedAudioTrackId;

  /// Currently selected subtitle track ID, or null for off.
  final String? selectedSubtitleTrackId;

  /// Called when the user selects an audio track.
  final ValueChanged<String?> onAudioTrackSelected;

  /// Called when the user selects a subtitle track.
  final ValueChanged<String?> onSubtitleTrackSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (audioTracks.isNotEmpty)
          _TrackButton(
            icon: Icons.audiotrack,
            label: _audioLabel,
            onTap: () => _showAudioDialog(context),
          ),
        if (audioTracks.isNotEmpty && subtitleTracks.isNotEmpty)
          const SizedBox(width: 8),
        if (subtitleTracks.isNotEmpty)
          _TrackButton(
            icon: Icons.subtitles,
            label: _subtitleLabel,
            onTap: () => _showSubtitleDialog(context),
          ),
      ],
    );
  }

  String get _audioLabel {
    if (selectedAudioTrackId == null) return 'Disabled';
    final track = audioTracks
        .where((t) => t.id == selectedAudioTrackId)
        .firstOrNull;
    return track?.label ?? 'Select';
  }

  String get _subtitleLabel {
    if (selectedSubtitleTrackId == null) return 'Off';
    final track = subtitleTracks
        .where((t) => t.id == selectedSubtitleTrackId)
        .firstOrNull;
    return track?.label ?? 'Select';
  }

  void _showAudioDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Audio Track'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Disable'),
                  selected: selectedAudioTrackId == null,
                  onTap: () {
                    onAudioTrackSelected(null);
                    Navigator.of(context).pop();
                  },
                ),
                ...audioTracks.map(
                  (track) => ListTile(
                    title: Text(track.label),
                    selected: track.id == selectedAudioTrackId,
                    onTap: () {
                      onAudioTrackSelected(track.id);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSubtitleDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Subtitle Track'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Off'),
                  selected: selectedSubtitleTrackId == null,
                  onTap: () {
                    onSubtitleTrackSelected(null);
                    Navigator.of(context).pop();
                  },
                ),
                ...subtitleTracks.map(
                  (track) => ListTile(
                    title: Text(track.label),
                    selected: track.id == selectedSubtitleTrackId,
                    onTap: () {
                      onSubtitleTrackSelected(track.id);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TrackButton extends StatelessWidget {
  const _TrackButton({
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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.onSurface),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
