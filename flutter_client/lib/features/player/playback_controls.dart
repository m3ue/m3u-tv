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

  static const Duration seekStep = Duration(seconds: 10);

  double _progress() {
    if (duration.inMilliseconds == 0) return 0;
    return (currentPosition.inMilliseconds / duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
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
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        GestureDetector(
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
    final progress = _progress();

    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            formatTime(currentPosition),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            formatTime(duration),
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildControlRow(ColorScheme colorScheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ControlButton(
          icon: isPlaying ? Icons.pause : Icons.play_arrow,
          onTap: onPlayPause,
          colorScheme: colorScheme,
        ),
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
  });

  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
    );
  }
}
