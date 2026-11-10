import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:m3u_tv/features/player/player_source_settings.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/editor_stream_session_gateway.dart';
import 'package:m3u_tv/playback/now_playing_bridge.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

/// Plays a channel picked in CarPlay while the phone has no screen up for
/// the full-screen player: audio only, controlled from CarPlay's Now Playing
/// screen and the lock screen. Hands over to the full-screen player once the
/// phone's screen opens (see `CarPlayController.onPlayChannel`).
///
/// Follows the full-screen player's rules: the same stream request, Play
/// ignored while tuning, and a long live pause resumes at the live edge.
class CarPlayAudioPlayer {
  CarPlayAudioPlayer({
    required this.buildPlayer,
    required this.sourceFor,
    required ChannelContext Function() allChannels,
    this.currentProgramme,
    NowPlayingBridge? nowPlaying,
  }) : _allChannelsBuilder = allChannels,
       _nowPlaying = nowPlaying ?? NowPlayingBridge.instance;

  /// Plays the way the full-screen player does: the same stream request
  /// (proxy and playback settings applied) and stream session handling.
  factory CarPlayAudioPlayer.forApp(AppStateController appState) {
    return CarPlayAudioPlayer(
      buildPlayer: () => buildCarPlayAudioOrchestrator(
        streamSessionGateway: EditorStreamSessionGateway(
          serverBase: () => appState.xtreamService.credentials?.server,
          stopPlayerStream: appState.stopPlayerStream,
        ),
      ),
      sourceFor: (channel) {
        final args = PlayerArgs.liveChannel(channel);
        return applyPlayerSourceSettings(
          args
              .copyWith(
                streamUrl: appState.applyProxyPlayback(
                  args.streamUrl,
                  type: 'live',
                ),
              )
              .toPlaybackSource(),
          appState.viewSettingsService,
        );
      },
      allChannels: () => CatalogChannelContext(
        repository: appState.catalogRepository,
        length: 0,
      ),
      currentProgramme: (channel) =>
          appState.epgService.lookupForChannel(channel)?.current.title,
    );
  }

  final PlaybackOrchestrator Function() buildPlayer;
  final PlaybackSource Function(Channel channel) sourceFor;

  /// The title airing now on a channel, for Now Playing.
  final String? Function(Channel channel)? currentProgramme;

  final ChannelContext Function() _allChannelsBuilder;
  final NowPlayingBridge _nowPlaying;

  // As in the full-screen player (`PlayerScreen._trackLivePause`).
  static const Duration liveResumeAtEdgeAfter = Duration(seconds: 30);
  static const Duration livePauseReleaseAfter = Duration(minutes: 5);
  static const Duration _epgRefreshInterval = Duration(seconds: 30);

  PlaybackOrchestrator? _orchestrator;
  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<PlaybackError>? _errorSub;
  Channel? _channel;
  ChannelContext _context = ListChannelContext.empty;
  PlaybackStatus _status = PlaybackStatus.idle;
  int _switchGeneration = 0;
  DateTime? _livePausedAt;
  Timer? _livePauseReleaseTimer;
  bool _streamReleased = false;
  Timer? _epgTimer;

  /// The channel playing (or paused), or null when stopped.
  Channel? get channel => _channel;

  /// What next/previous channel moves through.
  ChannelContext get context => _context;

  /// Every live channel, for a context too small to skip through. Kept
  /// across presses so its row hint carries over.
  late final ChannelContext _allChannels = _allChannelsBuilder();

  Future<void> play(Channel channel, ChannelContext context) async {
    _switchGeneration++;
    _channel = channel;
    _context = context;
    _clearLivePause();
    _status = PlaybackStatus.loading;
    _nowPlaying.attach(this, _handleCommand);
    _publish();
    _epgTimer ??= Timer.periodic(_epgRefreshInterval, (_) => _publish());
    final orchestrator = _orchestrator ??= _createOrchestrator();
    try {
      await orchestrator.open(sourceFor(channel));
    } on Object catch (error) {
      debugPrint('[CarPlay] Failed to open ${channel.name}: $error');
    }
  }

  /// Stops playback and releases the player. Completes once the native
  /// player is gone, so another can start straight after.
  Future<void> stop() async {
    _switchGeneration++;
    _channel = null;
    _clearLivePause();
    _epgTimer?.cancel();
    _epgTimer = null;
    _nowPlaying.detach(this);
    final orchestrator = _orchestrator;
    _orchestrator = null;
    // Not awaited, as in PlaybackOrchestrator.dispose: awaiting a cancel and
    // then closing the stream it listened to can deadlock.
    unawaited(_stateSub?.cancel());
    unawaited(_errorSub?.cancel());
    _stateSub = null;
    _errorSub = null;
    _status = PlaybackStatus.idle;
    await orchestrator?.dispose();
  }

