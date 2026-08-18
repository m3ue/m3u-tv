import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/shared/app_button.dart';

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
    this.onDialogVisibilityChanged,
    this.isAudioTrackSelectionKnown = false,
    this.isSubtitleTrackSelectionKnown = false,
    super.key,
  });

  static const double buttonWidth = 136;
  static const double buttonHeight = 48;
  static const double buttonGap = 6;
  static const double controlsWidth = buttonWidth * 2 + buttonGap;

  /// Available audio tracks.
  final List<PlaybackTrack> audioTracks;

  /// Available subtitle tracks.
  final List<PlaybackTrack> subtitleTracks;

  /// Currently selected audio track ID, or null for disabled.
  final String? selectedAudioTrackId;

  /// Currently selected subtitle track ID, or null for off.
  final String? selectedSubtitleTrackId;

  final bool isAudioTrackSelectionKnown;

  final bool isSubtitleTrackSelectionKnown;

  /// Called when the user selects an audio track.
  final ValueChanged<String?> onAudioTrackSelected;

  /// Called when the user selects a subtitle track.
  final ValueChanged<String?> onSubtitleTrackSelected;
  final ValueChanged<bool>? onDialogVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (audioTracks.isNotEmpty)
          SizedBox(
            width: buttonWidth,
            height: buttonHeight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AppButton(
                icon: Icons.audiotrack,
                label: 'Audio',
                onPressed: () => _showAudioDialog(context),
              ),
            ),
          ),
        if (audioTracks.isNotEmpty && subtitleTracks.isNotEmpty)
          const SizedBox(width: buttonGap),
        if (subtitleTracks.isNotEmpty)
          SizedBox(
            width: buttonWidth,
            height: buttonHeight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AppButton(
                icon: Icons.subtitles,
                label: 'Subtitles',
                onPressed: () => _showSubtitleDialog(context),
              ),
            ),
          ),
      ],
    );
    // Individual buttons already shrink their own label via FittedBox, but
    // the row's total width (2 * buttonWidth + gap) is otherwise fixed —
    // wrapping the whole row lets it scale down as a unit instead of
    // overflowing off the edge of narrow/portrait screens.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: row,
    );
  }

  String? get _effectiveAudioTrackId => isAudioTrackSelectionKnown
      ? selectedAudioTrackId
      : selectedAudioTrackId ?? audioTracks.firstOrNull?.id;

  void _showAudioDialog(BuildContext context) {
    onDialogVisibilityChanged?.call(true);
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
      ).whenComplete(() => onDialogVisibilityChanged?.call(false)),
    );
  }

  void _showSubtitleDialog(BuildContext context) {
    onDialogVisibilityChanged?.call(true);
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
                  selected:
                      isSubtitleTrackSelectionKnown &&
                      selectedSubtitleTrackId == null,
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
      ).whenComplete(() => onDialogVisibilityChanged?.call(false)),
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
