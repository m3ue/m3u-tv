import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

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
    this.supportsHdrToggle = false,
    this.hdrEnabled = true,
    this.onHdrEnabledChanged,
    super.key,
  });

  static const double buttonHeight = 48;
  // Halved from 6 -- the perceived gap between Audio/Subtitles used to be
  // dominated by each button sitting centered inside its own fixed-width
  // cell (see the old `buttonWidth`), not by this constant, so shrinking it
  // alone wouldn't have done much. Removing the per-button cell (below)
  // fixed the bulk of it; this still halves the deliberate gap on top.
  static const double buttonGap = 3;
  // Rough reservation for [PlaybackControls]' non-compact layout math and
  // its `Align(centerRight)` box -- no longer the exact width of the button
  // row now that each button sizes to its own content instead of a fixed
  // cell, but only needs to be a safe upper bound.
  static const double controlsWidth = 300;

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

  /// Whether the active backend can toggle HDR playback (currently only
  /// `DesktopLibmpvBackend` on Linux/Windows -- see [HdrToggleProvider]).
  final bool supportsHdrToggle;

  /// Current HDR setting, only meaningful when [supportsHdrToggle] is true.
  final bool hdrEnabled;

  /// Called when the user taps the HDR button to flip [hdrEnabled].
  final ValueChanged<bool>? onHdrEnabledChanged;

  @override
  Widget build(BuildContext context) {
    // Each button now sizes to its own content (height pinned, width
    // intrinsic) instead of being centered inside a fixed-width cell -- the
    // old fixed cell was wide enough to fit "Subtitles" without shrinking,
    // which left "Audio" (a shorter label) surrounded by dead space on
    // both sides. That dead space, not `buttonGap` itself, was the bulk of
    // the visually "large gap" between the two buttons.
    //
    // The pinned height must scale with the display-size setting - AppButton
    // itself grows (padding + text) at larger scales, and a fixed unscaled
    // height here would clip that growth instead of fitting it.
    final scale = FontSizeScope.scaleOf(context);
    final scaledButtonHeight = buttonHeight * scale;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (supportsHdrToggle)
          Padding(
            padding: EdgeInsets.only(
              right: audioTracks.isNotEmpty || subtitleTracks.isNotEmpty
                  ? buttonGap
                  : 0,
            ),
            child: SizedBox(
              height: scaledButtonHeight,
              child: AppButton(
                icon: Icons.hdr_on,
                label: hdrEnabled ? 'HDR On' : 'HDR Off',
                onPressed: () => onHdrEnabledChanged?.call(!hdrEnabled),
              ),
            ),
          ),
        if (audioTracks.isNotEmpty)
          SizedBox(
            height: scaledButtonHeight,
            child: AppButton(
              icon: Icons.audiotrack,
              label: 'Audio',
              onPressed: () => _showAudioDialog(context),
            ),
          ),
        if (audioTracks.isNotEmpty && subtitleTracks.isNotEmpty)
          const SizedBox(width: buttonGap),
        if (subtitleTracks.isNotEmpty)
          SizedBox(
            height: scaledButtonHeight,
            child: AppButton(
              icon: Icons.subtitles,
              label: 'Subtitles',
              onPressed: () => _showSubtitleDialog(context),
            ),
          ),
      ],
    );
    // Wrapping the whole row lets it scale down as a unit instead of
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