  PlaybackOrchestrator _createOrchestrator() {
    final orchestrator = buildPlayer();
    _stateSub = orchestrator.onState.listen(_handleState);
    _errorSub = orchestrator.onError.listen(_handleError);
    return orchestrator;
  }

  void _handleState(PlaybackState state) {
    if (_channel == null) return;
    _status = state.status;
    _trackLivePause(state.status);
    _publish();
  }

  void _handleError(PlaybackError error) {
    if (_channel == null) return;
    debugPrint('[CarPlay] Playback failed: ${error.message}');
    _status = PlaybackStatus.stopped;
    _publish();
  }

  void _publish() {
    final channel = _channel;
    if (channel == null) return;
    _nowPlaying.update(
      this,
      NowPlayingInfo(
        title: channel.name,
        subtitle: currentProgramme?.call(channel),
        artworkUrl: channel.logoUrl,
        isLive: true,
        isPlaying: _status == PlaybackStatus.playing,
        canChangeChannel: true,
        keepPlayingInBackground: true,
        artworkIsLogo: true,
      ),
    );
  }

  void _handleCommand(NowPlayingCommandEvent event) {
    if (_channel == null) return;
    switch (event.command) {
      // CarPlay shows Play while no audio is coming out, tuning included;
      // playback is on its way then (see PlayerScreen's handling).
      case NowPlayingCommand.play:
        if (!_isOpeningOrBuffering) _resume();
      case NowPlayingCommand.pause:
        unawaited(_orchestrator?.pause());
      case NowPlayingCommand.toggle:
        if (_isOpeningOrBuffering) return;
        if (_status == PlaybackStatus.playing) {
          unawaited(_orchestrator?.pause());
        } else {
          _resume();
        }
      case NowPlayingCommand.next:
        unawaited(_switchChannel(1));
      case NowPlayingCommand.previous:
        unawaited(_switchChannel(-1));
      case NowPlayingCommand.seek:
      case NowPlayingCommand.skipForward:
      case NowPlayingCommand.skipBackward:
        // Live: nothing to seek along.
        break;
    }
  }

  bool get _isOpeningOrBuffering =>
      !_streamReleased &&
      (_status == PlaybackStatus.idle ||
          _status == PlaybackStatus.loading ||
          _status == PlaybackStatus.ready ||
          _status == PlaybackStatus.buffering);

  Future<void> _switchChannel(int step) async {
    final channel = _channel;
    if (channel == null) return;
    final channels = _context.length > 1 ? _context : _allChannels;
    // Rapid presses each resolve asynchronously; only the latest plays.
    final generation = ++_switchGeneration;
    final next = await channels.neighbour(channel.id, step);
    if (next == null || generation != _switchGeneration) return;
    await play(next, _context);
  }

  void _trackLivePause(PlaybackStatus status) {
    if (status == PlaybackStatus.paused) {
      if (_livePausedAt != null) return;
      _livePausedAt = clock.now();
      _livePauseReleaseTimer?.cancel();
      _livePauseReleaseTimer = Timer(
        livePauseReleaseAfter,
        _releasePausedStream,
      );
    } else if (status == PlaybackStatus.playing) {
      _clearLivePause();
    }
  }

  void _clearLivePause() {
    _livePausedAt = null;
    _streamReleased = false;
    _livePauseReleaseTimer?.cancel();
    _livePauseReleaseTimer = null;
  }

  /// A long pause comes back at the live edge: reopening is a fresh
  /// connection, like a channel change.
  void _resume() {
    final channel = _channel;
    final pausedAt = _livePausedAt;
    if (channel != null &&
        pausedAt != null &&
        (_streamReleased ||
            clock.now().difference(pausedAt) >= liveResumeAtEdgeAfter)) {
      unawaited(play(channel, _context));
      return;
    }
    unawaited(_orchestrator?.play());
  }

  /// Lets go of the stream (and the provider connection it holds) after a
  /// very long pause; Now Playing stays up, and Play reopens it.
  void _releasePausedStream() {
    _livePauseReleaseTimer = null;
    if (_channel == null || _livePausedAt == null) return;
    _streamReleased = true;
    _status = PlaybackStatus.paused;
    unawaited(_orchestrator?.stop());
  }
}
