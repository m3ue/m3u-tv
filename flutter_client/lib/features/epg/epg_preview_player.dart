import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Builds one isolated embedded player, normally `buildMultiviewTilePlayer`.
typedef EpgPreviewPlayerBuilder =
    ({PlaybackOrchestrator orchestrator, MultiviewBackend backend}) Function(
      String playerId,
    );

/// The live channel playing in the EPG guide's preview panel (see
/// `EpgPreviewPlayback` in view_settings_service.dart).
///
/// Owns at most one embedded player, built the same way as a Multiview tile.
/// Native teardown is always awaited before the surface leaves the tree and
/// before the next player opens: a platform-view backend can hold an
/// unretained pointer into its own view (see app_shell.dart's
/// `_closePlayer`), and two native players alive at once for the full-screen
/// handoff is what crashed Multiview (see `MultiviewScreen._openFullscreen`).
class EpgPreviewPlayerController extends ChangeNotifier {
  EpgPreviewPlayerController({
    required this.buildPlayer,
    String Function(Channel channel)? streamUrlFor,
  }) : streamUrlFor = streamUrlFor ?? _rawStreamUrl;

  final EpgPreviewPlayerBuilder buildPlayer;

  /// The URL to play for a channel. Must match what the full-screen player
  /// requests (proxy playback settings applied) so a handoff between the
  /// two joins the same proxy stream.
  final String Function(Channel channel) streamUrlFor;

  static String _rawStreamUrl(Channel channel) => channel.streamUrl;

  Channel? _channel;
  PlaybackOrchestrator? _orchestrator;
  MultiviewBackend? _backend;
  PlaybackState? _state;
  bool _hasError = false;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<PlaybackError>? _errorSub;
  Future<void> _teardownDone = Future<void>.value();
  int _generation = 0;
  int _nextPlayerSeq = 0;
  bool _disposed = false;

  /// The channel playing (or starting) in the preview, or null when stopped.
  Channel? get channel => _channel;

  /// The backend to render. Outlives [channel] while a stop is still
  /// tearing the native player down, so the surface stays mounted until it
  /// is safe to remove.
  MultiviewBackend? get backend => _backend;

  PlaybackState? get state => _state;
  bool get hasError => _hasError;

  bool isPlaying(Channel channel) => _channel?.id == channel.id;

  /// Starts [channel] in the preview, replacing whatever is playing. A
  /// no-op when it is already playing; a newer call made while this one is
  /// still waiting on teardown wins.
  Future<void> play(Channel channel) async {
    if (_disposed || (isPlaying(channel) && !_hasError)) return;
    final generation = ++_generation;
    await _teardown();
    if (_disposed || generation != _generation) return;
    final built = buildPlayer('epg-preview-${_nextPlayerSeq++}');
    final orchestrator = built.orchestrator;
    _channel = channel;
    _orchestrator = orchestrator;
    _backend = built.backend;
    _state = null;
    _hasError = false;
    _stateSub = orchestrator.onState.listen((state) {
      if (!identical(_orchestrator, orchestrator)) return;
      final previous = _state;
      _state = state;
      final recovered =
          _hasError &&
          (state.status == PlaybackStatus.ready ||
              state.status == PlaybackStatus.playing);
      if (recovered) _hasError = false;
      // Position ticks don't change anything the preview draws, and every
      // notify rebuilds the guide's preview panel.
      if (recovered ||
          previous?.status != state.status ||
          previous?.videoAspectRatio != state.videoAspectRatio) {
        notifyListeners();
      }
    });
    _errorSub = orchestrator.onError.listen((_) {
      if (!identical(_orchestrator, orchestrator)) return;
      _hasError = true;
      notifyListeners();
    });
    notifyListeners();
    try {
      await orchestrator.open(
        PlaybackSource(
          uri: streamUrlFor(channel),
          title: channel.name,
          isLive: true,
          headers: channel.headers,
        ),
      );
    } on Object catch (_) {
      if (!identical(_orchestrator, orchestrator)) return;
      _hasError = true;
      notifyListeners();
    }
  }

  /// Stops the preview. Completes once the native player is fully torn
  /// down, so callers can safely open the full-screen player afterwards.
  /// [keepStreamWarm] leaves the editor proxy stream running (see
  /// [PlaybackOrchestrator.detachStreamSession]) for a player about to
  /// request the same channel.
  Future<void> stop({bool keepStreamWarm = false}) {
    _generation++;
    if (keepStreamWarm) _orchestrator?.detachStreamSession();
    return _teardown();
  }

  Future<void> _teardown() {
    final orchestrator = _orchestrator;
    if (orchestrator == null) return _teardownDone;
    final backend = _backend;
    _orchestrator = null;
    _channel = null;
    unawaited(_stateSub?.cancel());
    unawaited(_errorSub?.cancel());
    _stateSub = null;
    _errorSub = null;
    _teardownDone = _teardownDone.then((_) async {
      try {
        await orchestrator.dispose().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Same trade-off as AppShell._closePlayer: better to leak a
        // not-fully-disposed adapter than leave the guide stuck.
      }
      if (!identical(_backend, backend)) return;
      _backend = null;
      _state = null;
      _hasError = false;
      if (!_disposed) notifyListeners();
    });
    if (!_disposed) notifyListeners();
    return _teardownDone;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_teardown());
    super.dispose();
  }
}

/// The preview's video, with a loading spinner, an error state and the
/// channel name. Shown in place of the programme artwork while
/// [EpgPreviewPlayerController.backend] is set.
class EpgPreviewVideo extends StatelessWidget {
  const EpgPreviewVideo({super.key, required this.controller, this.onTap});

  final EpgPreviewPlayerController controller;

  /// Desktop mouse click on the video (opens the full-screen player).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final backend = controller.backend;
    final state = controller.state;
    final channel = controller.channel;
    final hasError = controller.hasError;
    final nativePlaneActive =
        !hasError &&
        backend is NativePlaneProvider &&
        (backend! as NativePlaneProvider).usesNativePlane;
    final loading =
        channel != null &&
        (state == null ||
            state.status == PlaybackStatus.loading ||
            state.status == PlaybackStatus.buffering);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: ColoredBox(
          color: nativePlaneActive ? Colors.transparent : Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NativeVideoSurface.forBackend(
                backend,
                // A new key per player instance so a channel switch never
                // reuses the previous player's attached native view.
                key: ObjectKey(backend),
                aspectRatio: state?.videoAspectRatio ?? 16 / 9,
                wrapInBlackBackground: false,
                clearAncestorPaintForNativePlane: nativePlaneActive,
              ),
              if (hasError)
                const Center(
                  child: Icon(Icons.error_outline, color: Colors.white),
                )
              else if (loading)
                const Center(
                  child: SizedBox.square(
                    dimension: 32,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              if (channel != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
