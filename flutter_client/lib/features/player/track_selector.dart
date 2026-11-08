import 'dart:async';

import 'package:m3u_tv/features/player/playback_controls.dart'
    show isHandheldLayout;
import 'package:m3u_tv/features/player/sync_offset_bar.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/list_picker_sheet.dart';
import 'package:m3u_tv/shared/sort_option_row.dart';
import 'package:material_ui/material_ui.dart';

/// Track selector widget for audio and subtitle track selection: buttons
/// that open the shared [ListPickerSheet] with one checked row per track.
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
    this.onSearchOnlineSubtitles,
    this.audioSyncOffset,
    this.subtitleSyncOffset,
    this.onAdjustAudioSync,
    this.onAdjustSubtitleSync,
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

  /// Adds "Search online" to the subtitle menu, and shows the Subtitles button
  /// even when the stream has no tracks of its own.
  final VoidCallback? onSearchOnlineSubtitles;

  /// The current offsets, shown on the pickers' sync rows.
  final Duration? audioSyncOffset;
  final Duration? subtitleSyncOffset;

  /// Open the sync bar. Null when the playing backend can't shift audio or
  /// subtitles, which hides the row and the long-press shortcut.
  final VoidCallback? onAdjustAudioSync;
  final VoidCallback? onAdjustSubtitleSync;

  bool get _showsSubtitleButton =>
      subtitleTracks.isNotEmpty || onSearchOnlineSubtitles != null;

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
    final l = AppLocalizations.of(context);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (supportsHdrToggle)
          Padding(
            padding: EdgeInsets.only(
              right: audioTracks.isNotEmpty || _showsSubtitleButton
                  ? buttonGap
                  : 0,
            ),
            child: SizedBox(
              height: scaledButtonHeight,
              child: AppButton(
                icon: Icons.hdr_on,
                label: hdrEnabled ? l.playerHdrOn : l.playerHdrOff,
                onPressed: () => onHdrEnabledChanged?.call(!hdrEnabled),
              ),
            ),
          ),
        if (audioTracks.isNotEmpty)
          SizedBox(
            height: scaledButtonHeight,
            child: AppButton(
              icon: Icons.audiotrack,
              label: l.playerTrackAudio,
              onPressed: () => _showAudioDialog(context),
              onLongPress: onAdjustAudioSync,
            ),
          ),
        if (audioTracks.isNotEmpty && _showsSubtitleButton)
          const SizedBox(width: buttonGap),
        if (_showsSubtitleButton)
          SizedBox(
            height: scaledButtonHeight,
            child: AppButton(
              icon: Icons.subtitles,
              label: l.playerTrackSubtitles,
              onPressed: () => _showSubtitleDialog(context),
              onLongPress: onAdjustSubtitleSync,
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
    final l = AppLocalizations.of(context);
    final selectedId = _effectiveAudioTrackId;
    _showTrackPicker(
      context,
      title: l.playerTrackAudioTitle,
      options: [
        (id: null, label: l.playerTrackAudioDisabled, icon: Icons.volume_off),
        for (final track in audioTracks)
          (id: track.id, label: track.label, icon: Icons.language),
      ],
      selectedId: selectedId,
      hasSelection: true,
      onSelected: onAudioTrackSelected,
      actions: [
        if (onAdjustAudioSync != null)
          (
            icon: Icons.graphic_eq,
            label: l.playerSyncRow(
              l.playerAudioSync,
              formatSyncOffset(l, audioSyncOffset ?? Duration.zero),
            ),
            action: onAdjustAudioSync!,
          ),
      ],
    );
  }

  void _showSubtitleDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    _showTrackPicker(
      context,
      title: l.playerTrackSubtitleTitle,
      options: [
        (
          id: null,
          label: l.playerTrackSubtitlesOff,
          icon: Icons.subtitles_off,
        ),
        for (final track in subtitleTracks)
          (id: track.id, label: track.label, icon: Icons.closed_caption),
      ],
      selectedId: selectedSubtitleTrackId,
      // An unknown selection with no id must not tick "Off".
      hasSelection:
          isSubtitleTrackSelectionKnown || selectedSubtitleTrackId != null,
      onSelected: onSubtitleTrackSelected,
      actions: [
        if (onAdjustSubtitleSync != null)
          (
            icon: Icons.av_timer,
            label: l.playerSyncRow(
              l.playerSubtitleSync,
              formatSyncOffset(l, subtitleSyncOffset ?? Duration.zero),
            ),
            action: onAdjustSubtitleSync!,
          ),
        if (onSearchOnlineSubtitles != null)
          (
            icon: Icons.search,
            label: l.playerOnlineSubtitlesSearch,
            action: onSearchOnlineSubtitles!,
          ),
      ],
    );
  }

  void _showTrackPicker(
    BuildContext context, {
    required String title,
    required List<({String? id, String label, IconData icon})> options,
    required String? selectedId,
    required bool hasSelection,
    required ValueChanged<String?> onSelected,
    List<({IconData icon, String label, VoidCallback action})> actions =
        const [],
  }) {
    final l = AppLocalizations.of(context);
    onDialogVisibilityChanged?.call(true);
    VoidCallback? chosenAction;
    unawaited(
      ListPickerSheet.show(
        context,
        title: title,
        cancelLabel: l.cancel,
        asDialog: !isHandheldLayout(context),
        // The active row takes focus itself (below), wherever it sits.
        autofocusIndex: -1,
        children: [
          for (final (index, option) in options.indexed)
            Builder(
              builder: (rowContext) {
                final isActive = hasSelection && option.id == selectedId;
                return SortOptionRow(
                  icon: option.icon,
                  label: option.label,
                  isActive: isActive,
                  autofocus: isActive || (!hasSelection && index == 0),
                  onTap: () {
                    onSelected(option.id);
                    Navigator.of(rowContext).pop();
                  },
                );
              },
            ),
          for (final action in actions)
            Builder(
              builder: (rowContext) => SortOptionRow(
                icon: action.icon,
                label: action.label,
                onTap: () {
                  chosenAction = action.action;
                  Navigator.of(rowContext).pop();
                },
              ),
            ),
        ],
      ).whenComplete(() {
        onDialogVisibilityChanged?.call(false);
        // Only once this sheet is gone, so the two dialogs' visibility
        // callbacks can't interleave.
        chosenAction?.call();
      }),
    );
  }
}
