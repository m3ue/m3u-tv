import 'dart:async';
import 'dart:io' show Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/features/player/track_selector.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Edge padding for [PlaybackControls]' back-button corner. tvOS gets a
/// much smaller value since `SafeArea` already insets for its focus-safe
/// zone; stacking the full padding on top of that would double up. Phones/
/// tablets (in either orientation) also get a smaller value than TV/desktop
/// -- their shortest side is much smaller, so the same 40px inset used to
/// eat a disproportionate share of the available height, especially in the
/// short landscape orientation the player now locks to on handheld devices.
/// Shared with `PlayerScreen`'s diagnostics overlay, which must position
/// itself against this same value to line up with the back button.
double overlayEdgePaddingFor(BuildContext context) {
  if (Platform.operatingSystem == 'tvos') return 8;
  if (isHandheldLayout(context)) return 16;
  return 40;
}

/// True for phones/tablets in either orientation -- judged by the shortest
/// side of the viewport so a phone rotated into landscape (wide but short)
/// is still recognized as compact, instead of only narrow *portrait* widths
/// getting the compact treatment. That width-only check used to flip on and
/// off depending on orientation and made the controls/overlays behave
/// inconsistently between portrait and landscape on the same device.
bool isHandheldLayout(BuildContext context) {
  if (Platform.operatingSystem == 'tvos') return false;
  return MediaQuery.sizeOf(context).shortestSide < 600;
}

