import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Builds the preview's player: the same orchestrator the full-screen
/// player uses (`buildPlaybackOrchestrator`), so the full-screen player can
/// take it over mid-stream (see [EpgPreviewPlayerController.lend]).
typedef EpgPreviewPlayerBuilder = PlaybackOrchestrator Function();

/// A playing preview handed to the full-screen player, and back. The
/// [surfaceKey] goes on the native video view in both places, so the view
/// moves between them instead of being recreated (which restarts playback).
class EpgPreviewLease {
  const EpgPreviewLease({
    required this.orchestrator,
    required this.channel,
    required this.surfaceKey,
  });

  final PlaybackOrchestrator orchestrator;
  final Channel channel;
  final GlobalKey surfaceKey;

  EpgPreviewLease withChannel(Channel channel) => EpgPreviewLease(
    orchestrator: orchestrator,
    channel: channel,
    surfaceKey: surfaceKey,
  );
}

/// Hands a playing preview to the full-screen player, which calls
/// [adoptBack] when it closes to give the player back to the preview. That
/// returns false when the guide can no longer show it, and the full-screen
/// player then disposes it as usual.
typedef EpgPreviewHandoff =
    void Function(
      EpgPreviewLease lease,
      bool Function(EpgPreviewLease lease) adoptBack,
    );

/// The live channel playing in the EPG guide's preview panel (see
/// `EpgPreviewPlayback` in view_settings_service.dart).
///
/// Owns at most one player. Native teardown is always awaited before the
/// surface leaves the tree and before the next player opens: a
/// platform-view backend can hold an unretained pointer into its own view
/// (see app_shell.dart's `_closePlayer`), and two native players alive at
/// once is what crashed Multiview (see `MultiviewScreen._openFullscreen`).
/// Going full screen doesn't tear it down: [lend] hands the player itself
/// over, and [adoptBack] takes it back.
class EpgPreviewPlayerController extends ChangeNotifier {
  EpgPreviewPlayerController({
    required this.buildPlayer,
    PlaybackSource Function(Channel channel)? sourceFor,
    this.onOpened,
  }) : sourceFor = sourceFor ?? _rawSource;

  final EpgPreviewPlayerBuilder buildPlayer;

  /// The source to play for a channel. Must match what the full-screen
  /// player requests (proxy playback and playback settings applied), since
  /// the full-screen player carries on with whatever the preview opened.
  /// Display mode changes are always held off in the guide; the full-screen
  /// player allows them when it takes over.
  final PlaybackSource Function(Channel channel) sourceFor;

  /// Called once a channel has opened, for the settings the full-screen
  /// player pushes after opening (see `applyPlayerOpenedSettings`).
  final void Function(PlaybackOrchestrator orchestrator)? onOpened;

  static PlaybackSource _rawSource(Channel channel) => PlaybackSource(
    uri: channel.streamUrl,
    title: channel.name,
    isLive: true,
    headers: channel.headers,
  );

  Channel? _channel;
  PlaybackOrchestrator? _orchestrator;
  // The player [lend] last handed out: one lent while still opening still
  // gets [onOpened] once it has.
  PlaybackOrchestrator? _lentOrchestrator;
  PlaybackOrchestrator? _surfaceOrchestrator;
  GlobalKey? _surfaceKey;
  PlaybackState? _state;
  bool _hasError = false;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<PlaybackError>? _errorSub;
  Future<void> _teardownDone = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;

  /// The channel playing (or starting) in the preview, or null when stopped.
  Channel? get channel => _channel;

  /// The player to render. Outlives [channel] while a stop is still
  /// tearing the native player down, so the surface stays mounted until it
  /// is safe to remove.
  PlaybackOrchestrator? get surfaceOrchestrator => _surfaceOrchestrator;

  /// The key for the native video view of [surfaceOrchestrator].
  GlobalKey? get surfaceKey => _surfaceKey;

  PlaybackState? get state => _state;
  bool get hasError => _hasError;

  bool isPlaying(Channel channel) => _channel?.id == channel.id;

  /// Whether [adoptBack] would take a player back right now.
  bool get canAdoptBack =>
      !_disposed && _orchestrator == null && _surfaceOrchestrator == null;

