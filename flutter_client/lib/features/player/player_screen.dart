import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

/// Full-screen player screen with playback controls, EPG overlay,
/// resume prompt, backend fallback display, and progress reporting.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.args,
    required this.orchestrator,
    required this.epgService,
    this.xtreamService,
    this.progressReporter,
    this.viewerId = '',
    this.onClose,
    super.key,
  });

  final PlayerArgs args;
  final PlaybackOrchestrator orchestrator;
  final EpgService epgService;
  final XtreamService? xtreamService;
  final void Function(Progress progress)? progressReporter;
  final String viewerId;
  final VoidCallback? onClose;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Duration _loadingTimeout = Duration(seconds: 20);
  static const Duration _progressInterval = Duration(seconds: 10);
  static const Duration _overlayTimeout = Duration(seconds: 8);

  PlaybackStatus _status = PlaybackStatus.idle;
  Duration _currentPosition = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  String? _fallbackReason;
  bool _isPlaying = false;

  List<PlaybackTrack> _audioTracks = [];
  List<PlaybackTrack> _subtitleTracks = [];
  String? _selectedAudioTrackId;
  String? _selectedSubtitleTrackId;

  EpgCurrentNext? _epgData;

  bool _overlayVisible = true;

  // Owns the outer Focus so we can steal focus from the content area when
  // the player opens, and reclaim it whenever the overlay hides.
  final FocusNode _screenFocusNode = FocusNode();

  // Handed to the play/pause button so _showOverlay() can jump focus there.
  final FocusNode _controlsFocusNode = FocusNode();

  // Handed to the "Go back" button on the error screen.
  final FocusNode _errorButtonFocusNode = FocusNode();

  Timer? _loadingTimer;
  Timer? _overlayHideTimer;
  Timer? _progressTimer;
  Timer? _positionTimer;
  Timer? _epgTimer;
  Future<void>? _epgFetch;

  StreamSubscription<PlaybackState>? _stateSubscription;
  StreamSubscription<PlaybackError>? _errorSubscription;

  bool _disposed = false;

  bool get _isLive => widget.args.type == 'live';
  bool get _canSeek => !_isLive && _duration > Duration.zero;

  @override
  void initState() {
    super.initState();
    // Steal focus from the content area (autofocus won't do this if another
    // widget already holds focus when the player opens via the AppShell Stack).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Overlay is visible on open — focus the play/pause button directly
        // so D-pad traversal works immediately. Falls back to _screenFocusNode
        // if somehow the overlay was already hidden.
        if (_overlayVisible) {
          _controlsFocusNode.requestFocus();
        } else {
          _screenFocusNode.requestFocus();
        }
      }
    });
    _startPlayback();
    _startLoadingTimeout();
    _scheduleOverlayHide();
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed || !mounted || !_isPlaying || _isLive) return;
      setState(() {
        final next = _currentPosition + const Duration(milliseconds: 500);
        _currentPosition = (_duration > Duration.zero && next > _duration)
            ? _duration
            : next;
      });
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _loadingTimer?.cancel();
    _overlayHideTimer?.cancel();
    _progressTimer?.cancel();
    _positionTimer?.cancel();
    _epgTimer?.cancel();
    _screenFocusNode.dispose();
    _controlsFocusNode.dispose();
    _errorButtonFocusNode.dispose();
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(widget.orchestrator.stop());
    super.dispose();
  }

  // Sets the error state and reclaims _screenFocusNode after the next frame.
  // PlaybackControls is hidden when _errorMessage is set, so without this the
  // escape-to-close Shortcuts would have no focused node to route through.
  void _setErrorMessage(String message) {
    setState(() {
      _errorMessage = message;
      _status = PlaybackStatus.idle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _errorButtonFocusNode.requestFocus();
    });
  }

  void _startPlayback() {
    _stateSubscription = widget.orchestrator.onState.listen(_handleState);
    _errorSubscription = widget.orchestrator.onError.listen(_handleError);

    final source = widget.args.toPlaybackSource();

    unawaited(
      widget.orchestrator.open(source).catchError((Object error) {
        if (!_disposed && mounted) _setErrorMessage(error.toString());
      }),
    );
  }

  void _startLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(_loadingTimeout, () {
      if (!_disposed &&
          mounted &&
          (_status == PlaybackStatus.loading ||
              _status == PlaybackStatus.idle)) {
        _setErrorMessage(
          'Stream loading timed out. The server may be unreachable or the stream URL is invalid.',
        );
      }
    });
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(_overlayTimeout, () {
      if (!_disposed && mounted) {
        setState(() => _overlayVisible = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_overlayVisible) _screenFocusNode.requestFocus();
        });
      }
    });
  }

  void _handleState(PlaybackState state) {
    if (_disposed || !mounted) return;

    _loadingTimer?.cancel();

    setState(() {
      _status = state.status;
      _currentPosition = state.position;
      if (state.duration != null && state.duration! > Duration.zero) {
        _duration = state.duration!;
      }
      _audioTracks = state.audioTracks;
      _subtitleTracks = state.subtitleTracks;
      _selectedAudioTrackId = state.selectedAudioTrackId;
      _selectedSubtitleTrackId = state.selectedSubtitleTrackId;

      if (state.status == PlaybackStatus.playing) {
        _isPlaying = true;
        _errorMessage = null;
        if (!_isLive) _startPositionTimer();
      } else if (state.status == PlaybackStatus.paused ||
          state.status == PlaybackStatus.buffering) {
        if (state.status == PlaybackStatus.paused) _isPlaying = false;
        _stopPositionTimer();
      } else if (state.status == PlaybackStatus.completed) {
        _isPlaying = false;
        _stopPositionTimer();
        _goBack();
      }
    });

    final backend = widget.orchestrator.activeBackend;
    if (backend == PlaybackBackend.serverTranscode) {
      setState(() {
        _fallbackReason = 'Server transcode active';
      });
    }

    if (state.status == PlaybackStatus.playing && !_isLive) {
      _startProgressReporting();
    }

    if (_isLive &&
        (state.status == PlaybackStatus.ready ||
            state.status == PlaybackStatus.playing)) {
      _startEpgRefresh();
    }
  }

  void _handleError(PlaybackError error) {
    if (_disposed || !mounted) return;

    _loadingTimer?.cancel();

    if (error.recoverable) {
      final backend = widget.orchestrator.activeBackend;
      if (backend == PlaybackBackend.serverTranscode) {
        setState(() {
          _fallbackReason = error.message;
        });
        return;
      }
    }

    _setErrorMessage(error.message);
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) {
      if (_disposed || !mounted) return;
      widget.progressReporter?.call(
        Progress(
          viewerId: widget.viewerId,
          contentType: _isLive
              ? ContentType.live
              : (widget.args.type == 'series'
                    ? ContentType.episode
                    : ContentType.vod),
          streamId: widget.args.streamId ?? 0,
          positionSeconds: _currentPosition.inSeconds,
          durationSeconds: _duration.inSeconds > 0 ? _duration.inSeconds : null,
          seriesId: widget.args.seriesId,
          seasonNumber: widget.args.seasonNumber,
        ),
      );
    });
  }

  void _startEpgRefresh() {
    if (!_isLive) return;
    _epgTimer?.cancel();
    unawaited(_updateEpg());
    _epgTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_disposed || !mounted) return;
      unawaited(_updateEpg());
    });
  }

  Future<void> _updateEpg() async {
    if (!_isLive || widget.args.epgChannelId == null) return;
    final channelId = widget.args.epgChannelId!;
    final result = widget.epgService.lookup(channelId);
    if (result != null) {
      if (mounted) {
        setState(() => _epgData = result);
      }
      return;
    }

    if (mounted) {
      setState(() => _epgData = result);
    }

    final streamId = widget.args.streamId;
    final xtreamService = widget.xtreamService;
    if (streamId == null || xtreamService == null || _epgFetch != null) return;

    final fetch = xtreamService.getShortEpg(
      streamId,
      channelId: channelId,
      limit: 4,
    );
    _epgFetch = fetch;
    try {
      final programs = await fetch;
      if (_disposed || !mounted) return;
      widget.epgService.mergePrograms(programs);
      final refreshed = widget.epgService.lookup(channelId);
      if (mounted) {
        setState(() => _epgData = refreshed);
      }
    } on Object catch (_) {
      if (_disposed || !mounted) return;
    } finally {
      if (identical(_epgFetch, fetch)) {
        _epgFetch = null;
      }
    }
  }

  void _goBack() {
    if (_disposed || !mounted) return;
    // Return focus to _screenFocusNode before closing. AppShell's restoration
    // logic (savedFocus / _contentFocusNode fallback) was designed around
    // _screenFocusNode being the primary focus when the player closes. If a
    // DpadFocusable child (error button, controls) is primary instead, its
    // Focus widget unmounts and detaches the node before PlayerScreen.dispose()
    // runs, breaking the parent chain and causing _willDisposeFocusNode to
    // corrupt _contentFocusNode._focusedChild.
    if (!_screenFocusNode.hasPrimaryFocus) {
      _screenFocusNode.requestFocus();
    }
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      unawaited(widget.orchestrator.pause());
    } else {
      unawaited(widget.orchestrator.play());
    }
  }

  void _seekTo(Duration position) {
    if (!_canSeek) return;
    unawaited(widget.orchestrator.seek(position));
  }

  void _handleAudioTrackSelected(String? trackId) {
    unawaited(widget.orchestrator.setAudioTrack(trackId));
  }

  void _handleSubtitleTrackSelected(String? trackId) {
    unawaited(widget.orchestrator.setSubtitleTrack(trackId));
  }

  void _showOverlay() {
    setState(() => _overlayVisible = true);
    _scheduleOverlayHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayVisible) _controlsFocusNode.requestFocus();
    });
  }

  void _hideOverlay() {
    _overlayHideTimer?.cancel();
    setState(() => _overlayVisible = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_overlayVisible) _screenFocusNode.requestFocus();
    });
  }

  void _handleBack() {
    if (_errorMessage != null) {
      _goBack();
      return;
    }
    if (_overlayVisible) {
      _hideOverlay();
    } else {
      _goBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const _BackIntent(),
          LogicalKeySet(LogicalKeyboardKey.goBack): const _BackIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaPlayPause):
              const _PlayPauseIntent(),
          // Only claim arrow keys when the overlay is hidden — when visible,
          // let dpad's root Shortcuts handle them for spatial navigation.
          if (!_overlayVisible) ...{
            LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                const _SeekBackIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowRight):
                const _SeekForwardIntent(),
          },
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _BackIntent: _BackAction(_handleBack),
            _PlayPauseIntent: _PlayPauseAction(_togglePlayPause),
            _SeekBackIntent: _SeekAction(
              () => _seekTo(_currentPosition - const Duration(seconds: 10)),
            ),
            _SeekForwardIntent: _SeekAction(
              () => _seekTo(_currentPosition + const Duration(seconds: 10)),
            ),
          },
          child: Focus(
            focusNode: _screenFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  !_overlayVisible &&
                  _errorMessage == null) {
                // Don't intercept back/escape — let the Shortcuts above handle
                // it as a direct back action. Intercepting it here would set
                // _overlayVisible = true, causing _handleBack() to call
                // _hideOverlay() instead of _goBack(), making back a no-op.
                final key = event.logicalKey;
                final isBack =
                    key == LogicalKeyboardKey.escape ||
                    key == LogicalKeyboardKey.goBack;
                if (!isBack) _showOverlay();
              }
              return KeyEventResult.ignored;
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: _VideoSurface(
                    textureId: widget.orchestrator.activeTextureId,
                  ),
                ),

                if (widget.orchestrator.activeSubtitleController != null)
                  Positioned.fill(
                    child: mkv.SubtitleView(
                      controller: widget.orchestrator.activeSubtitleController!,
                      configuration: const mkv.SubtitleViewConfiguration(),
                    ),
                  ),

                // Loading indicator
                if (_status == PlaybackStatus.loading && _errorMessage == null)
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'Loading stream...',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),

                // Error display
                if (_errorMessage != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Playback error',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 24),
                          DpadFocusable(
                            focusNode: _errorButtonFocusNode,
                            onSelect: _goBack,
                            effects: const [
                              GradientBorderEffect(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(50),
                                ),
                              ),
                            ],
                            child: FilledButton.icon(
                              onPressed: _goBack,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Go back'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Playback controls overlay
                if (_overlayVisible && _errorMessage == null)
                  PlaybackControls(
                    isPlaying: _isPlaying,
                    isLive: _isLive,
                    canSeek: _canSeek,
                    currentPosition: _currentPosition,
                    duration: _duration,
                    onPlayPause: _togglePlayPause,
                    onSeek: _seekTo,
                    onBack: _goBack,
                    audioTracks: _audioTracks,
                    subtitleTracks: _subtitleTracks,
                    selectedAudioTrackId: _selectedAudioTrackId,
                    selectedSubtitleTrackId: _selectedSubtitleTrackId,
                    onAudioTrackSelected: _handleAudioTrackSelected,
                    onSubtitleTrackSelected: _handleSubtitleTrackSelected,
                    fallbackReason: _fallbackReason,
                    playPauseFocusNode: _controlsFocusNode,
                  ),

                if (_overlayVisible && _errorMessage == null)
                  Positioned(
                    top: 40,
                    right: 40,
                    child: _PlaybackDiagnosticsPanel(
                      activeBackend: widget.orchestrator.activeBackend,
                      diagnostics: widget.orchestrator.diagnostics,
                    ),
                  ),

                // Hidden overlay tap area
                if (!_overlayVisible && _errorMessage == null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _showOverlay,
                      child: const SizedBox.expand(),
                    ),
                  ),

                // EPG overlay (live only)
                if (_isLive && _epgData != null && _overlayVisible)
                  Positioned(
                    top: 40,
                    left: 104,
                    width: 420,
                    child: EpgOverlay(
                      currentTitle: _epgData!.current.title,
                      currentProgress: _epgData!.progress,
                      nextTitle: _epgData?.next?.title,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.textureId});

  final int? textureId;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) return const ColoredBox(color: Colors.black);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Texture(textureId: id),
        ),
      ),
    );
  }
}