/// Playback controls overlay for the player screen.
///
/// Shows play/pause, seek, and back controls. The parent widget
/// manages overlay visibility; this widget is always visible when
/// mounted and does not auto-hide (the parent handles that).
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    required this.isPlaying,
    required this.isLive,
    required this.canSeek,
    required this.currentPosition,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    required this.onBack,
    this.audioTracks = const <PlaybackTrack>[],
    this.subtitleTracks = const <PlaybackTrack>[],
    this.selectedAudioTrackId,
    this.selectedSubtitleTrackId,
    this.isAudioTrackSelectionKnown = false,
    this.isSubtitleTrackSelectionKnown = false,
    this.onAudioTrackSelected,
    this.onSubtitleTrackSelected,
    this.onTrackDialogVisibilityChanged,
    this.supportsHdrToggle = false,
    this.hdrEnabled = true,
    this.onHdrEnabledChanged,
    this.fallbackReason,
    this.playPauseFocusNode,
    this.onNextChannel,
    this.onPreviousChannel,
    this.onRecordNow,
    this.isRecording = false,
    this.skipPrompt,
    this.upNextPrompt,
    super.key,
  });

  final bool isPlaying;
  final bool isLive;
  final bool canSeek;
  final Duration currentPosition;
  final Duration duration;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onBack;
  final List<PlaybackTrack> audioTracks;
  final List<PlaybackTrack> subtitleTracks;
  final String? selectedAudioTrackId;
  final String? selectedSubtitleTrackId;
  final bool isAudioTrackSelectionKnown;
  final bool isSubtitleTrackSelectionKnown;
  final ValueChanged<String?>? onAudioTrackSelected;
  final ValueChanged<String?>? onSubtitleTrackSelected;
  final ValueChanged<bool>? onTrackDialogVisibilityChanged;
  final bool supportsHdrToggle;
  final bool hdrEnabled;
  final ValueChanged<bool>? onHdrEnabledChanged;
  final String? fallbackReason;
  final FocusNode? playPauseFocusNode;
  final VoidCallback? onNextChannel;
  final VoidCallback? onPreviousChannel;
  final VoidCallback? onRecordNow;
  final bool isRecording;

  /// A comskip/TheIntroDB skip prompt (see `_SkipSegmentPrompt` in
  /// `player_screen.dart`), rendered above the controls bar, left-aligned.
  /// Placed inside this widget's own [DpadRegion] (rather than as a
  /// separate overlay in the parent's Stack) so D-pad up/down can actually
  /// reach it — the region's `stop` edge behavior otherwise keeps focus
  /// confined to this subtree and would skip right over an external sibling
  /// widget entirely.
  final Widget? skipPrompt;

  /// The "up next" card (see `UpNextOverlay`), rendered above the controls
  /// bar, right-aligned. Inside this widget's [DpadRegion] for the same
  /// reason as [skipPrompt] - so the remote can actually move onto it.
  final Widget? upNextPrompt;

  static const Duration seekStep = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = isHandheldLayout(context);

    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      verticalEdge: DpadEdgeBehavior.stop,
      child: ColoredBox(
        color: Colors.black26,
        child: SafeArea(
          // SafeArea above already insets for the platform's real safe zone
          // (notably tvOS's ~80px focus-safe-zone margin, which on TV also
          // passes through _TvZoom's 1.6x scale-up). Stacking the full 40px
          // app padding on top of that compounds into an excessive, "boxed
          // in" inset on tvOS specifically. tvOS gets a much smaller value,
          // pure app-level breathing room rather than a safe-zone duplicate;
          // other platforms (no SafeArea contribution) keep the original 40
          // so macOS/iOS spacing -- already confirmed working -- doesn't
          // change. Phones/tablets get a smaller value too, freeing up
          // vertical room in the short landscape orientation the player
          // locks to. PlayerScreen's diagnostics overlay positions itself
          // against this same value -- see [overlayEdgePaddingFor].
          child: Padding(
            padding: EdgeInsets.all(overlayEdgePaddingFor(context)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildHeader(colorScheme),
                const Spacer(),
                if (upNextPrompt != null) ...[
                  Align(alignment: Alignment.centerRight, child: upNextPrompt),
                  SizedBox(height: compact ? 8 : 14),
                ],
                if (skipPrompt != null) ...[
                  Align(alignment: Alignment.centerLeft, child: skipPrompt),
                  SizedBox(height: compact ? 8 : 14),
                ],
                _buildControlsBar(context, colorScheme, compact: compact),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        DpadFocusable(
          onSelect: onBack,
          effects: const [
            GradientBorderEffect(
              borderRadius: BorderRadius.all(Radius.circular(50)),
            ),
          ],
          child: GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.arrow_back,
                color: colorScheme.onSurface,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (fallbackReason != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              fallbackReason!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlsBar(
    BuildContext context,
    ColorScheme colorScheme, {
    required bool compact,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 24,
        vertical: compact ? 8 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSeek) _buildProgressBar(colorScheme),
          if (canSeek) SizedBox(height: compact ? 6 : 12),
          _buildControlRow(context, colorScheme, compact: compact),
        ],
      ),
    );
  }

  bool get _hasTrackControls =>
      audioTracks.isNotEmpty || subtitleTracks.isNotEmpty || supportsHdrToggle;

  Widget _buildTrackControls() {
    return TrackSelector(
      audioTracks: audioTracks,
      subtitleTracks: subtitleTracks,
      selectedAudioTrackId: selectedAudioTrackId,
      selectedSubtitleTrackId: selectedSubtitleTrackId,
      isAudioTrackSelectionKnown: isAudioTrackSelectionKnown,
      isSubtitleTrackSelectionKnown: isSubtitleTrackSelectionKnown,
      onAudioTrackSelected: onAudioTrackSelected ?? (_) {},
      onSubtitleTrackSelected: onSubtitleTrackSelected ?? (_) {},
      onDialogVisibilityChanged: onTrackDialogVisibilityChanged,
      supportsHdrToggle: supportsHdrToggle,
      hdrEnabled: hdrEnabled,
      onHdrEnabledChanged: onHdrEnabledChanged,
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
    return _SeekBar(
      currentPosition: currentPosition,
      duration: duration,
      onSeek: onSeek,
    );
  }

  bool get _hasChannelControls =>
      isLive &&
      (onPreviousChannel != null ||
          onNextChannel != null ||
          onRecordNow != null);

  int get _liveButtonCount =>
      1 + // play/pause
      (onPreviousChannel != null ? 1 : 0) +
      (onNextChannel != null ? 1 : 0) +
      (onRecordNow != null ? 1 : 0);

  Widget _buildControlRow(
    BuildContext context,
    ColorScheme colorScheme, {
    required bool compact,
  }) {
    final transportControls = _buildTransportControls(context);

    // Handheld (phone/tablet) layout: a Wrap naturally keeps the transport
    // buttons and Audio/Subtitles on one line whenever they fit, and drops
    // to a second line only when they genuinely don't -- based on the
    // actual measured content, not a magic width threshold. The old
    // threshold compared against TrackSelector.controlsWidth regardless of
    // whether both Audio *and* Subtitles buttons were actually present,
    // so which layout you got depended on incidental per-video metadata
    // (e.g. whether a title had subtitle tracks) rather than on the real
    // available space -- the root cause of controls "working" for some
    // videos and not others. The FittedBox is the last-resort fallback for
    // a viewport too short/narrow to fit even the wrapped layout.
    if (compact) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            transportControls,
            if (_hasTrackControls) _buildTrackControls(),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackControlsWidth = _hasTrackControls
            ? TrackSelector.controlsWidth
            : 0.0;
        final transportWidth = isLive
            ? (_hasChannelControls ? _liveButtonCount * 56.0 : 56.0)
            : 168.0;
        final hasRoomForCenteredTransport =
            constraints.maxWidth >= transportWidth + (trackControlsWidth * 2);

        if (_hasTrackControls && !hasRoomForCenteredTransport) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: transportControls),
              const SizedBox(height: 12),
              Center(child: _buildTrackControls()),
            ],
          );
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            Center(child: transportControls),
            if (_hasTrackControls)
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: TrackSelector.controlsWidth,
                  child: _buildTrackControls(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildTransportControls(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isLive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppIconButton(
              icon: Icons.replay_10,
              onPressed: () {
                final target = currentPosition - seekStep;
                final clamped = Duration(
                  milliseconds: target.inMilliseconds.clamp(
                    0,
                    duration.inMilliseconds,
                  ),
                );
                onSeek(clamped);
              },
            ),
          ),
        if (isLive && onPreviousChannel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppIconButton(
              icon: Icons.skip_previous,
              onPressed: onPreviousChannel,
              tooltip: AppLocalizations.of(context).playerSkipPreviousTooltip,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AppIconButton(
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            onPressed: onPlayPause,
            autofocus: playPauseFocusNode == null,
            focusNode: playPauseFocusNode,
          ),
        ),
        if (isLive && onNextChannel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppIconButton(
              icon: Icons.skip_next,
              onPressed: onNextChannel,
              tooltip: AppLocalizations.of(context).playerSkipNextTooltip,
            ),
          ),
        if (isLive && onRecordNow != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppIconButton(
              icon: isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
              onPressed: onRecordNow,
              variant: AppButtonVariant.destructive,
              tooltip: isRecording
                  ? AppLocalizations.of(context).playerStopRecordingTooltip
                  : AppLocalizations.of(context).playerRecordNowTooltip,
            ),
          ),
        if (!isLive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AppIconButton(
              icon: Icons.forward_10,
              onPressed: () {
                final target = currentPosition + seekStep;
                final clamped = Duration(
                  milliseconds: target.inMilliseconds.clamp(
                    0,
                    duration.inMilliseconds,
                  ),
                );
                onSeek(clamped);
              },
            ),
          ),
      ],
    );
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.currentPosition,
    required this.duration,
    required this.onSeek,
  });

  final Duration currentPosition;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  static const Duration _scrubStep = Duration(seconds: 30);

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  final FocusNode _focusNode = FocusNode();
  Timer? _commitTimer;
  Duration? _scrubPosition;
  bool _hasFocus = false;

  Duration get _displayPosition => _scrubPosition ?? widget.currentPosition;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (!_focusNode.hasFocus && _scrubPosition != null) {
      _commit();
    }
  }

  void _adjustScrub(int direction) {
    final current = _scrubPosition ?? widget.currentPosition;
    final next = current + (_SeekBar._scrubStep * direction);
    setState(() {
      _scrubPosition = Duration(
        milliseconds: next.inMilliseconds.clamp(
          0,
          widget.duration.inMilliseconds,
        ),
      );
    });
    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 700), _commit);
  }

  void _seekFromPointer(double localDx, double width) {
    if (widget.duration <= Duration.zero || width <= 0) return;
    final clampedX = localDx.clamp(0.0, width);
    final ratio = clampedX / width;
    setState(() {
      _scrubPosition = Duration(
        milliseconds: (widget.duration.inMilliseconds * ratio).round(),
      );
    });
  }

  void _commitPointerSeek() {
    _commitTimer?.cancel();
    _commitTimer = null;
    final pos = _scrubPosition;
    if (pos == null) return;
    widget.onSeek(pos);
    // Keep thumb visible while the player seeks to the new position.
    _commitTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _scrubPosition = null);
    });
  }

  void _commit() {
    _commitTimer?.cancel();
    _commitTimer = null;
    final pos = _scrubPosition;
    if (pos == null) return;
    setState(() => _scrubPosition = null);
    widget.onSeek(pos);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayPos = _displayPosition;
    final total = widget.duration;
    final isScrubbing = _scrubPosition != null;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (displayPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return DpadFocusable(
      focusNode: _focusNode,
      onSelect: _commit,
      onDirection: (direction) {
        if (direction == TraversalDirection.left) {
          _adjustScrub(-1);
          return true;
        }
        if (direction == TraversalDirection.right) {
          _adjustScrub(1);
          return true;
        }
        return false;
      },
      effects: const [
        GradientBorderEffect(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                formatTime(displayPos),
                style: TextStyle(
                  color: isScrubbing
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: isScrubbing ? FontWeight.w700 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackW = constraints.maxWidth;
                    final fillW = (trackW * progress).clamp(0.0, trackW);
                    final barH = _hasFocus ? 8.0 : 6.0;
                    return GestureDetector(
                      key: const Key('playback-seekbar-track'),
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (details) {
                        _seekFromPointer(details.localPosition.dx, trackW);
                      },
                      onTap: _commitPointerSeek,
                      onHorizontalDragStart: (details) {
                        _seekFromPointer(details.localPosition.dx, trackW);
                      },
                      onHorizontalDragUpdate: (details) {
                        _seekFromPointer(details.localPosition.dx, trackW);
                      },
                      onHorizontalDragEnd: (_) => _commitPointerSeek(),
                      child: SizedBox(
                        height: 16,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (16 - barH) / 2,
                              height: barH,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white30,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: (16 - barH) / 2,
                              width: fillW,
                              height: barH,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            if (_hasFocus || isScrubbing)
                              Positioned(
                                left: (fillW - 8).clamp(0, trackW - 16),
                                top: 0,
                                child: Container(
                                  key: const Key('playback-seekbar-thumb'),
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                formatTime(total),
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