  /// Starts [channel] in the preview, replacing whatever is playing. A
  /// no-op when it is already playing; a newer call made while this one is
  /// still waiting on teardown wins.
  Future<void> play(Channel channel) async {
    if (_disposed || (isPlaying(channel) && !_hasError)) return;
    // Lent to the full-screen player: the guide is hidden beneath it, and a
    // second player must not start until that one comes back or is gone.
    if (_lentOrchestrator != null) return;
    final generation = ++_generation;
    await _teardown();
    if (_disposed || generation != _generation) return;
    final orchestrator = buildPlayer();
    _attach(orchestrator, channel, GlobalKey(debugLabel: 'epg-preview'));
    notifyListeners();
    try {
      await orchestrator.open(
        sourceFor(channel).copyWith(allowDisplayModeChanges: false),
      );
      if (identical(_orchestrator, orchestrator) ||
          identical(_lentOrchestrator, orchestrator)) {
        onOpened?.call(orchestrator);
      }
    } on Object catch (_) {
      if (!identical(_orchestrator, orchestrator)) return;
      _hasError = true;
      notifyListeners();
    }
  }

  /// Hands the playing player to the full-screen player without stopping
  /// it, or returns null when there is nothing healthy to hand over. The
  /// preview stops rendering it straight away, so the caller must mount
  /// [EpgPreviewLease.surfaceKey] in the same frame (synchronously, before
  /// any await) for the native view to move rather than be disposed.
  EpgPreviewLease? lend() {
    final orchestrator = _orchestrator;
    final channel = _channel;
    final surfaceKey = _surfaceKey;
    if (_disposed ||
        orchestrator == null ||
        channel == null ||
        surfaceKey == null ||
        _hasError) {
      return null;
    }
    _generation++;
    _detach();
    _lentOrchestrator = orchestrator;
    _surfaceOrchestrator = null;
    _surfaceKey = null;
    notifyListeners();
    return EpgPreviewLease(
      orchestrator: orchestrator,
      channel: channel,
      surfaceKey: surfaceKey,
    );
  }

  /// Takes back a player [lend] handed out (possibly on another channel by
  /// now). Like [lend], the caller must drop [EpgPreviewLease.surfaceKey]
  /// in the same frame. Returns false, leaving the player with the caller,
  /// when the preview can't take it (see [canAdoptBack]).
  bool adoptBack(EpgPreviewLease lease) {
    if (!canAdoptBack) return false;
    _generation++;
    _lentOrchestrator = null;
    _attach(lease.orchestrator, lease.channel, lease.surfaceKey);
    _state = lease.orchestrator.lastState;
    notifyListeners();
    return true;
  }

  /// Forgets a player [lend] handed out that won't come back through
  /// [adoptBack] (the full-screen player disposed it instead), so the
  /// preview can play again.
  void forgetLent() => _lentOrchestrator = null;

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

  void _attach(
    PlaybackOrchestrator orchestrator,
    Channel channel,
    GlobalKey surfaceKey,
  ) {
    _channel = channel;
    _orchestrator = orchestrator;
    _surfaceOrchestrator = orchestrator;
    _surfaceKey = surfaceKey;
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
          previous?.backend != state.backend ||
          previous?.videoAspectRatio != state.videoAspectRatio) {
        notifyListeners();
      }
    });
    _errorSub = orchestrator.onError.listen((_) {
      if (!identical(_orchestrator, orchestrator)) return;
      _hasError = true;
      notifyListeners();
    });
  }

  void _detach() {
    _orchestrator = null;
    _channel = null;
    _state = null;
    _hasError = false;
    unawaited(_stateSub?.cancel());
    unawaited(_errorSub?.cancel());
    _stateSub = null;
    _errorSub = null;
  }

  Future<void> _teardown() {
    final orchestrator = _orchestrator;
    if (orchestrator == null) return _teardownDone;
    _detach();
    _teardownDone = _teardownDone.then((_) async {
      try {
        await orchestrator.dispose().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // Same trade-off as AppShell._closePlayer: better to leak a
        // not-fully-disposed adapter than leave the guide stuck.
      }
      if (!identical(_surfaceOrchestrator, orchestrator)) return;
      _surfaceOrchestrator = null;
      _surfaceKey = null;
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
/// [EpgPreviewPlayerController.surfaceOrchestrator] is set.
class EpgPreviewVideo extends StatelessWidget {
  const EpgPreviewVideo({super.key, required this.controller, this.onTap});

  final EpgPreviewPlayerController controller;

  /// Desktop mouse click on the video (opens the full-screen player).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final orchestrator = controller.surfaceOrchestrator;
    final state = controller.state;
    final channel = controller.channel;
    final hasError = controller.hasError;
    final nativePlaneActive =
        !hasError && (orchestrator?.isNativePlaneActive ?? false);
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
              NativeVideoSurface(
                // A new key per player instance so a channel switch never
                // reuses the previous player's attached native view.
                key: ObjectKey(orchestrator),
                surfaceKey: controller.surfaceKey,
                textureId: orchestrator?.activeTextureId,
                platformView: orchestrator?.activePlatformViewProvider,
                htmlView: orchestrator?.activeHtmlViewProvider,
                nativePlane: orchestrator?.activeNativePlaneProvider,
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
