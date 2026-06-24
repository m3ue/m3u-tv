import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

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

  static const double buttonWidth = 136;
  static const double controlsWidth = buttonWidth * 2 + 8;

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
            label: 'Audio',
            onTap: () => _showAudioDialog(context),
          ),
        if (audioTracks.isNotEmpty && subtitleTracks.isNotEmpty)
          const SizedBox(width: 8),
        if (subtitleTracks.isNotEmpty)
          _TrackButton(
            icon: Icons.subtitles,
            label: 'Subtitles',
            onTap: () => _showSubtitleDialog(context),
          ),
      ],
    );
  }

  String? get _effectiveAudioTrackId =>
      selectedAudioTrackId ?? audioTracks.firstOrNull?.id;

  void _showAudioDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Audio Track'),
            content: _TrackDialogList(
              children: [
                ListTile(
                  title: const Text('Disable'),
                  selected: _effectiveAudioTrackId == null,
                  onTap: () {
                    onAudioTrackSelected(null);
                    Navigator.of(context).pop();
                  },
                ),
                ...audioTracks.map(
                  (track) => ListTile(
                    title: Text(track.label),
                    selected: track.id == _effectiveAudioTrackId,
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
            content: _TrackDialogList(
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

class _TrackDialogList extends StatelessWidget {
  const _TrackDialogList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      width: double.maxFinite,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Scrollbar(
          thumbVisibility: true,
          child: ListView(
            shrinkWrap: true,
            children: children,
          ),
        ),
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

    return DpadFocusable(
      onSelect: onTap,
      effects: const [
        GradientBorderEffect(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ],
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: TrackSelector.buttonWidth,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
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
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