class _PlaybackDiagnosticsPanel extends StatelessWidget {
  const _PlaybackDiagnosticsPanel({
    required this.activeBackend,
    required this.diagnostics,
  });

  final PlaybackBackend? activeBackend;
  final List<String> diagnostics;

  @override
  Widget build(BuildContext context) {
    final snapshot = _PlaybackDiagnosticsSnapshot.from(
      activeBackend: activeBackend,
      diagnostics: diagnostics,
    );
    final rows = <Widget>[
      _DiagnosticsRow(label: 'Backend', value: snapshot.backendLabel),
      if (snapshot.fallbackReason != null)
        _DiagnosticsRow(label: 'Fallback', value: snapshot.fallbackReason!),
      if (snapshot.codecDecision != null)
        _DiagnosticsRow(label: 'Codec', value: snapshot.codecDecision!),
      if (snapshot.transcodeSession != null)
        _DiagnosticsRow(label: 'Transcode', value: snapshot.transcodeSession!),
      if (snapshot.cleanupStatus != null)
        _DiagnosticsRow(label: 'Cleanup', value: snapshot.cleanupStatus!),
      if (snapshot.androidMpvStatus != null)
        _DiagnosticsRow(
          label: 'Android mpv/libmpv',
          value: snapshot.androidMpvStatus!,
        ),
    ];

    return IgnorePointer(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackDiagnosticsSnapshot {
  const _PlaybackDiagnosticsSnapshot({
    required this.backendLabel,
    this.fallbackReason,
    this.codecDecision,
    this.transcodeSession,
    this.cleanupStatus,
    this.androidMpvStatus,
  });

  final String backendLabel;
  final String? fallbackReason;
  final String? codecDecision;
  final String? transcodeSession;
  final String? cleanupStatus;
  final String? androidMpvStatus;

  static _PlaybackDiagnosticsSnapshot from({
    required PlaybackBackend? activeBackend,
    required List<String> diagnostics,
  }) {
    var backendLabel = _backendLabel(activeBackend);
    String? fallbackReason;
    String? codecDecision;
    String? transcodeSession;
    String? cleanupStatus;
    String? androidMpvStatus;

    for (final item in diagnostics) {
      if (item.startsWith('active-backend:')) {
        final backend = _backendFromDiagnostic(item);
        if (backend != null) backendLabel = _backendLabel(backend);
      } else if (item.startsWith('fallback-reason:')) {
        final parsed = _parseKeyValueDiagnostic(item, 'fallback-reason:');
        codecDecision = parsed.key;
        fallbackReason = parsed.value;
      } else if (item.startsWith('server-transcode:')) {
        final parts = item.split(':');
        final streamId = parts.length > 1 ? parts[1] : 'unknown stream';
        final sessionId = parts.length > 2 ? parts[2] : 'no session';
        transcodeSession = sessionId == 'null'
            ? streamId
            : '$streamId / $sessionId';
      } else if (item.startsWith('cleanup:server-transcode:stopped:')) {
        final payload = item.substring(
          'cleanup:server-transcode:stopped:'.length,
        );
        cleanupStatus = 'server transcode stopped ($payload)';
      } else if (item.startsWith('android-mpv:disabled-future-gated:')) {
        final reason = item.substring(
          'android-mpv:disabled-future-gated:'.length,
        );
        androidMpvStatus = 'disabled/future-gated ($reason)';
      }
    }

    return _PlaybackDiagnosticsSnapshot(
      backendLabel: backendLabel,
      fallbackReason: fallbackReason,
      codecDecision: codecDecision,
      transcodeSession: transcodeSession,
      cleanupStatus: cleanupStatus,
      androidMpvStatus: androidMpvStatus,
    );
  }

  static ({String key, String value}) _parseKeyValueDiagnostic(
    String item,
    String prefix,
  ) {
    final payload = item.substring(prefix.length);
    final separator = payload.indexOf(':');
    if (separator < 0) return (key: payload, value: payload);
    return (
      key: payload.substring(0, separator),
      value: payload.substring(separator + 1),
    );
  }

  static PlaybackBackend? _backendFromDiagnostic(String item) {
    final parts = item.split(':');
    if (parts.length < 2) return null;
    return switch (parts[1]) {
      'androidExoPlayer' => PlaybackBackend.androidExoPlayer,
      'androidMpv' => PlaybackBackend.androidMpv,
      'appleMpvKit' => PlaybackBackend.appleMpvKit,
      'appleAvKit' => PlaybackBackend.appleAvKit,
      'desktopLibmpv' => PlaybackBackend.desktopLibmpv,
      'serverTranscode' => PlaybackBackend.serverTranscode,
      _ => null,
    };
  }

  static String _backendLabel(PlaybackBackend? backend) {
    return switch (backend) {
      PlaybackBackend.androidExoPlayer => 'Android ExoPlayer',
      PlaybackBackend.androidMpv => 'Android mpv/libmpv disabled',
      PlaybackBackend.appleMpvKit => 'Apple MPVKit',
      PlaybackBackend.appleAvKit => 'Apple AVKit fallback',
      PlaybackBackend.desktopLibmpv => 'Desktop libmpv',
      PlaybackBackend.serverTranscode => 'Server transcode fallback',
      null => 'Selecting backend',
    };
  }
}

/// Badge showing the reason for backend fallback.
class FallbackReasonBadge extends StatelessWidget {
  const FallbackReasonBadge({required this.reason, super.key});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        reason,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}

class _SeekBackIntent extends Intent {
  const _SeekBackIntent();
}

class _SeekForwardIntent extends Intent {
  const _SeekForwardIntent();
}

class _BackAction extends Action<_BackIntent> {
  _BackAction(this.onBack);
  final VoidCallback onBack;
  @override
  Object? invoke(_BackIntent intent) {
    onBack();
    return null;
  }
}

class _PlayPauseAction extends Action<_PlayPauseIntent> {
  _PlayPauseAction(this.onToggle);
  final VoidCallback onToggle;
  @override
  Object? invoke(_PlayPauseIntent intent) {
    onToggle();
    return null;
  }
}

class _SeekAction extends Action<Intent> {
  _SeekAction(this.onSeek);
  final VoidCallback onSeek;
  @override
  Object? invoke(Intent intent) {
    onSeek();
    return null;
  }
}
