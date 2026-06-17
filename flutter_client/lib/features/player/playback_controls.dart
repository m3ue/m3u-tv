import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/features/player/format_time.dart';

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
    this.fallbackReason,
    this.playPauseFocusNode,
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
  final String? fallbackReason;
  final FocusNode? playPauseFocusNode;

  static const Duration seekStep = Duration(seconds: 10);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      verticalEdge: DpadEdgeBehavior.stop,
      child: Container(
        padding: const EdgeInsets.all(40),
        color: Colors.black26,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildHeader(colorScheme),
            const Spacer(),
            _buildControlsBar(colorScheme),
          ],
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
            DpadBorderEffect(
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

  Widget _buildControlsBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canSeek) _buildProgressBar(colorScheme),
          if (canSeek) const SizedBox(height: 12),
          _buildControlRow(colorScheme),
        ],
      ),
    );
  }

  Widget _buildProgressBar(ColorScheme colorScheme) {
    return _SeekBar(
      currentPosition: currentPosition,
      duration: duration,
      onSeek: onSeek,
    );
  }

  Widget _buildControlRow(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isLive)
          _ControlButton(
            icon: Icons.replay_10,
            onTap: () {
              final target = currentPosition - seekStep;
              final clamped = Duration(
                milliseconds: target.inMilliseconds.clamp(
                  0,
                  duration.inMilliseconds,
                ),
              );
              onSeek(clamped);
            },
            colorScheme: colorScheme,
          ),
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onTap: onPlayPause,
          colorScheme: colorScheme,
          autofocus: playPauseFocusNode == null,
          focusNode: playPauseFocusNode,
        ),
        if (!isLive)
          _ControlButton(
            icon: Icons.forward_10,
            onTap: () {
              final target = currentPosition + seekStep;
              final clamped = Duration(
                milliseconds: target.inMilliseconds.clamp(
                  0,
                  duration.inMilliseconds,
                ),
              );
              onSeek(clamped);
            },
            colorScheme: colorScheme,
          ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.onTap,
    required this.colorScheme,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onTap,
      effects: const [
        DpadBorderEffect(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ],
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 22, color: colorScheme.onSurface),
        ),
      ),
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
        DpadBorderEffect(
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
