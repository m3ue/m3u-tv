import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/features/player/catchup_timeline.dart';
import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/episode_picker.dart';
import 'package:m3u_tv/features/player/now_playing_overlay.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_diagnostics_panel.dart';
import 'package:m3u_tv/features/player/player_shortcuts.dart';
import 'package:m3u_tv/features/player/player_skip_prompts.dart';
import 'package:m3u_tv/features/player/player_skip_segments.dart';
import 'package:m3u_tv/features/player/player_source_settings.dart';
import 'package:m3u_tv/features/player/up_next_overlay.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/comskip_service.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/desktop_fullscreen_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cached_backdrop_image.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

const bool _showPlaybackDiagnostics = bool.fromEnvironment(
  'M3U_TV_SHOW_PLAYBACK_DIAGNOSTICS',
);

/// App-level playback volume only applies on desktop -- TV/mobile have their
/// own hardware/system volume controls and should always play at full
/// volume through this app.
bool get _isDesktop =>
    HostPlatform.isMacOS || HostPlatform.isWindows || HostPlatform.isLinux;

/// How far past the credits mark to wait before raising the "up next" card,
/// so it doesn't fight the skip-credits prompt for the screen (and focus).
const _kUpNextDelayAfterCredits = Duration(seconds: 5);

/// Full-screen player screen with playback controls, EPG overlay,
/// resume prompt, backend fallback display, and progress reporting.
/// Lets a host route a Back press into the mounted player's own handling
/// (dismiss the track dialog / up-next card / OSD first, close last), so a
/// back that reaches the host instead of the player still behaves the same.
class PlayerBackController {
  VoidCallback? _handler;

  /// Runs the attached player's Back handling. False when no player is
  /// attached.
  bool handleBack() {
    final handler = _handler;
    if (handler == null) return false;
    handler();
    return true;
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.args,
    required this.orchestrator,
    required this.epgService,
    this.xtreamService,
    this.comskipSettings,
    this.comskipService,
    this.introDbSettings,
    this.hasDvrFeature = false,
    this.progressReporter,
    this.traktService,
    this.wakelockController = const PlatformWakelockController(),
    this.viewerId = '',
    this.onClose,
    this.onPlaybackFailure,
    this.onLiveStreamEnded,
    this.onNextChannel,
    this.onPreviousChannel,
    this.onReplaceItem,
    this.onRecordProgram,
    this.onTrackDialogVisibilityChanged,
    this.backController,
    this.onBackKey,
    this.isRecordingCurrentChannel = false,
    this.viewSettingsService,
    this.isHandheld = false,
    this.adoptsPlayingSession = false,
    this.surfaceKey,
    this.releasesOrchestratorOnDispose,
    super.key,
  });

  final PlayerArgs args;
  final PlaybackOrchestrator orchestrator;

  /// [orchestrator] is already playing [args] (the EPG preview's player,
  /// taken over for full screen): carry on with it instead of opening it.
  final bool adoptsPlayingSession;

  /// See [NativeVideoSurface.surfaceKey]: the EPG preview's key for the
  /// native view [orchestrator] is already rendering into.
  final Key? surfaceKey;

  /// Asked on dispose whether to stop [orchestrator]; false when it went
  /// back to the EPG preview, which keeps playing it. Null stops it.
  final bool Function()? releasesOrchestratorOnDispose;
  final EpgService epgService;
  final XtreamService? xtreamService;
  final ComskipSettings? comskipSettings;

  /// Fetches the recording's commercial-break segments. Defaults to a fresh
  /// [ComskipService]; tests inject one over a fake HTTP client.
  final ComskipService? comskipService;

  /// Null behaves as enabled (the setting's default).
  final IntroDbSettings? introDbSettings;
  final bool hasDvrFeature;
  final void Function(Progress progress)? progressReporter;
  final TraktService? traktService;
  final WakelockController wakelockController;
  final String viewerId;
  final ViewSettingsService? viewSettingsService;
  final VoidCallback? onClose;
  final VoidCallback? onPlaybackFailure;
  final Future<String?> Function()? onLiveStreamEnded;
  final VoidCallback? onNextChannel;
  final VoidCallback? onPreviousChannel;

  /// Swaps the currently playing item for `args` on the same player session
  /// (no route push/pop). Used by the "up next" overlay to roll straight into
  /// the next series episode. Mirrors how live TV reuses the player for
  /// channel skip - see `didUpdateWidget`.
  final void Function(PlayerArgs args)? onReplaceItem;
  final Future<void> Function(EpgProgram program)? onRecordProgram;
  final ValueChanged<bool>? onTrackDialogVisibilityChanged;

  /// Attached to this player's Back handling while it is mounted.
  final PlayerBackController? backController;

  /// Host hook for an Escape/GoBack key press, so a host that also receives
  /// the platform's own back message (Android TV, tvOS) can treat the pair
  /// as one press and route it back through [backController]. Null handles
  /// the key directly.
  final VoidCallback? onBackKey;
  final bool isRecordingCurrentChannel;

  /// True for phones/tablets (never TV/desktop -- see `DeviceType` in
  /// `app_shell.dart`). Locks the device into landscape for the duration of
  /// this screen and restores portrait on close, since a handheld video
  /// player is cramped and inconsistently laid out in portrait, and the
  /// user has to fight the OS's rotation lock to get a usable landscape
  /// view otherwise.
  final bool isHandheld;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Duration _loadingTimeout = Duration(seconds: 20);
  static const Duration _progressInterval = Duration(seconds: 10);
  static const Duration _overlayTimeout = Duration(seconds: 8);

  PlaybackStatus _status = PlaybackStatus.idle;

  // The position the controls display ([_skipScrubPosition] while a skip
  // scrub is pending, else [_currentPosition]). Position ticks only update
  // this notifier, so they rebuild the seek bar and "ends at" label instead
  // of the whole player overlay twice a second.
  final ValueNotifier<Duration> _displayPosition = ValueNotifier(
    Duration.zero,
  );
  Duration _positionValue = Duration.zero;
  Duration get _currentPosition => _positionValue;
  set _currentPosition(Duration value) {
    _positionValue = value;
    _syncDisplayPosition();
  }

  void _syncDisplayPosition() {
    _displayPosition.value = _skipScrubPositionValue ?? _positionValue;
  }

  Duration _duration = Duration.zero;
  String? _errorMessage;
  String? _fallbackReason;
  String? _retryStatusMessage;
  bool _isPlaying = false;
  double _videoAspectRatio = 16 / 9;

  // Latches on the first `ready`/`playing`/`paused` state for the current source so
  // the bottom controls bar stays hidden while the stream is still loading
  // (its buttons can't do anything yet). Reset on a channel/episode switch.
  bool _hasStartedPlayback = false;

  // Keeps the loading overlay up past `ready` until the first frame is
  // actually showing. mpv reports `ready` on FILE_LOADED (stream probed, cache
  // not filled, nothing decoded), so a slow stream otherwise sits on a black
  // screen with the OSD up for several seconds. Reset on a channel/episode
  // switch.
  bool _awaitingFirstFrame = true;

  // Handheld only: the video surface is held back (plain black instead)
  // until the forced portrait->landscape rotation has settled. Android
  // Hybrid Composition snapshots the current Flutter frame when a platform
  // view first mounts, so mounting it on the very first player frame -
  // while the window is still portrait - leaves the previous screen's
  // portrait frame stretched across the landscape video rect until the
  // first decoded frame covers it. Capped well under the ~2s the Android
  // mpv `load` call waits for its view (MpvPlayerPlugin.waitForCore). With
  // no rotation to wait out (TV, or already landscape), Android still holds
  // the surface for the player's first frames - see
  // [_markVideoSurfaceReadyAfterFirstFrames].
  static const Duration _surfaceRotationSettle = Duration(milliseconds: 200);
  static const Duration _surfaceRotationMaxHold = Duration(milliseconds: 1000);
  bool _videoSurfaceReady = false;
  bool _sawPortraitBeforeSurface = false;
  // Android only: the first source opens once the surface hold above ends -
  // see [_openInitialSource].
  bool _initialOpenPending = false;
  Timer? _videoSurfaceSettleTimer;
  Timer? _videoSurfaceMaxHoldTimer;

  List<PlaybackTrack> _audioTracks = [];
  List<PlaybackTrack> _subtitleTracks = [];
  String? _selectedAudioTrackId;
  String? _selectedSubtitleTrackId;
  bool _isAudioTrackSelectionKnown = false;
  bool _isSubtitleTrackSelectionKnown = false;
  late bool _hdrEnabled = widget.viewSettingsService?.hdrEnabledSync ?? true;
  late double _volume = widget.viewSettingsService?.volumeSync ?? 1.0;

  EpgCurrentNext? _epgData;

  late final PlayerSkipSegments _skips = PlayerSkipSegments(
    position: () => _currentPosition,
    duration: () => _duration,
    bumpPosition: (position) => _currentPosition = position,
    seek: widget.orchestrator.seek,
    comskipService: widget.comskipService ?? ComskipService(),
    autoSkipEnabled: () => widget.comskipSettings?.autoSkipEnabled ?? false,
    introDbEnabled: () => widget.introDbSettings?.enabled != false,
  );

  // ── Up next (series only) ──────────────────────────────────────────────
  // Populated once per episode from get_series_info: the next episode to roll
  // into, shown as a bottom-right card from the credits mark (or ~90% in when
  // TheIntroDB has no credits segment) until the user dismisses it.
  Series? _upNextSeries;
  Episode? _nextEpisode;
  bool _upNextVisible = false;
  bool _upNextDismissed = false;

  /// Full series/episode data from the same `get_series_info` fetch as
  /// "up next", kept around so the episode picker (any episode, not just
  /// the next one) doesn't need its own request.
  SeriesInfo? _seriesInfo;

  /// Focus target for the up-next card's Play button - the player moves focus
  /// here the moment the card appears so the remote lands on it, not the
  /// transport bar.
  final FocusNode _upNextFocusNode = FocusNode(debugLabel: 'playerUpNext');

  bool _overlayVisible = true;
  bool _trackDialogVisible = false;
  bool _dvrSchedulePending = false;

  // Android system Picture-in-Picture (entered via MainActivity's
  // onUserLeaveHint while this screen is the active route). The transport
  // controls are unusable at PiP's tiny window size, so they're hidden and
  // kept from reappearing (_showOverlay below) for the duration.
  bool _isInPictureInPicture = false;
  static const _pipChannel = MethodChannel('m3u_tv/system_ui');

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
  Timer? _liveEndHoldTimer;
  bool _liveEndHold = false;
  String? _liveEndReason;
  Future<void>? _epgFetch;

  StreamSubscription<PlaybackState>? _stateSubscription;
  StreamSubscription<PlaybackError>? _errorSubscription;
  StreamSubscription<bool>? _nativePlaneSubscription;

  bool _disposed = false;
  bool _traktScrobbleActive = false;
  bool _failureReported = false;
  double _lastValidProgress = 0;

  // Catchup only: the controls show the programme's timeline (see
  // CatchupTimeline), so position and duration are mapped from whichever
  // timeshift stream is open for it. While a reopened stream loads, the old
  // stream's position reports no longer apply, so the landing point is held
  // on screen until the new stream has opened. A seek's target is held on
  // screen the same way while it waits for the buffer or for a reopen.
  CatchupTimeline? _catchup;
  bool _catchupStreamSeekable = false;
  bool _catchupReopenPending = false;
  int _catchupReopenGeneration = 0;
  int _catchupSeekGeneration = 0;
  Duration? _catchupSeekTarget;
  // Last position the open stream reported, on its own clock.
  Duration _catchupStreamPosition = Duration.zero;

  // The platform view stays mounted while a reopen swaps the stream. open()
  // clears the active adapter until the new load starts, and unmounting the
  // view in that gap makes the native side re-create its player core when
  // the view comes back, tearing down the core the new load was sent to.
  PlatformViewProvider? _reopenPlatformView;

  bool get _isLive => widget.args.type == 'live';
  bool get _canSeek =>
      !_isLive && _duration > Duration.zero && !_seekBlockedByTranscode;

  /// Transcoded VOD/series output can't be seeked (only direct proxy can), so
  /// seeking is withheld rather than offered and silently ignored (#98).
  /// Catchup is left alone: its seeks reopen the timeshift stream at the
  /// target instead of seeking the open one.
  bool get _seekBlockedByTranscode =>
      (widget.args.transcoded && (widget.args.type == 'vod' || _isSeries)) ||
      widget.orchestrator.activeBackend == PlaybackBackend.serverTranscode;
  bool get _isSeries => widget.args.type == 'series';
  bool get _isNativePlaneActive => widget.orchestrator.isNativePlaneActive;

  String _nowPlayingBadgeLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _isSeries ? l10n.playerNowPlayingSeries : l10n.playerNowPlayingMovie;
  }

  String _nowPlayingTitle() {
    final seriesName = widget.args.metadata['series_name'] as String?;
    if (_isSeries && seriesName != null && seriesName.isNotEmpty) {
      return seriesName;
    }
    return widget.args.title;
  }

  String? _nowPlayingSubtitle(BuildContext context) {
    if (!_isSeries) return null;
    final season = widget.args.metadata['season_number'] as int?;
    final episode = widget.args.metadata['episode_number'] as int?;
    final episodeTitle = widget.args.metadata['episode_title'] as String?;

    final parts = <String>[];
    if (season != null && episode != null) {
      parts.add(
        AppLocalizations.of(
          context,
        ).playerNowPlayingSeasonEpisode(season, episode),
      );
    }
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      parts.add(episodeTitle);
    }
    return parts.isEmpty ? null : parts.join(' — ');
  }

  String? _nowPlayingDescription() {
    return widget.args.metadata['plot'] as String?;
  }

  @override
  void initState() {
    super.initState();
    // Screen must stay on for the entire time the player route is active,
    // not just while actively playing — e.g. staying paused on an overlay
    // shouldn't let the screen sleep. Enabled here, disabled in dispose().
    unawaited(widget.wakelockController.enable());
    widget.backController?._handler = _handleBack;
    DesktopFullscreenService.instance?.deferEscape = _defersFullscreenEscape;
    if (HostPlatform.isAndroid) {
      _pipChannel.setMethodCallHandler(_handlePipChannelCall);
    }
    if (widget.adoptsPlayingSession) {
      // The native view already exists and is playing: it must mount in
      // this first frame to move here from the preview (see surfaceKey).
      _videoSurfaceReady = true;
      if (widget.isHandheld) {
        unawaited(
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]),
        );
      }
    } else if (widget.isHandheld) {
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
      // Safety net in case the rotation never lands (e.g. split-screen or
      // freeform windows that ignore the orientation request).
      _videoSurfaceMaxHoldTimer = Timer(
        _surfaceRotationMaxHold,
        _markVideoSurfaceReady,
      );
    } else {
      _markVideoSurfaceReadyAfterFirstFrames();
    }
    // Steal focus from the content area (autofocus won't do this if another
    // widget already holds focus when the player opens via the AppShell Stack).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // The controls bar (and its play/pause button) isn't built until
        // playback starts, so hold focus on the screen until then;
        // _handleState moves it onto play/pause once the bar appears.
        _focusControlsOrScreen();
      }
    });
    _skips.addListener(_onSkipSegmentsChanged);
    _stateSubscription = widget.orchestrator.onState.listen(_handleState);
    _errorSubscription = widget.orchestrator.onError.listen(_handleError);
    // `_isNativePlaneActive` reads the orchestrator directly rather than
    // caching its value, so nothing otherwise triggers a rebuild when it
    // flips -- without this, AppShell's own onNativePlaneCompositionChanged
    // listener (app_shell.dart) could un-suppress the opaque browsing shell
    // behind this screen before this screen's own backgroundColor toggle
    // (which only updates via _handleState/_handleError) catches up.
    _nativePlaneSubscription = widget
        .orchestrator
        .onNativePlaneCompositionChanged
        .listen((_) {
          if (mounted) setState(() {});
        });
    _resetCatchupTimeline(widget.args);
    if (widget.adoptsPlayingSession) {
      // onState doesn't replay, so start from where the session already is.
      final state = widget.orchestrator.lastState;
      if (state != null) _handleState(state);
    } else {
      _openInitialSource();
    }
    _startLoadingTimeout();
    _scheduleOverlayHide();
    _loadSkipSegments(widget.args);
    unawaited(_initUpNext(widget.args));
  }

  // Live-TV skip-previous/skip-next replaces `args` on an already-mounted
  // PlayerScreen (AppShell keeps the same orchestrator/State alive across a
  // channel switch — see app_shell.dart's `_playerSessionId` — so the single
  // native player behind Media3/AVKit is never torn down mid-switch). Reset
  // everything initState/_openSource would normally set up for a fresh
  // mount, but reuse the existing stream subscriptions rather than doubling
  // them up on the same orchestrator.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_videoSurfaceReady || !widget.isHandheld) return;
    final size = MediaQuery.sizeOf(context);
    if (size.width < size.height) {
      _sawPortraitBeforeSurface = true;
      return;
    }
    if (!_sawPortraitBeforeSurface) {
      // Already landscape on open (e.g. a tablet) - no rotation to wait for.
      _videoSurfaceMaxHoldTimer?.cancel();
      _markVideoSurfaceReadyAfterFirstFrames();
      return;
    }
    // Rotated to landscape - give the rotation a moment to finish before
    // the platform view mounts.
    _videoSurfaceSettleTimer ??= Timer(
      _surfaceRotationSettle,
      _markVideoSurfaceReady,
    );
  }

  void _markVideoSurfaceReady() {
    _videoSurfaceSettleTimer?.cancel();
    _videoSurfaceMaxHoldTimer?.cancel();
    if (_disposed || !mounted || _videoSurfaceReady) return;
    setState(() => _videoSurfaceReady = true);
    if (_initialOpenPending) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPendingInitialSource(),
      );
    }
  }

  // Android starts playback only once the player has drawn its own black
  // placeholder and the surface hold has ended: the native load (ExoPlayer or
  // mpv setup) runs on the platform thread, which Hybrid Composition also
  // composites Flutter frames on, so opening on the first frame left this
  // screen stuck half-drawn over the one it opened from until the stream had
  // loaded. Other platforms open straight away.
  void _openInitialSource() {
    if (widget.orchestrator.platform != PlaybackPlatform.android) {
      unawaited(_openSource(widget.args));
      return;
    }
    _initialOpenPending = true;
    if (_videoSurfaceReady) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openPendingInitialSource(),
      );
    }
  }

  void _openPendingInitialSource() {
    if (!_initialOpenPending || _disposed || !mounted) return;
    _initialOpenPending = false;
    unawaited(_openSource(widget.args));
  }

  // For an open with no rotation to wait out. Android's Hybrid Composition
  // snapshot still applies: a surface mounted on the player's very first
  // frame captures the screen the player opened over (e.g. a detail page),
  // left showing behind the overlay until the first decoded frame covers it
  // (seen on Shield TV). Two frames of the player's own black first make
  // that black the snapshot instead.
  void _markVideoSurfaceReadyAfterFirstFrames() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      _videoSurfaceReady = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance
        ..addPostFrameCallback((_) => _markVideoSurfaceReady())
        ..scheduleFrame();
    });
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger a rebuild so PlaybackControls shows the correct record/stop icon
    // whenever the recording state changes.
    if (oldWidget.isRecordingCurrentChannel !=
        widget.isRecordingCurrentChannel) {
      if (mounted) setState(() {});
    }
    if (_isSamePlaybackSession(oldWidget.args, widget.args)) return;

    if (_traktScrobbleActive) _scrobbleFor(oldWidget.args, 'stop');
    _traktScrobbleActive = false;
    _failureReported = false;
    _lastValidProgress = 0;
    _stopPositionTimer();
    _progressTimer?.cancel();
    _epgTimer?.cancel();
    _epgFetch = null;
    _liveEndHoldTimer?.cancel();
    // Read before _openSource clears the active adapter.
    final keptView =
        widget.orchestrator.activePlatformViewProvider ?? _reopenPlatformView;

    setState(() {
      _status = PlaybackStatus.idle;
      _liveEndHold = false;
      _liveEndReason = null;
      _currentPosition = Duration.zero;
      _duration = Duration.zero;
      _errorMessage = null;
      _fallbackReason = null;
      _retryStatusMessage = null;
      _isPlaying = false;
      _hasStartedPlayback = false;
      _awaitingFirstFrame = true;
      _videoAspectRatio = 16 / 9;
      _audioTracks = const <PlaybackTrack>[];
      _subtitleTracks = const <PlaybackTrack>[];
      _selectedAudioTrackId = null;
      _selectedSubtitleTrackId = null;
      _epgData = null;
      _overlayVisible = true;
      _skips.reset();
      _upNextVisible = false;
      _upNextDismissed = false;
      _nextEpisode = null;
      _upNextSeries = null;
      _seriesInfo = null;
      _resetCatchupTimeline(widget.args);
      _reopenPlatformView = keptView;
    });

    _initialOpenPending = false;
    unawaited(_openSwitchedSource(widget.args));
    _startLoadingTimeout();
    _scheduleOverlayHide();
    _loadSkipSegments(widget.args);
    unawaited(_initUpNext(widget.args));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayVisible) _focusControlsOrScreen();
    });
  }

  /// Opens [args] on the player already showing something else (a channel
  /// change, the next episode), keeping its native view mounted until the
  /// new stream has opened, for the same reason as a catchup reopen (see
  /// [_reopenPlatformView]).
  Future<void> _openSwitchedSource(PlayerArgs args) async {
    final generation = _catchupReopenGeneration;
    await _openSource(args);
    if (_disposed || !mounted || generation != _catchupReopenGeneration) {
      return;
    }
    setState(() => _reopenPlatformView = null);
  }

  // Two channels can share a stream URL while differing in stream ID,
  // headers, EPG ID, or metadata (e.g. a proxied/transcoded URL keyed by
  // query params that get stripped, or distinct catchup sources pointing at
  // the same base live URL) — comparing streamUrl alone would silently skip
  // the switch and leave the previous channel's state in place.
  bool _isSamePlaybackSession(PlayerArgs a, PlayerArgs b) {
    return a.streamUrl == b.streamUrl &&
        a.streamId == b.streamId &&
        a.type == b.type &&
        a.epgChannelId == b.epgChannelId &&
        mapEquals(a.headers, b.headers) &&
        mapEquals(a.metadata, b.metadata);
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_disposed ||
          !mounted ||
          !_isPlaying ||
          _isLive ||
          _catchupReopenPending ||
          _catchupSeekTarget != null) {
        return;
      }
      final next = _currentPosition + const Duration(milliseconds: 500);
      _currentPosition = (_duration > Duration.zero && next > _duration)
          ? _duration
          : next;
      _skips.check();
      _checkUpNext();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _onSkipSegmentsChanged() {
    if (mounted) setState(() {});
  }

  /// Fetches comskip and TheIntroDB segments for [args]. Both are
  /// fire-and-forget: a miss just leaves the player without skip prompts.
  void _loadSkipSegments(PlayerArgs args) {
    bool isCurrent() => mounted && identical(args, widget.args);
    unawaited(
      _skips.loadComskip(
        args,
        xtreamService: widget.xtreamService,
        hasDvrFeature: widget.hasDvrFeature,
        isCurrent: isCurrent,
      ),
    );
    unawaited(_skips.loadIntroDb(args, isCurrent: isCurrent));
  }

  // ── Up next (series only) ──────────────────────────────────────────────

  /// Resolves the next episode for the currently playing series episode from
  /// `get_series_info` (already cached client-side). Fire-and-forget, like
  /// the skip-segment loads: a missing series id, a non-series item, or any fetch
  /// failure just leaves `_nextEpisode` null and the overlay never appears.
  Future<void> _initUpNext(PlayerArgs args) async {
    if (args.type != 'series') return;
    final seriesId = args.seriesId;
    final service = widget.xtreamService;
    if (seriesId == null || service == null) return;

    final season = args.seasonNumber ?? args.metadata['season_number'] as int?;
    final episode = args.metadata['episode_number'] as int?;
    if (season == null || episode == null) return;

    try {
      final info = await service.getSeriesInfo(seriesId);
      if (!mounted || !identical(args, widget.args)) return;
      setState(() {
        _upNextSeries = info.series;
        _seriesInfo = info;
        _nextEpisode = nextEpisodeInSeries(
          info,
          seasonNumber: season,
          episodeNumber: episode,
        );
      });
    } on Object catch (_) {
      // No "up next" affordance if the series info can't be fetched.
    }
  }

  /// Shows the overlay once the play-head reaches the credits mark (or ~90%
  /// in when TheIntroDB has no credits segment, mirroring the editor's
  /// `completed` threshold). Stays until dismissed or the episode ends;
  /// seeking back before the threshold hides it again.
  void _checkUpNext() {
    if (_disposed ||
        !mounted ||
        _upNextDismissed ||
        _upNextVisible ||
        _nextEpisode == null) {
      return;
    }
    final creditsStartMs = _skips.introDbSegments?.credits?.startMs;
    final shouldShow = creditsStartMs != null
        // Hold off until the skip-credits prompt has had its moment.
        ? _currentPosition.inMilliseconds >=
              creditsStartMs + _kUpNextDelayAfterCredits.inMilliseconds
        : _duration > Duration.zero && _currentPosition >= _duration * 0.9;
    if (!shouldShow) return;

    // The card lives inside the control overlay (so it's D-pad reachable), so
    // force the OSD up and pin it there while the card is showing, then drop
    // focus onto the card's Play button once it's laid out.
    setState(() {
      _upNextVisible = true;
      _overlayVisible = true;
    });
    _overlayHideTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _upNextVisible) _upNextFocusNode.requestFocus();
    });
  }

  void _dismissUpNext() {
    setState(() {
      _upNextVisible = false;
      _upNextDismissed = true;
    });
    // Hand focus back to the transport controls rather than letting Flutter
    // reparent it wherever after the card unmounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayVisible) _focusControlsOrScreen();
    });
    _scheduleOverlayHide();
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next == null) return;
    // No startPosition: "up next" always begins the next episode from the
    // top, even if the viewer had previously sampled it. The in-place swap
    // path (_openPlayerDirect) doesn't consult the resume store, and that's
    // the intended behaviour here - not an oversight.
    _playEpisode(next);
  }

  /// Swaps playback to any episode of the current series - shared by "up
  /// next" (always the next episode) and the episode picker (any episode
  /// the viewer chooses).
  void _playEpisode(Episode episode) {
    final seriesId = widget.args.seriesId;
    final onReplace = widget.onReplaceItem;
    if (seriesId == null || onReplace == null) return;
    final args = episodePlayerArgs(
      episode: episode,
      seriesId: seriesId,
      seriesName:
          (widget.args.metadata['series_name'] as String?) ?? widget.args.title,
      series: _upNextSeries,
    );
    if (args != null) onReplace(args);
  }

  /// Opens the episode picker dialog for the current series, letting the
  /// viewer jump directly to any episode without leaving playback.
  void _showEpisodePicker() {
    final info = _seriesInfo;
    if (info == null) return;
    final season =
        widget.args.seasonNumber ??
        widget.args.metadata['season_number'] as int?;
    // Prefer the authoritative string id (set by `episodePlayerArgs`) over
    // `streamId`, which is a lossy `int.tryParse` of that same id and can be
    // null - stringifying a null `streamId` directly would otherwise send
    // the literal text "null" in as the "current episode" to match against.
    final currentEpisodeId =
        (widget.args.metadata['episode_id'] as String?) ??
        widget.args.streamId?.toString() ??
        '';
    _handleTrackDialogVisibilityChanged(true);
    unawaited(
      showEpisodePicker(
        context,
        info: info,
        currentSeasonNumber: season,
        currentEpisodeId: currentEpisodeId,
        onSelect: _playEpisode,
      ).whenComplete(() => _handleTrackDialogVisibilityChanged(false)),
    );
  }

  /// The one active skip prompt (comskip or TheIntroDB — the two never
  /// overlap since comskip is DVR-only and TheIntroDB is VOD/series-only),
  /// or null when neither is active. `context` is only needed for
  /// localized labels.
  Widget? _buildSkipPrompt(BuildContext context) {
    final skips = _skips;
    if (skips.activeComskipSegment != null) {
      return SkipSegmentPrompt(
        label: AppLocalizations.of(context).playerSkipCommercial,
        onSkip: skips.confirmComskipSkip,
      );
    }
    // Once the "up next" card is up it takes over the end-of-episode moment;
    // a redundant "skip credits" button beside it just competes for focus.
    if (skips.introDbPromptVisible(overlayVisible: _overlayVisible) &&
        !_upNextVisible) {
      return SkipSegmentPrompt(
        label: skips.introDbMatchedKind == IntroDbSegmentKind.intro
            ? AppLocalizations.of(context).playerSkipIntro
            : AppLocalizations.of(context).playerSkipCredits,
        onSkip: skips.confirmIntroDbSkip,
        countdownShownAt: skips.introDbCountdownActive
            ? skips.introDbCountdownShownAt
            : null,
        countdownDuration: skips.introDbCountdownActive
            ? kIntroDbPromptCountdown
            : null,
      );
    }
    return null;
  }

  void _scrobble(String action) => _scrobbleFor(widget.args, action);

  void _scrobbleFor(PlayerArgs args, String action) {
    final service = widget.traktService;
    if (service == null || service.status != TraktAuthStatus.connected) return;
    if (args.type == 'live' || args.type == 'catchup') return;
    final duration = _duration.inSeconds;
    var progress = duration > 0
        ? (_currentPosition.inSeconds / duration * 100).clamp(0.0, 100.0)
        : (action == 'start' ? 0.0 : null);
    if (progress == null) return;
    // Trakt rejects pause with < 1% progress. Skip rather than spam 422s.
    if (action == 'pause' && progress < 1.0) return;
    // For stop, fall back to the last known valid progress so we always record.
    if (action == 'stop' && progress < 1.0 && _lastValidProgress > 0) {
      progress = _lastValidProgress;
    }
    if (progress > 0) _lastValidProgress = progress;
    unawaited(
      service.scrobble(
        action: action,
        title: args.title,
        seriesTitle: args.type == 'series'
            ? args.metadata['series_name'] as String?
            : null,
        season: args.seasonNumber ?? args.metadata['season_number'] as int?,
        episode: args.metadata['episode_number'] as int?,
        tmdbId: args.metadata['tmdb_id'] as int?,
        imdbId: args.metadata['aio_item_id'] as String?,
        progress: progress,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    // A new session's player can mount before this one unmounts, so only
    // detach what is still ours.
    final backController = widget.backController;
    if (backController?._handler == _handleBack) {
      backController!._handler = null;
    }
    final fullscreen = DesktopFullscreenService.instance;
    if (fullscreen?.deferEscape == _defersFullscreenEscape) {
      fullscreen!.deferEscape = null;
    }
    if (HostPlatform.isAndroid) {
      _pipChannel.setMethodCallHandler(null);
    }
    if (widget.isHandheld) {
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
    if (_traktScrobbleActive) _scrobble('stop');
    _loadingTimer?.cancel();
    _videoSurfaceSettleTimer?.cancel();
    _videoSurfaceMaxHoldTimer?.cancel();
    _overlayHideTimer?.cancel();
    _progressTimer?.cancel();
    _positionTimer?.cancel();
    _epgTimer?.cancel();
    _liveEndHoldTimer?.cancel();
    _skipCommitTimer?.cancel();
    _skips.dispose();
    _screenFocusNode.dispose();
    _controlsFocusNode.dispose();
    _errorButtonFocusNode.dispose();
    _upNextFocusNode.dispose();
    _displayPosition.dispose();
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_nativePlaneSubscription?.cancel());
    unawaited(widget.wakelockController.disable());
    if (widget.releasesOrchestratorOnDispose?.call() ?? true) {
      unawaited(widget.orchestrator.stop());
    }
    super.dispose();
  }

  // Sets the error state and reclaims _screenFocusNode after the next frame.
  // PlaybackControls is hidden when _errorMessage is set, so without this the
  // escape-to-close Shortcuts would have no focused node to route through.
  void _setErrorMessage(String message) {
    if (!_failureReported) {
      _failureReported = true;
      widget.onPlaybackFailure?.call();
    }
    setState(() {
      _errorMessage = message;
      _status = PlaybackStatus.idle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) _errorButtonFocusNode.requestFocus();
    });
  }

  Future<void> _openSource(PlayerArgs args) {
    return _openAndSeek(
      applyPlayerSourceSettings(
        args.toPlaybackSource(),
        widget.viewSettingsService,
        hdrEnabled: _hdrEnabled,
      ),
    );
  }

  void _resetCatchupTimeline(PlayerArgs args) {
    _catchup = args.type == 'catchup'
        ? CatchupTimeline.fromMetadata(args.metadata)
        : null;
    _catchupStreamSeekable = false;
    _catchupReopenPending = false;
    _catchupReopenGeneration++;
    _catchupSeekGeneration++;
    _catchupSeekTarget = null;
    _catchupStreamPosition = Duration.zero;
    _reopenPlatformView = null;
    _duration = _catchup?.duration ?? Duration.zero;
  }

  Future<void> _openAndSeek(PlaybackSource source) async {
    try {
      await widget.orchestrator.open(source);
      applyPlayerOpenedSettings(
        widget.orchestrator,
        hdrEnabled: _hdrEnabled,
        volume: _volume,
      );
      if (_disposed || !mounted || source.isLive) return;
      // A non-recoverable load failure lets open() return normally (the
      // failure is reported asynchronously via onError/_handleError instead
      // of being thrown here) but leaves no active adapter behind. Without
      // this guard, seek() below throws a bare StateError that this
      // function's own catch clause then shows via _setErrorMessage,
      // clobbering the real error _handleError already surfaced.
      if (source.startPosition > Duration.zero &&
          widget.orchestrator.activeBackend != null) {
        await widget.orchestrator.seek(source.startPosition);
      }
    } on Object catch (error) {
      if (!_disposed && mounted) _setErrorMessage(error.toString());
    }
  }

  static bool _isMpvBackend(PlaybackBackend backend) => switch (backend) {
    PlaybackBackend.androidMpv ||
    PlaybackBackend.appleMpvNative ||
    PlaybackBackend.desktopLibmpv ||
    PlaybackBackend.macMpvNative => true,
    PlaybackBackend.androidExoPlayer ||
    PlaybackBackend.appleAvKit ||
    PlaybackBackend.serverTranscode ||
    PlaybackBackend.webVideo => false,
  };

  // `buffering` before the first frame is still the initial load (ExoPlayer
  // and AVKit emit it right after open), so it keeps the overlay up too.
  bool get _showLoadingOverlay =>
      _errorMessage == null &&
      (_status == PlaybackStatus.loading ||
          (_awaitingFirstFrame &&
              (_status == PlaybackStatus.ready ||
                  _status == PlaybackStatus.buffering)));

  /// The item's art, shown full-bleed behind the loading indicator while a
  /// VOD/series stream opens, so the screen doesn't sit on a flat black
  /// background. Prefers the wide backdrop/fanart image (same art the
  /// detail screens' hero uses) over the portrait poster, which `BoxFit
  /// .cover` would otherwise have to crop in hard to fill a landscape
  /// screen. Null for live/catchup, where there's no meaningful art (and
  /// the channel logo badge already fills that role).
  String? get _loadingBackdropUrl {
    if (widget.args.type != 'vod' && widget.args.type != 'series') {
      return null;
    }
    final metadata = widget.args.metadata;
    return (metadata['backdrop_url'] as String?) ??
        (metadata['poster_url'] as String?);
  }

  void _startLoadingTimeout() {
    _loadingTimer?.cancel();
    _loadingTimer = Timer(_loadingTimeout, () {
      if (!_disposed &&
          mounted &&
          (_status == PlaybackStatus.loading ||
              _status == PlaybackStatus.idle)) {
        _setErrorMessage(AppLocalizations.of(context).playerLoadTimedOut);
      }
    });
  }

  void _scheduleOverlayHide() {
    _overlayHideTimer?.cancel();
    // Keep the OSD pinned while the up-next card is riding inside it.
    if (_upNextVisible) return;
    // While paused, keep the overlay up indefinitely - there's no reason to
    // hide info the user is deliberately looking at. Playback resuming (or
    // the initial load reaching `playing`) reschedules the timer below.
    if (!_isPlaying) return;
    // While the audio/subtitle track dialog is open, don't let this timer
    // unmount PlaybackControls (and steal focus back to the player) out
    // from under the still-open dialog. Rescheduled once the dialog closes.
    if (_trackDialogVisible) return;
    // Keep the overlay visible while a DVR recording is being scheduled so
    // the user can see the recording badge appear (or a failure message).
    if (_dvrSchedulePending) return;
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

    // Position ticks resend the current status on every update, so the
    // overlay hide timer and Trakt scrobbling below only react to a genuine
    // play/pause transition, not to every tick.
    final wasPlaying = _isPlaying;
    final hadStartedPlayback = _hasStartedPlayback;

    // While a comskip auto-skip seek is in flight, ignore orchestrator
    // position reports that would regress _currentPosition backward into
    // the segment (orchestrator onState can lag/oscillate during the real
    // seek's buffering). Accept state.position only once it's at or past
    // the pending target — that proves the real seek genuinely caught up.
    final pendingTarget = _skips.pendingComskipSeekTarget;
    final catchup = _catchup;
    final Duration acceptedPosition;
    if (catchup != null) {
      if (!_catchupReopenPending) _catchupStreamPosition = state.position;
      acceptedPosition = _catchupReopenPending || _catchupSeekTarget != null
          ? _currentPosition
          : catchup.positionOf(state.position);
    } else {
      acceptedPosition = pendingTarget != null && state.position < pendingTarget
          ? _currentPosition
          : state.position;
    }

    setState(() {
      _status = state.status;
      _retryStatusMessage = null;
      _currentPosition = acceptedPosition;
      if (state.duration != null && state.duration! > Duration.zero) {
        // A catchup duration is the programme's, not the stream's. A stream
        // that reports one at all can seek in place.
        if (catchup == null) {
          _duration = state.duration!;
        } else {
          _catchupStreamSeekable = true;
        }
      }
      _audioTracks = state.audioTracks;
      _subtitleTracks = state.subtitleTracks;
      _selectedAudioTrackId = state.selectedAudioTrackId;
      _selectedSubtitleTrackId = state.selectedSubtitleTrackId;
      _isAudioTrackSelectionKnown = state.isAudioTrackSelectionKnown;
      _isSubtitleTrackSelectionKnown = state.isSubtitleTrackSelectionKnown;

      final aspectRatio =
          state.videoAspectRatio ?? state.source?.videoAspectRatio;
      if (aspectRatio != null) {
        _videoAspectRatio = aspectRatio;
      }

      if (state.status == PlaybackStatus.ready ||
          state.status == PlaybackStatus.playing ||
          state.status == PlaybackStatus.paused) {
        _hasStartedPlayback = true;
      }

      if (state.status == PlaybackStatus.playing ||
          state.status == PlaybackStatus.paused ||
          // ExoPlayer/AVKit only report `ready` once loaded but not playing
          // (a frame is up), unlike mpv's FILE_LOADED `ready`.
          (state.status == PlaybackStatus.ready &&
              !_isMpvBackend(state.backend))) {
        _awaitingFirstFrame = false;
      }

      if (state.status == PlaybackStatus.playing) {
        _isPlaying = true;
        _errorMessage = null;
        if (!_isLive) _startPositionTimer();
        _traktScrobbleActive = true;
        // Position ticks resend `playing` many times a second - only
        // scrobble 'start' on the actual transition into playback, not on
        // every tick, or Trakt gets flooded and starts rate-limiting.
        if (!wasPlaying) _scrobble('start');
      } else if (state.status == PlaybackStatus.paused ||
          state.status == PlaybackStatus.buffering) {
        if (state.status == PlaybackStatus.paused) {
          _isPlaying = false;
          if (_traktScrobbleActive) _scrobble('pause');
        }
        _stopPositionTimer();
      } else if (state.status == PlaybackStatus.completed &&
          // The old stream ending is the reopen itself, not the programme.
          !_catchupReopenPending) {
        _isPlaying = false;
        _stopPositionTimer();
        if (_traktScrobbleActive) {
          _traktScrobbleActive = false;
          _scrobble('stop');
        }
        if (_isLive) {
          // A live stream ended unexpectedly (channel evicted by a DVR
          // recording, provider drop, server-side stop). Hold the player
          // immediately so SOMETHING is shown, then ask the shell for the
          // reason (it fetches persisted notifications) and swap the generic
          // "Stream ended" for the real message (e.g. the DVR eviction text).
          _holdBeforeGoBack();
          unawaited(_loadLiveEndReason());
        } else {
          _goBack();
        }
      }
    });

    // If the orchestrator genuinely caught up to (or past) the pending
    // seek target, the real seek has landed — release the guard so the
    // next segment / next scrub-back can fire normally.
    if (pendingTarget != null && state.position >= pendingTarget) {
      _skips.clearPendingComskipSeek();
    }
    _skips.check();
    _checkUpNext();

    // Only re-evaluate the hide timer on an actual play/pause transition:
    // pausing cancels it (keeping the overlay up), resuming restarts the
    // countdown fresh. Ignore same-status ticks (e.g. position updates)
    // or the timer would never survive long enough to fire.
    if (_isPlaying != wasPlaying && _overlayVisible) {
      _scheduleOverlayHide();
    }

    // The controls bar just appeared - hand focus from the screen to its
    // play/pause button, unless the user already moved it (e.g. onto the
    // back button).
    if (_hasStartedPlayback && !hadStartedPlayback && _overlayVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _overlayVisible && _screenFocusNode.hasPrimaryFocus) {
          _controlsFocusNode.requestFocus();
        }
      });
    }

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

    // A stream-unavailable retry in progress (e.g. the upstream IPTV
    // provider returning a 5xx that never reaches the client as anything
    // more specific than "no format found") isn't a failure yet -- the
    // orchestrator is still retrying the same backend. Surface it as a
    // status message in place of the generic loading spinner text instead
    // of the full error screen.
    if (error.code == 'stream_unavailable_retrying') {
      setState(() {
        _retryStatusMessage = error.message;
      });
      return;
    }

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

    setState(() {
      _retryStatusMessage = null;
    });
    _setErrorMessage(error.message);
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(_progressInterval, (_) {
      if (_disposed || !mounted) return;
      _reportProgress(_currentPosition);
      if (_traktScrobbleActive) _scrobble('start');
    });
  }

  void _reportProgress(Duration position) {
    if (_isLive ||
        widget.args.type == 'catchup' ||
        widget.progressReporter == null) {
      return;
    }
    widget.progressReporter!(
      Progress(
        viewerId: widget.viewerId,
        contentType: widget.args.type == 'series'
            ? ContentType.episode
            : ContentType.vod,
        streamId: widget.args.streamId ?? 0,
        positionSeconds: position.inSeconds,
        durationSeconds: _duration.inSeconds > 0 ? _duration.inSeconds : null,
        seriesId: widget.args.seriesId,
        seasonNumber: widget.args.seasonNumber,
      ),
    );
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
    if (mounted) setState(() => _epgData = result);

    final streamId = widget.args.streamId;
    final xtreamService = widget.xtreamService;
    if (streamId == null ||
        xtreamService == null ||
        _epgFetch != null ||
        !widget.epgService.shouldFetchData(channelId)) {
      return;
    }

    final sourceGeneration = widget.epgService.markFetchStarted(<String>[
      channelId,
    ]);
    final fetch = xtreamService.getShortEpg(
      streamId,
      channelId: channelId,
      limit: 4,
    );
    _epgFetch = fetch;
    try {
      final programs = await fetch;
      widget.epgService.applySuccessfulResponse(
        <String>[channelId],
        programs,
        sourceGeneration: sourceGeneration,
      );
      // The player may have switched to a different channel while this was
      // in flight (didUpdateWidget cancels the timer but can't cancel this
      // future) — don't let a stale response overwrite the new channel's EPG.
      if (_disposed || !mounted || widget.args.epgChannelId != channelId) {
        return;
      }
      final refreshed = widget.epgService.lookup(channelId);
      if (mounted) {
        setState(() => _epgData = refreshed);
      }
    } on Object catch (_) {
      widget.epgService.markFetchFailed(
        <String>[channelId],
        sourceGeneration: sourceGeneration,
      );
      if (_disposed || !mounted) return;
    } finally {
      if (identical(_epgFetch, fetch)) {
        _epgFetch = null;
      }
    }
  }

  /// Holds the player on screen after a live stream ends so a notification
  /// toast (e.g. a DVR eviction message) stays visible, then returns.
  /// User input (back) returns immediately.
  void _holdBeforeGoBack() {
    if (_disposed || !mounted) return;
    setState(() => _liveEndHold = true);
    _liveEndHoldTimer?.cancel();
    _liveEndHoldTimer = Timer(const Duration(seconds: 15), _goBack);
  }

  /// Fetches the reason the live stream ended (via the shell, which queries
  /// persisted notifications - the push channel can be down) and swaps the
  /// generic "Stream ended" for the real message.
  Future<void> _loadLiveEndReason() async {
    String? reason;
    if (widget.onLiveStreamEnded != null) {
      reason = await widget.onLiveStreamEnded!();
    }
    if (_disposed || !mounted) return;
    setState(() => _liveEndReason = reason);
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

  // Holding a remote's skip/FF/rewind button (or the arrow keys, when the
  // overlay is hidden) fires a stream of KeyDownEvent/KeyRepeatEvent, one per
  // OS repeat tick. Seeking the orchestrator on every tick would be jumpy
  // and hammer it with redundant seeks, so this accumulates the target
  // locally - same pattern as _SeekBar._adjustScrub's dpad-focused scrubbing
  // - and only commits a single real seek once the repeats go quiet.
  static const Duration _skipStep = Duration(seconds: 10);
  static const Duration _skipCommitDebounce = Duration(milliseconds: 700);
  Duration? _skipScrubPositionValue;
  Duration? get _skipScrubPosition => _skipScrubPositionValue;
  set _skipScrubPosition(Duration? value) {
    _skipScrubPositionValue = value;
    _syncDisplayPosition();
  }

  Timer? _skipCommitTimer;

  void _adjustSkip(int direction) {
    if (!_canSeek) return;
    final current = _skipScrubPosition ?? _currentPosition;
    final next = current + (_skipStep * direction);
    _skipScrubPosition = next < Duration.zero
        ? Duration.zero
        : (next > _duration ? _duration : next);
    _skipCommitTimer?.cancel();
    _skipCommitTimer = Timer(_skipCommitDebounce, _commitSkip);
  }

  void _commitSkip() {
    _skipCommitTimer?.cancel();
    _skipCommitTimer = null;
    final pos = _skipScrubPosition;
    if (pos == null) return;
    _skipScrubPosition = null;
    _seekTo(pos);
  }

  // Mirrors _adjustSkip's debounce reasoning: holding channel up/down fires
  // repeated key events too, and each one triggers a full channel
  // switch/reload, so accepted changes are rate-limited instead of one
  // firing per repeat tick.
  static const Duration _channelChangeDebounce = Duration(milliseconds: 400);
  DateTime? _lastChannelChangeAt;

  void _handleNextChannel() {
    final now = DateTime.now();
    final last = _lastChannelChangeAt;
    if (last != null && now.difference(last) < _channelChangeDebounce) return;
    _lastChannelChangeAt = now;
    widget.onNextChannel?.call();
  }

  void _handlePreviousChannel() {
    final now = DateTime.now();
    final last = _lastChannelChangeAt;
    if (last != null && now.difference(last) < _channelChangeDebounce) return;
    _lastChannelChangeAt = now;
    widget.onPreviousChannel?.call();
  }

  void _seekTo(Duration position) {
    if (!_canSeek) return;
    // A manual seek always supersedes any in-flight comskip seek — the
    // user's deliberate new position should never be guarded by the
    // auto-skip's pending target. Without this, the orchestrator's
    // confirmation of the manual seek (which may briefly report a
    // position before the auto-skip's target during the real seek's
    // buffering) would be rejected as a stale regression and the
    // player would hold _currentPosition at the auto-skip's target
    // until the 5s safety-net timer cleared the guard.
    _skips.clearPendingComskipSeek();
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _duration ? _duration : position);
    if (_catchup != null) {
      _seekCatchup(clamped);
      return;
    }
    setState(() => _currentPosition = clamped);
    _reportProgress(clamped);
    unawaited(widget.orchestrator.seek(clamped));
  }

  // How long a catchup seek may wait for the buffer to reach its target
  // before it reopens instead, and how often it checks.
  static const Duration _catchupBufferWaitBudget = Duration(seconds: 5);
  static const Duration _catchupBufferPollInterval = Duration(
    milliseconds: 250,
  );

  /// Seeks the catchup programme to [target], holding it on screen until
  /// it's reached. Only the newest seek acts, and a seek made while a reopen
  /// is loading waits for that stream (see [_reopenCatchup]) instead of
  /// opening another one.
  void _seekCatchup(Duration target) {
    final generation = ++_catchupSeekGeneration;
    setState(() {
      _catchupSeekTarget = target;
      _currentPosition = target;
    });
    if (_catchupReopenPending) return;
    unawaited(_settleCatchupSeek(generation));
  }

  /// Seeks inside the open timeshift stream when the target is already
  /// buffered (or, when the player can't say, close and seekable), waits for
  /// the buffer when the target is just past it and it's filling fast enough
  /// to get there within [_catchupBufferWaitBudget], and otherwise reopens
  /// the programme at the target minute (see [CatchupTimeline.planSeek]).
  Future<void> _settleCatchupSeek(int generation) async {
    final waited = clock.stopwatch()..start();
    ({Duration at, Duration end})? firstSample;
    while (true) {
      final buffered = await _catchupSeekWindow();
      final catchup = _catchup;
      final target = _catchupSeekTarget;
      if (_disposed ||
          !mounted ||
          catchup == null ||
          target == null ||
          generation != _catchupSeekGeneration) {
        return;
      }
      final plan = catchup.planSeek(
        target,
        from: catchup.positionOf(_catchupStreamPosition),
        streamSeekable: _catchupStreamSeekable,
        buffered: buffered,
      );
      if (plan case CatchupBufferWait(
        :final streamPosition,
        :final bufferEnd,
      )) {
        final sample = (at: waited.elapsed, end: bufferEnd);
        firstSample ??= sample;
        if (_bufferArrivesInTime(firstSample, sample, streamPosition)) {
          await Future<void>.delayed(_catchupBufferPollInterval);
          continue;
        }
      }
      _catchupSeekTarget = null;
      _applyCatchupSeek(catchup, target, plan);
      return;
    }
  }

  void _applyCatchupSeek(
    CatchupTimeline catchup,
    Duration target,
    CatchupSeek? plan,
  ) {
    switch (plan) {
      case null:
        setState(
          () => _currentPosition = catchup.positionOf(_catchupStreamPosition),
        );
      case CatchupInStreamSeek(:final streamPosition):
        setState(() => _currentPosition = target);
        unawaited(widget.orchestrator.seek(streamPosition));
      case CatchupReopen(:final start, :final duration):
        final url = widget.xtreamService?.catchupStreamUrlAt(
          widget.args.streamUrl,
          start,
          duration,
        );
        if (url == null) return;
        unawaited(_reopenCatchup(catchup.withStreamStart(start), url));
      case CatchupBufferWait(:final reopen):
        // The buffer won't get there in time.
        _applyCatchupSeek(catchup, target, reopen);
    }
  }

  /// Whether a buffer that ended at [first] and now ends at [latest], on the
  /// stream clock, is on course to reach [target] within the wait budget.
  /// It gets half a second to show it's filling at all.
  static bool _bufferArrivesInTime(
    ({Duration at, Duration end}) first,
    ({Duration at, Duration end}) latest,
    Duration target,
  ) {
    if (latest.at >= _catchupBufferWaitBudget) return false;
    final measuredFor = latest.at - first.at;
    final filled = latest.end - first.end;
    if (filled <= Duration.zero) {
      return measuredFor < const Duration(milliseconds: 500);
    }
    final remaining = target - latest.end;
    final arrivesIn = Duration(
      microseconds:
          remaining.inMicroseconds *
          measuredFor.inMicroseconds ~/
          filled.inMicroseconds,
    );
    return latest.at + arrivesIn <= _catchupBufferWaitBudget;
  }

  /// What the active player has buffered, when it can tell quickly. Null for
  /// players that can't report it, an older native build without the call,
  /// or no answer in time.
  Future<PlaybackSeekWindow?> _catchupSeekWindow() async {
    final provider = widget.orchestrator.activeSeekWindowProvider;
    if (provider == null) return null;
    try {
      return await provider.seekWindow().timeout(
        const Duration(milliseconds: 500),
      );
    } on Object {
      return null;
    }
  }

  /// Opens the programme's stream at [url] in place of the current one.
  /// `open()` ends the current stream session first, so the proxy drops the
  /// old stream straight away. A seek made while this loads is held until
  /// the new stream has opened and then planned against it, so skipping
  /// faster than streams open doesn't open one per skip.
  Future<void> _reopenCatchup(CatchupTimeline timeline, String url) async {
    final generation = ++_catchupReopenGeneration;
    setState(() {
      _catchup = timeline;
      _catchupReopenPending = true;
      _catchupStreamPosition = Duration.zero;
      _reopenPlatformView =
          widget.orchestrator.activePlatformViewProvider ?? _reopenPlatformView;
      _currentPosition = timeline.positionOf(Duration.zero);
    });
    _startLoadingTimeout();
    await _openSource(widget.args.copyWith(streamUrl: url));
    if (_disposed || !mounted || generation != _catchupReopenGeneration) {
      return;
    }
    setState(() {
      _catchupReopenPending = false;
      _reopenPlatformView = null;
    });
    if (_catchupSeekTarget != null) {
      unawaited(_settleCatchupSeek(_catchupSeekGeneration));
    }
  }

  void _handleAudioTrackSelected(String? trackId) {
    unawaited(widget.orchestrator.setAudioTrack(trackId));
  }

  void _handleSubtitleTrackSelected(String? trackId) {
    unawaited(widget.orchestrator.setSubtitleTrack(trackId));
  }

  bool get _supportsHdrToggle =>
      widget.orchestrator.activeHdrToggleProvider != null;

  void _handleHdrEnabledChanged(bool enabled) {
    setState(() => _hdrEnabled = enabled);
    unawaited(widget.viewSettingsService?.setHdrEnabled(enabled));
    unawaited(
      widget.orchestrator.activeHdrToggleProvider?.setHdrEnabled(enabled),
    );
  }

  void _handleVolumeChanged(double volume) {
    setState(() => _volume = volume);
    unawaited(widget.viewSettingsService?.setVolume(volume));
    unawaited(widget.orchestrator.activeVolumeProvider?.setVolume(volume));
  }

  Future<void> _handlePipChannelCall(MethodCall call) async {
    if (call.method != 'pipModeChanged') return;
    final isInPip = call.arguments as bool;
    if (!mounted) return;
    setState(() => _isInPictureInPicture = isInPip);
    if (isInPip) {
      _hideOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    // Transport controls are unusable at PiP's tiny window size.
    if (_isInPictureInPicture) return;
    // No extra intro-db handling needed here - the intro-db prompt's
    // visibility is derived from `_overlayVisible`, so this setState alone re-shows the
    // prompt (without restarting its countdown) if one is still pending.
    setState(() => _overlayVisible = true);
    _scheduleOverlayHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayVisible) _focusControlsOrScreen();
    });
  }

  void _focusControlsOrScreen() {
    if (_overlayVisible && _hasStartedPlayback) {
      _controlsFocusNode.requestFocus();
    } else {
      _screenFocusNode.requestFocus();
    }
  }

  void _hideOverlay() {
    _overlayHideTimer?.cancel();
    setState(() => _overlayVisible = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_overlayVisible) _screenFocusNode.requestFocus();
    });
  }

  /// Escape hides an open OSD before it leaves desktop fullscreen.
  bool _defersFullscreenEscape() => _overlayVisible && _errorMessage == null;

  void _handleBack() {
    if (_trackDialogVisible) {
      Navigator.of(context, rootNavigator: true).maybePop();
      return;
    }
    if (_liveEndHold) {
      // User pressed back during the post-stream hold - leave immediately.
      _liveEndHoldTimer?.cancel();
      _liveEndHold = false;
      _goBack();
      return;
    }
    if (_errorMessage != null) {
      _goBack();
      return;
    }
    // Back while the up-next card is up dismisses the card first (same as its
    // Dismiss button), which also unpins the OSD.
    if (_upNextVisible) {
      _dismissUpNext();
      return;
    }
    if (_overlayVisible) {
      _hideOverlay();
    } else {
      _goBack();
    }
  }

  void _handleTrackDialogVisibilityChanged(bool visible) {
    if (mounted) setState(() => _trackDialogVisible = visible);
    if (visible) {
      _overlayHideTimer?.cancel();
    } else if (_overlayVisible) {
      _scheduleOverlayHide();
    }
    widget.onTrackDialogVisibilityChanged?.call(visible);
  }

  @override
  Widget build(BuildContext context) {
    final desktopFullscreen = DesktopFullscreenScope.maybeOf(context);
    return Scaffold(
      backgroundColor: _isNativePlaneActive && _errorMessage == null
          ? Colors.transparent
          : Colors.black,
      body: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const PlayerBackIntent(),
          LogicalKeySet(LogicalKeyboardKey.goBack): const PlayerBackIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaPlayPause):
              const PlayerPlayPauseIntent(),
          // Channel up/down and skip fwd/back are dedicated remote buttons,
          // distinct from the arrow keys dpad uses for spatial navigation,
          // so they're safe to claim regardless of overlay visibility.
          // PlayerChannelChangeAction/_seekTo no-op when not applicable (e.g. a
          // skip key during live TV, or channel keys during VOD), so no
          // _isLive/_canSeek gating is needed here.
          LogicalKeySet(LogicalKeyboardKey.channelUp):
              const PlayerChannelUpIntent(),
          LogicalKeySet(LogicalKeyboardKey.channelDown):
              const PlayerChannelDownIntent(),
          // Remotes vary on whether they send FF/rewind or dedicated skip
          // keys for VOD/series scrubbing, so both map to the same 10s seek
          // as the arrow keys below.
          LogicalKeySet(LogicalKeyboardKey.mediaFastForward):
              const PlayerSeekForwardIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaRewind):
              const PlayerSeekBackIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaSkipForward):
              const PlayerSeekForwardIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaSkipBackward):
              const PlayerSeekBackIntent(),
          // Only claim arrow keys when the overlay is hidden - when visible,
          // let dpad's root Shortcuts handle them for spatial navigation.
          if (!_overlayVisible) ...{
            LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                const PlayerSeekBackIntent(),
            LogicalKeySet(LogicalKeyboardKey.arrowRight):
                const PlayerSeekForwardIntent(),
          },
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            PlayerBackIntent: PlayerBackAction(widget.onBackKey ?? _handleBack),
            PlayerPlayPauseIntent: PlayerPlayPauseAction(_togglePlayPause),
            PlayerSeekBackIntent: PlayerSeekAction(() => _adjustSkip(-1)),
            PlayerSeekForwardIntent: PlayerSeekAction(() => _adjustSkip(1)),
            PlayerChannelUpIntent: PlayerChannelChangeAction(
              _handleNextChannel,
            ),
            PlayerChannelDownIntent: PlayerChannelChangeAction(
              _handlePreviousChannel,
            ),
          },
          child: Focus(
            focusNode: _screenFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  !_overlayVisible &&
                  _errorMessage == null) {
                // Don't intercept back/escape - let the Shortcuts above handle
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
            child: Builder(
              builder: (context) {
                // TV/tablet layouts get the fixed 104px left inset that
                // clears the sidebar rail plus a generous top margin; narrow
                // portrait phones have no sidebar to clear and a much
                // smaller viewport, so the same fixed offsets push the
                // overlay's fixed 420px width off the right edge and its
                // top edge under the status bar/notch.
                final mediaQuery = MediaQuery.of(context);
                // Judged by the shortest side (not raw width) so a phone
                // rotated into landscape -- wide but short -- is still
                // recognized as compact instead of flipping to the TV/
                // desktop layout just because it's momentarily wider than
                // 600px. The old width-only check made these overlays
                // inconsistent between portrait and landscape on the same
                // device. Shared with PlaybackControls -- see
                // [isHandheldLayout].
                final isCompact = isHandheldLayout(context);
                final edgePadding = overlayEdgePaddingFor(context);
                final fontScale = FontSizeScope.scaleOf(context);
                // Sits to the right of the back button on every platform --
                // mirroring tvOS's original placement, now applied uniformly
                // instead of a separate flat desktop constant. It used to sit
                // below the back button on handheld instead, which ate a big
                // chunk of vertical space that's especially scarce in the
                // short landscape orientation the player locks to on phones.
                // Derive the offset from the actual button geometry instead
                // of a magic constant: safe-area inset + PlaybackControls'
                // own padding (edgePadding, shared with it so the two can't
                // drift apart) + the circular back button (44px at the
                // normal display-size scale - see PlaybackControls._
                // buildHeader's icon size + padding, which this must track
                // or a larger display-size setting grows the real button
                // past this reserved space) + a gap. The desktop gap (20)
                // matches the old flat 104.0 constant at scale 1
                // (40 edgePadding + 44 button + 20 gap).
                final gap = isCompact
                    ? 12.0
                    : (HostPlatform.isTvOS ? 16.0 : 20.0);
                final overlayLeft =
                    mediaQuery.padding.left +
                    edgePadding +
                    44.0 * fontScale +
                    gap;
                // Must match PlaybackControls' own edgePadding or the
                // back button and this overlay's top edges drift apart.
                final overlayTop = mediaQuery.padding.top + edgePadding;
                // Reserve room on the right for the diagnostics panel (debug
                // builds only) so the two don't draw on top of each other --
                // on a compact/handheld screen the title overlay would
                // otherwise stretch to within a few pixels of the right
                // edge, exactly where the diagnostics panel sits.
                final diagnosticsWidth = _showPlaybackDiagnostics
                    ? (isCompact ? 200.0 : 300.0) * fontScale
                    : 0.0;
                // Same for the header clock (and "Ends at" under it) that
                // PlaybackControls shows in that corner; the diagnostics
                // panel sits below it in the same right-hand column.
                final clockWidth = 112.0 * fontScale;
                final rightColumnWidth = diagnosticsWidth > 0
                    ? math.max(diagnosticsWidth + 12, clockWidth)
                    : clockWidth;
                final desktopMaxWidth =
                    mediaQuery.size.width -
                    overlayLeft -
                    (mediaQuery.padding.right + edgePadding) -
                    rightColumnWidth;
                final overlayWidth = isCompact
                    ? desktopMaxWidth
                    : (420.0 * fontScale < desktopMaxWidth
                          ? 420.0 * fontScale
                          : desktopMaxWidth);
                final skipPrompt = _buildSkipPrompt(context);
                final upNextPrompt = (_upNextVisible && _nextEpisode != null)
                    ? UpNextOverlay(
                        eyebrowLabel: AppLocalizations.of(context).playerUpNext,
                        title: _nextEpisode!.title,
                        subtitle:
                            AppLocalizations.of(
                              context,
                            ).playerNowPlayingSeasonEpisode(
                              _nextEpisode!.seasonNumber,
                              _nextEpisode!.episodeNumber,
                            ),
                        plot: _nextEpisode!.plot,
                        thumbnailUrl: _nextEpisode!.thumbnailUrl,
                        playLabel: AppLocalizations.of(
                          context,
                        ).playerUpNextPlay,
                        dismissLabel: AppLocalizations.of(
                          context,
                        ).playerUpNextDismiss,
                        playFocusNode: _upNextFocusNode,
                        onPlay: _playNextEpisode,
                        onDismiss: _dismissUpNext,
                      )
                    : null;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: _videoSurfaceReady
                          ? NativeVideoSurface(
                              surfaceKey: widget.surfaceKey,
                              textureId: widget.orchestrator.activeTextureId,
                              platformView:
                                  widget
                                      .orchestrator
                                      .activePlatformViewProvider ??
                                  _reopenPlatformView,
                              htmlView:
                                  widget.orchestrator.activeHtmlViewProvider,
                              nativePlane:
                                  widget.orchestrator.activeNativePlaneProvider,
                              aspectRatio: _videoAspectRatio,
                            )
                          : const ColoredBox(color: Colors.black),
                    ),

                    // Poster backdrop behind the loading indicator (VOD/series).
                    // Skipped on Android: `NativeVideoSurface` is already
                    // mounted as a live Hybrid Composition `AndroidView` by
                    // this point (`_videoSurfaceReady` flips true before
                    // `_openSource` runs), and covering one with an opaque
                    // Flutter overlay and later removing it does not
                    // reliably restore its visibility - confirmed on a real
                    // Pixel 7 during the EAC3 fallback work. Android gets the
                    // same backdrop natively instead - a poster `ImageView`
                    // living in the *same* native view as the `SurfaceView`
                    // (see `PosterLoader.kt`/`Media3PlatformView.kt`/
                    // `MpvPlayerPlatformView.kt`), which composites safely
                    // where a Flutter-side overlay can't. Desktop/iOS/web
                    // render through a `Texture`/html view, which doesn't
                    // have this failure mode and so keeps this Flutter path.
                    if (_showLoadingOverlay &&
                        _loadingBackdropUrl != null &&
                        !HostPlatform.isAndroid)
                      Positioned.fill(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedBackdropImage(_loadingBackdropUrl!),
                            const ColoredBox(color: Colors.black54),
                          ],
                        ),
                      ),

                    // Loading indicator
                    if (_showLoadingOverlay)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.args.logoUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: Container(
                                  padding: EdgeInsets.all(12 * fontScale),
                                  decoration: BoxDecoration(
                                    color: Colors.black38,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ResilientMediaImage(
                                    imageUrl: widget.args.logoUrl,
                                    fallbackIcon: Icons.tv,
                                    width: 96 * fontScale,
                                    height: 96 * fontScale,
                                    fit: BoxFit.contain,
                                    oversample: 2,
                                    backgroundColor: Colors.transparent,
                                  ),
                                ),
                              ),
                            Text(
                              widget.args.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _retryStatusMessage ??
                                  AppLocalizations.of(
                                    context,
                                  ).playerLoadingStream,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                    // Error display
                    if (_liveEndHold)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _liveEndReason ??
                                    AppLocalizations.of(
                                      context,
                                    ).playerLiveStreamEnded,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                AppLocalizations.of(
                                  context,
                                ).playerReturningToMenu,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_errorMessage != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                AppLocalizations.of(context).playerErrorTitle,
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
                              AppButton(
                                focusNode: _errorButtonFocusNode,
                                autofocus: true,
                                icon: Icons.arrow_back,
                                label: AppLocalizations.of(
                                  context,
                                ).playerGoBack,
                                variant: AppButtonVariant.primary,
                                onPressed: _goBack,
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Playback controls overlay
                    if (_overlayVisible && _errorMessage == null)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _hideOverlay,
                          child: PlaybackControls(
                            isPlaying: _isPlaying,
                            isLive: _isLive,
                            canSeek: _canSeek,
                            seekUnavailableMessage:
                                !_isLive &&
                                    _duration > Duration.zero &&
                                    _seekBlockedByTranscode
                                ? AppLocalizations.of(
                                    context,
                                  ).playerSeekUnavailableTranscoding
                                : null,
                            currentPosition:
                                _skipScrubPosition ?? _currentPosition,
                            positionListenable: _displayPosition,
                            duration: _duration,
                            onPlayPause: _togglePlayPause,
                            onSeek: _seekTo,
                            onBack: _goBack,
                            audioTracks: _audioTracks,
                            subtitleTracks: _subtitleTracks,
                            selectedAudioTrackId: _selectedAudioTrackId,
                            selectedSubtitleTrackId: _selectedSubtitleTrackId,
                            isAudioTrackSelectionKnown:
                                _isAudioTrackSelectionKnown,
                            isSubtitleTrackSelectionKnown:
                                _isSubtitleTrackSelectionKnown,
                            onAudioTrackSelected: _handleAudioTrackSelected,
                            onSubtitleTrackSelected:
                                _handleSubtitleTrackSelected,
                            supportsHdrToggle: _supportsHdrToggle,
                            hdrEnabled: _hdrEnabled,
                            onHdrEnabledChanged: _handleHdrEnabledChanged,
                            volume: _volume,
                            onVolumeChanged: _isDesktop
                                ? _handleVolumeChanged
                                : null,
                            isFullscreen:
                                desktopFullscreen?.isFullscreen ?? false,
                            onToggleFullscreen: desktopFullscreen == null
                                ? null
                                : () => unawaited(desktopFullscreen.toggle()),
                            onTrackDialogVisibilityChanged:
                                _handleTrackDialogVisibilityChanged,
                            fallbackReason: _showPlaybackDiagnostics
                                ? _fallbackReason
                                : null,
                            playPauseFocusNode: _controlsFocusNode,
                            onNextChannel: widget.onNextChannel,
                            onPreviousChannel: widget.onPreviousChannel,
                            onEpisodePicker:
                                _seriesInfo != null &&
                                    pickableSeasons(_seriesInfo!).isNotEmpty
                                ? _showEpisodePicker
                                : null,
                            onRecordNow:
                                (_isLive &&
                                    widget.onRecordProgram != null &&
                                    _epgData?.current != null)
                                ? () async {
                                    setState(() => _dvrSchedulePending = true);
                                    try {
                                      await widget.onRecordProgram!(
                                        _epgData!.current,
                                      );
                                    } finally {
                                      // Keep the overlay pinned for a moment
                                      // so the user can see the stop icon
                                      // appear (success) or the error SnackBar
                                      // (failure) before the bar hides.
                                      await Future<void>.delayed(
                                        const Duration(seconds: 1),
                                      );
                                      if (mounted) {
                                        setState(
                                          () => _dvrSchedulePending = false,
                                        );
                                        _scheduleOverlayHide();
                                      }
                                    }
                                  }
                                : null,
                            isRecording: widget.isRecordingCurrentChannel,
                            skipPrompt: skipPrompt,
                            upNextPrompt: upNextPrompt,
                            showControlsBar: _hasStartedPlayback,
                            // The EPG's programme end; the stream itself has
                            // no length while live.
                            liveProgrammeEnd: _isLive
                                ? _epgData?.current.end.toLocal()
                                : null,
                          ),
                        ),
                      ),

                    if (_showPlaybackDiagnostics &&
                        _overlayVisible &&
                        _errorMessage == null)
                      Positioned(
                        // Below the header row (back button height + gap),
                        // so the clock and "Ends at" above it stay visible.
                        top: overlayTop + 44.0 * fontScale + 12,
                        right: mediaQuery.padding.right + edgePadding,
                        child: PlaybackDiagnosticsPanel(
                          compact: isCompact,
                          width: diagnosticsWidth,
                          fontScale: fontScale,
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
                        top: overlayTop,
                        left: overlayLeft,
                        width: overlayWidth,
                        child: GestureDetector(
                          onTap: _hideOverlay,
                          child: EpgOverlay(
                            currentTitle: _epgData!.current.displayTitle,
                            currentProgress: _epgData!.progress,
                            nextTitle: _epgData?.next?.displayTitle,
                            channelName: widget.args.title,
                            logoUrl: widget.args.logoUrl,
                          ),
                        ),
                      ),

                    // "Now playing" overlay (VOD/series, including AIOStreams
                    // on-demand content, which reuses the same 'vod'/'series'
                    // types once resolved to a stream URL).
                    if (!_isLive && _overlayVisible)
                      Positioned(
                        top: overlayTop,
                        left: overlayLeft,
                        width: overlayWidth,
                        child: GestureDetector(
                          onTap: _hideOverlay,
                          child: NowPlayingOverlay(
                            badgeLabel: _nowPlayingBadgeLabel(context),
                            title: _nowPlayingTitle(),
                            subtitle: _nowPlayingSubtitle(context),
                            description: _nowPlayingDescription(),
                          ),
                        ),
                      ),

                    // Comskip: brief auto-skip indicator (DVR recordings only)
                    if (_skips.showComskipSkippedBadge)
                      Positioned(
                        top: edgePadding,
                        left: edgePadding,
                        child: ComskipSkippedBadge(
                          label: AppLocalizations.of(
                            context,
                          ).playerCommercialSkipped,
                        ),
                      ),

                    // Comskip/TheIntroDB skip prompt while the OSD is
                    // hidden — e.g. TheIntroDB's initial one-time countdown,
                    // which fires the moment a segment is entered regardless
                    // of OSD state. Once the OSD is up, the very same prompt
                    // instead renders inside [PlaybackControls] (see
                    // `skipPrompt:` above) so it's reachable by D-pad
                    // alongside the back button and seek bar — a `DpadRegion`
                    // with `stop` edges otherwise can't be entered from an
                    // external sibling widget like this one. Left/bottom
                    // match `overlayEdgePadding` so it lines up with the
                    // controls' own back-button corner once the OSD appears.
                    if (!_overlayVisible && skipPrompt != null)
                      Positioned(
                        left: edgePadding,
                        bottom: edgePadding,
                        child: skipPrompt,
                      ),

                    // The "up next" card renders inside [PlaybackControls]
                    // (see `upNextPrompt:` above) - never as a bare sibling -
                    // so it sits in the same DpadRegion as the transport bar
                    // and is reachable / focusable by the remote. `_checkUpNext`
                    // force-shows the OSD so that path is always live while the
                    // card is up.
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
