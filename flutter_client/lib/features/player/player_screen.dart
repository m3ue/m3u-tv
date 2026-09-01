import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpStatus, Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/now_playing_overlay.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/up_next_overlay.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/introdb_service.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

const bool _showPlaybackDiagnostics = bool.fromEnvironment(
  'M3U_TV_SHOW_PLAYBACK_DIAGNOSTICS',
);

/// Which TheIntroDB segment a skip prompt refers to.
enum _IntroDbSegmentKind { intro, credits }

/// How long TheIntroDB's skip prompt stays up before fading (with a
/// countdown bar showing the time remaining).
const _kIntroDbPromptCountdown = Duration(seconds: 15);

/// How far past the credits mark to wait before raising the "up next" card,
/// so it doesn't fight the skip-credits prompt for the screen (and focus).
const _kUpNextDelayAfterCredits = Duration(seconds: 5);

/// Full-screen player screen with playback controls, EPG overlay,
/// resume prompt, backend fallback display, and progress reporting.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.args,
    required this.orchestrator,
    required this.epgService,
    this.xtreamService,
    this.comskipSettings,
    this.hasDvrFeature = false,
    this.progressReporter,
    this.traktService,
    this.wakelockController = const PlatformWakelockController(),
    this.viewerId = '',
    this.onClose,
    this.onPlaybackFailure,
    this.onNextChannel,
    this.onPreviousChannel,
    this.onReplaceItem,
    this.onRecordProgram,
    this.onTrackDialogVisibilityChanged,
    this.isRecordingCurrentChannel = false,
    this.viewSettingsService,
    this.isHandheld = false,
    super.key,
  });

  final PlayerArgs args;
  final PlaybackOrchestrator orchestrator;
  final EpgService epgService;
  final XtreamService? xtreamService;
  final ComskipSettings? comskipSettings;
  final bool hasDvrFeature;
  final void Function(Progress progress)? progressReporter;
  final TraktService? traktService;
  final WakelockController wakelockController;
  final String viewerId;
  final ViewSettingsService? viewSettingsService;
  final VoidCallback? onClose;
  final VoidCallback? onPlaybackFailure;
  final VoidCallback? onNextChannel;
  final VoidCallback? onPreviousChannel;

  /// Swaps the currently playing item for `args` on the same player session
  /// (no route push/pop). Used by the "up next" overlay to roll straight into
  /// the next series episode. Mirrors how live TV reuses the player for
  /// channel skip - see `didUpdateWidget`.
  final void Function(PlayerArgs args)? onReplaceItem;
  final void Function(EpgProgram program)? onRecordProgram;
  final ValueChanged<bool>? onTrackDialogVisibilityChanged;
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
  Duration _currentPosition = Duration.zero;
  Duration _duration = Duration.zero;
  String? _errorMessage;
  String? _fallbackReason;
  String? _retryStatusMessage;
  bool _isPlaying = false;
  double _videoAspectRatio = 16 / 9;

  List<PlaybackTrack> _audioTracks = [];
  List<PlaybackTrack> _subtitleTracks = [];
  String? _selectedAudioTrackId;
  String? _selectedSubtitleTrackId;
  bool _isAudioTrackSelectionKnown = false;
  bool _isSubtitleTrackSelectionKnown = false;
  late bool _hdrEnabled = widget.viewSettingsService?.hdrEnabledSync ?? true;

  EpgCurrentNext? _epgData;

  // Comskip (commercial-skip) state — only populated when args.metadata
  // carries an 'edl_url' (completed DVR recordings with comskip enabled).
  List<({double start, double end})> _comskipSegments = const [];
  ({double start, double end})? _activeComskipSegment;
  bool _showComskipSkippedBadge = false;
  Timer? _comskipBadgeTimer;
  // Set while an auto-skip seek is in flight so orchestrator position
  // reports that lag/oscillate behind the optimistic bump can't clobber
  // _currentPosition backward into the segment. Cleared the moment the
  // orchestrator genuinely reports a position at or past the target.
  Duration? _pendingComskipSeekTarget;
  // Safety net: if the orchestrator never confirms the seek (player stuck,
  // decode failure, etc.), auto-clear after a few seconds so we don't hold
  // _currentPosition hostage indefinitely and silently break future skips.
  Timer? _pendingComskipSeekTimer;

  // TheIntroDB (skip intro/credits) state — populated when the currently
  // playing VOD/series item resolves to a tmdb_id (or, for AIOStreams, an
  // imdb-style aio_item_id) with community-submitted timestamps.
  final IntroDbService _introDbService = IntroDbService();
  IntroDbSegments? _introDbSegments;
  // The segment kind the play-head is currently inside, independent of
  // whether the prompt is actually on screen right now.
  _IntroDbSegmentKind? _introDbMatchedKind;
  // True only during the one-time 5s countdown window that plays the moment
  // a segment is entered. Once it elapses this goes false for good (for that
  // segment) — the prompt then only shows/hides in lockstep with the OSD via
  // `_introDbPromptVisible` below, with no further auto-hide timer.
  bool _introDbCountdownActive = false;
  DateTime? _introDbCountdownShownAt;
  Timer? _introDbPromptTimer;
  // Segments are matched purely by current position, not remembered forever
  // — scrubbing back into an already-watched (or already-skipped) segment's
  // range re-offers its prompt. The one exception is right after the user
  // taps Skip: the orchestrator's seek is async, so `_currentPosition` can
  // still read as "inside the segment" for a tick or two afterward. This
  // guard excludes that one kind from matching until the seek's target
  // position is actually reached (or, as a safety net if it never confirms,
  // until this timer fires) — mirrors comskip's `_pendingComskipSeekTarget`.
  _IntroDbSegmentKind? _introDbPendingSkipKind;
  int? _introDbPendingSkipEndMs;
  Timer? _introDbPendingSkipTimer;

  // ── Up next (series only) ──────────────────────────────────────────────
  // Populated once per episode from get_series_info: the next episode to roll
  // into, shown as a bottom-right card from the credits mark (or ~90% in when
  // TheIntroDB has no credits segment) until the user dismisses it.
  Series? _upNextSeries;
  Episode? _nextEpisode;
  bool _upNextVisible = false;
  bool _upNextDismissed = false;

  /// Focus target for the up-next card's Play button - the player moves focus
  /// here the moment the card appears so the remote lands on it, not the
  /// transport bar.
  final FocusNode _upNextFocusNode = FocusNode(debugLabel: 'playerUpNext');

  /// Whether the skip prompt should be on screen right now: either the
  /// one-time countdown is still running, or the OSD is up and the play-head
  /// is still inside an unskipped segment. Purely derived — bringing the OSD
  /// back up after the countdown has already elapsed re-shows the prompt
  /// without restarting the countdown, and hiding the OSD hides it again.
  bool get _introDbPromptVisible =>
      _introDbMatchedKind != null &&
      (_introDbCountdownActive || _overlayVisible);

  bool _overlayVisible = true;
  bool _trackDialogVisible = false;

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
  StreamSubscription<bool>? _nativePlaneSubscription;

  bool _disposed = false;
  bool _traktScrobbleActive = false;
  bool _failureReported = false;
  double _lastValidProgress = 0;

  bool get _isLive => widget.args.type == 'live';
  bool get _canSeek => !_isLive && _duration > Duration.zero;
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
    if (widget.isHandheld) {
      unawaited(
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]),
      );
    }
    // Steal focus from the content area (autofocus won't do this if another
    // widget already holds focus when the player opens via the AppShell Stack).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Overlay is visible on open - focus the play/pause button directly
        // so D-pad traversal works immediately. Falls back to _screenFocusNode
        // if somehow the overlay was already hidden.
        if (_overlayVisible) {
          _controlsFocusNode.requestFocus();
        } else {
          _screenFocusNode.requestFocus();
        }
      }
    });
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
    _openSource(widget.args);
    _startLoadingTimeout();
    _scheduleOverlayHide();
    unawaited(_initComskip(widget.args));
    unawaited(_initIntroDb(widget.args));
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
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isSamePlaybackSession(oldWidget.args, widget.args)) return;

    if (_traktScrobbleActive) _scrobbleFor(oldWidget.args, 'stop');
    _traktScrobbleActive = false;
    _failureReported = false;
    _lastValidProgress = 0;
    _stopPositionTimer();
    _progressTimer?.cancel();
    _epgTimer?.cancel();
    _epgFetch = null;
    _comskipBadgeTimer?.cancel();
    _introDbPromptTimer?.cancel();
    _introDbPendingSkipTimer?.cancel();

    setState(() {
      _status = PlaybackStatus.idle;
      _currentPosition = Duration.zero;
      _duration = Duration.zero;
      _errorMessage = null;
      _fallbackReason = null;
      _retryStatusMessage = null;
      _isPlaying = false;
      _videoAspectRatio = 16 / 9;
      _audioTracks = const <PlaybackTrack>[];
      _subtitleTracks = const <PlaybackTrack>[];
      _selectedAudioTrackId = null;
      _selectedSubtitleTrackId = null;
      _epgData = null;
      _overlayVisible = true;
      _comskipSegments = const [];
      _activeComskipSegment = null;
      _showComskipSkippedBadge = false;
      _introDbSegments = null;
      _introDbMatchedKind = null;
      _introDbCountdownActive = false;
      _introDbCountdownShownAt = null;
      _introDbPendingSkipKind = null;
      _introDbPendingSkipEndMs = null;
      _upNextVisible = false;
      _upNextDismissed = false;
      _nextEpisode = null;
      _upNextSeries = null;
    });

    _openSource(widget.args);
    _startLoadingTimeout();
    _scheduleOverlayHide();
    unawaited(_initComskip(widget.args));
    unawaited(_initIntroDb(widget.args));
    unawaited(_initUpNext(widget.args));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _overlayVisible) _controlsFocusNode.requestFocus();
    });
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
      if (_disposed || !mounted || !_isPlaying || _isLive) return;
      setState(() {
        final next = _currentPosition + const Duration(milliseconds: 500);
        _currentPosition = (_duration > Duration.zero && next > _duration)
            ? _duration
            : next;
      });
      _checkComskip();
      _checkIntroDb();
      _checkUpNext();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  // ── Comskip (commercial-skip) ──────────────────────────────────────────

  /// Fetches the comskip EDL segment list for completed DVR recordings.
  /// Fire-and-forget: an older server, a recording with comskip disabled, or
  /// any fetch failure just leaves [_comskipSegments] empty, so the rest of
  /// the player behaves exactly as if this recording had no EDL at all.
  Future<void> _initComskip(PlayerArgs args) async {
    var edlUrl = args.metadata['edl_url'] as String?;
    if (edlUrl == null || edlUrl.isEmpty) {
      if (!widget.hasDvrFeature || widget.xtreamService == null) return;
      edlUrl = await _resolveEdlUrlFromService(args);
      if (!mounted || !identical(args, widget.args)) return;
      if (edlUrl == null || edlUrl.isEmpty) return;
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(_resolveEdlUri(Uri.parse(edlUrl)));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return;
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      if (decoded is! List) return;

      final segments = decoded
          .whereType<Map<String, Object?>>()
          .map((segment) {
            final start = segment['start'];
            final end = segment['end'];
            if (start is! num || end is! num) return null;
            return (start: start.toDouble(), end: end.toDouble());
          })
          .whereType<({double start, double end})>()
          .toList(growable: false);

      if (!mounted || !identical(args, widget.args)) return;
      setState(() => _comskipSegments = segments);
    } on Object catch (error) {
      debugPrint('Comskip: failed to fetch EDL: $error');
    } finally {
      client.close();
    }
  }

  /// Lazily resolves an `edl_url` for play paths that don't carry the field
  /// on the originating `PlayerArgs` — notably Continue Watching for series
  /// episodes, which only holds a `Progress` and a `Series` summary.
  /// Gated on the `hasDvrFeature` flag to keep non-DVR accounts off the
  /// extra call (the series branch fetches the full `get_series_info`
  /// payload).
  Future<String?> _resolveEdlUrlFromService(PlayerArgs args) async {
    final service = widget.xtreamService;
    if (service == null) return null;
    try {
      if (args.type == 'vod' && args.streamId != null) {
        final info = await service.getVodInfo(args.streamId!);
        return info.edlUrl;
      }
      if (args.type == 'series' && args.seriesId != null) {
        final info = await service.getSeriesInfo(args.seriesId!);
        final episode = info.episodesBySeason.values
            .expand((eps) => eps)
            .where((e) => e.id == '${args.streamId}')
            .firstOrNull;
        return episode?.edlUrl;
      }
    } on Object catch (error) {
      debugPrint('Comskip: failed to resolve EDL: $error');
    }
    return null;
  }

  /// Rewrites a localhost/127.0.0.1 EDL host to the connected Xtream server's
  /// real scheme/host/port. The m3u-editor backend occasionally returns an
  /// edl_url pointing at its own loopback (e.g. `http://localhost/dvr/...`)
  /// instead of the public host, which makes the client hit the user's own
  /// machine. Only rewrites when the parsed host is loopback AND we have
  /// configured credentials; otherwise returns the input unchanged so the
  /// existing failure path runs untouched.
  Uri _resolveEdlUri(Uri edlUri) {
    final host = edlUri.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1') return edlUri;
    final server = widget.xtreamService?.credentials?.server;
    if (server == null) return edlUri;
    final serverUri = Uri.tryParse(server);
    if (serverUri == null) return edlUri;
    return edlUri.replace(
      scheme: serverUri.scheme,
      host: serverUri.host,
      port: serverUri.port,
    );
  }

  /// Checks whether the current playback position has entered a commercial
  /// segment and reacts per the user's auto-skip/prompt preference. Called
  /// after every position update, mirroring the web player's
  /// timeupdate-driven `_checkComskip`.
  void _checkComskip() {
    if (_comskipSegments.isEmpty || _disposed || !mounted) return;

    final positionSeconds = _currentPosition.inMilliseconds / 1000.0;
    ({double start, double end})? current;
    for (final segment in _comskipSegments) {
      if (positionSeconds >= segment.start && positionSeconds < segment.end) {
        current = segment;
        break;
      }
    }

    if (current == null) {
      if (_activeComskipSegment != null) {
        setState(() => _activeComskipSegment = null);
      }
      return;
    }

    final autoSkip = widget.comskipSettings?.autoSkipEnabled ?? false;
    if (autoSkip) {
      _fireComskipSeek(current);
      _flashComskipSkippedBadge();
    } else if (_activeComskipSegment?.end != current.end) {
      setState(() => _activeComskipSegment = current);
    }
  }

  /// Seeks past the end of a commercial segment using sub-second EDL
  /// precision, with the optimistic `_currentPosition` bump and
  /// `_pendingComskipSeekTarget` guard required to keep the seek-storm
  /// regression from coming back. Shared by the auto-skip branch above
  /// and the prompt-mode confirm button so the two paths can't drift
  /// out of sync again (which previously left the prompt flickering).
  void _fireComskipSeek(({double start, double end}) segment) {
    // ceil() past the segment's actual end so sub-second EDL precision
    // (e.g. end=2284.08) doesn't leave us inside the half-open interval
    // after rounding to whole seconds. The same value is used for the
    // optimistic bump and the real seek so they stay in lockstep.
    final seekTargetMs = (segment.end * 1000).ceil();
    final seekTarget = Duration(milliseconds: seekTargetMs);
    // Optimistically bump the local position past the segment's end so
    // the very next tick no longer matches it — the manually-incremented
    // _currentPosition otherwise lags the orchestrator's true position
    // until onState confirms the seek asynchronously, which would
    // re-match and re-fire on the next tick. _pendingComskipSeekTarget
    // then prevents `_handleState` from clobbering the bump backward
    // (the orchestrator's mid-seek position reports can lag/oscillate
    // behind the optimistic value, which previously caused a re-fire
    // loop). There's deliberately no persistent already-skipped
    // tracking, since that would (and did) suppress a legitimate
    // re-skip on scrub-back, replay, or restart-from-0.
    _currentPosition = seekTarget;
    _pendingComskipSeekTarget = seekTarget;
    _pendingComskipSeekTimer?.cancel();
    _pendingComskipSeekTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed || !mounted) return;
      // Real seek never confirmed — give up holding position hostage so
      // future comskip seeks aren't silently broken.
      _pendingComskipSeekTarget = null;
      _pendingComskipSeekTimer = null;
    });
    unawaited(widget.orchestrator.seek(seekTarget));
  }

  void _flashComskipSkippedBadge() {
    _comskipBadgeTimer?.cancel();
    setState(() => _showComskipSkippedBadge = true);
    _comskipBadgeTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed && mounted) {
        setState(() => _showComskipSkippedBadge = false);
      }
    });
  }

  /// Confirms the prompt-mode skip control, jumping to the active segment's
  /// end the same way auto-skip would.
  void _confirmComskipSkip() {
    final segment = _activeComskipSegment;
    if (segment == null) return;
    _fireComskipSeek(segment);
    setState(() => _activeComskipSegment = null);
  }

  // ── TheIntroDB (skip intro/credits) ─────────────────────────────────────

  static final RegExp _imdbIdPattern = RegExp(r'^tt[0-9]{7,8}$');

  /// Fetches intro/credits timestamps for the currently playing VOD/series
  /// item. Fire-and-forget, mirroring `_initComskip`: no tmdb_id/imdb_id, an
  /// older/unlisted title, or any fetch failure just leaves
  /// `_introDbSegments` null, so the rest of the player behaves exactly as
  /// if this title had no TheIntroDB data at all.
  Future<void> _initIntroDb(PlayerArgs args) async {
    if (args.type != 'vod' && args.type != 'series') return;

    final tmdbId = args.metadata['tmdb_id'] as int?;
    final aioItemId = args.metadata['aio_item_id'] as String?;
    final imdbId =
        tmdbId == null &&
            aioItemId != null &&
            _imdbIdPattern.hasMatch(aioItemId)
        ? aioItemId
        : null;
    if (tmdbId == null && imdbId == null) return;

    final segments = await _introDbService.getSegments(
      tmdbId: tmdbId,
      imdbId: imdbId,
      isSeries: args.type == 'series',
      season: args.seasonNumber ?? args.metadata['season_number'] as int?,
      episode: args.metadata['episode_number'] as int?,
    );
    if (!mounted || !identical(args, widget.args)) return;
    setState(() => _introDbSegments = segments);
  }

  /// True when [positionMs] falls within [segment]'s effective range. A
  /// missing `endMs` means "end of media" (credits only), so it falls back
  /// to the known stream duration; until duration is known this can't match.
  bool _isWithinIntroDbSegment(IntroDbSegment segment, int positionMs) {
    final start = segment.startMs ?? 0;
    final end = segment.endMs ?? _duration.inMilliseconds;
    if (end <= 0) return false;
    return positionMs >= start && positionMs < end;
  }

  /// Picks whichever segment kind (intro takes priority over credits, since
  /// their windows never overlap in practice) the current position falls
  /// inside. Purely position-based — scrubbing back into a segment you've
  /// already watched through (or already tapped Skip on) re-matches it, so
  /// its prompt is offered again, not just on the way forward. The one
  /// exception is `_introDbPendingSkipKind`, a short-lived guard (see its
  /// field doc) for the moment right after tapping Skip.
  _IntroDbSegmentKind? _matchingIntroDbSegment(int positionMs) {
    final segments = _introDbSegments;
    if (segments == null) return null;
    if (_introDbPendingSkipKind != _IntroDbSegmentKind.intro &&
        segments.intro != null &&
        _isWithinIntroDbSegment(segments.intro!, positionMs)) {
      return _IntroDbSegmentKind.intro;
    }
    if (_introDbPendingSkipKind != _IntroDbSegmentKind.credits &&
        segments.credits != null &&
        _isWithinIntroDbSegment(segments.credits!, positionMs)) {
      return _IntroDbSegmentKind.credits;
    }
    return null;
  }

  /// Checks the current position against the fetched intro/credits ranges.
  /// Called after every position update, mirroring `_checkComskip`. Entering
  /// a segment (from outside it, in either direction) starts its one-time
  /// countdown; `_overlayVisible` changes alone are handled entirely by the
  /// `_introDbPromptVisible` getter, not here.
  void _checkIntroDb() {
    if (_introDbSegments == null || _disposed || !mounted) return;

    final pendingEnd = _introDbPendingSkipEndMs;
    if (pendingEnd != null && _currentPosition.inMilliseconds >= pendingEnd) {
      _introDbPendingSkipTimer?.cancel();
      _introDbPendingSkipTimer = null;
      _introDbPendingSkipKind = null;
      _introDbPendingSkipEndMs = null;
    }

    final matched = _matchingIntroDbSegment(_currentPosition.inMilliseconds);
    if (matched == null) {
      if (_introDbMatchedKind != null) _resetIntroDbPromptState();
      return;
    }

    if (_introDbMatchedKind != matched) _startIntroDbCountdown(matched);
  }

  /// Enters a new segment kind and plays its one-time 15s countdown. After it
  /// elapses, `_introDbCountdownActive` simply goes false — the prompt then
  /// only shows/hides in lockstep with the OSD (`_introDbPromptVisible`),
  /// with no further timer and no restart on subsequent OSD toggles.
  void _startIntroDbCountdown(_IntroDbSegmentKind kind) {
    _introDbPromptTimer?.cancel();
    setState(() {
      _introDbMatchedKind = kind;
      _introDbCountdownActive = true;
      _introDbCountdownShownAt = DateTime.now();
    });
    _introDbPromptTimer = Timer(_kIntroDbPromptCountdown, () {
      if (_disposed || !mounted) return;
      setState(() {
        _introDbCountdownActive = false;
        _introDbCountdownShownAt = null;
      });
    });
  }

  void _resetIntroDbPromptState() {
    _introDbPromptTimer?.cancel();
    _introDbPromptTimer = null;
    if (_introDbMatchedKind == null && !_introDbCountdownActive) return;
    setState(() {
      _introDbMatchedKind = null;
      _introDbCountdownActive = false;
      _introDbCountdownShownAt = null;
    });
  }

  void _confirmIntroDbSkip() {
    final kind = _introDbMatchedKind;
    final segments = _introDbSegments;
    if (kind == null || segments == null) return;
    final segment = kind == _IntroDbSegmentKind.intro
        ? segments.intro
        : segments.credits;
    if (segment == null) return;
    final endMs = segment.endMs ?? _duration.inMilliseconds;

    _introDbPendingSkipKind = kind;
    _introDbPendingSkipEndMs = endMs;
    _introDbPendingSkipTimer?.cancel();
    _introDbPendingSkipTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed || !mounted) return;
      _introDbPendingSkipKind = null;
      _introDbPendingSkipEndMs = null;
    });

    _resetIntroDbPromptState();
    unawaited(widget.orchestrator.seek(Duration(milliseconds: endMs)));
  }

  // ── Up next (series only) ──────────────────────────────────────────────

  /// Resolves the next episode for the currently playing series episode from
  /// `get_series_info` (already cached client-side). Fire-and-forget, like
  /// `_initIntroDb`: a missing series id, a non-series item, or any fetch
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
    final creditsStartMs = _introDbSegments?.credits?.startMs;
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
      if (mounted && _overlayVisible) _controlsFocusNode.requestFocus();
    });
    _scheduleOverlayHide();
  }

  void _playNextEpisode() {
    final next = _nextEpisode;
    final seriesId = widget.args.seriesId;
    final onReplace = widget.onReplaceItem;
    if (next == null || seriesId == null || onReplace == null) return;
    // No startPosition: "up next" always begins the next episode from the
    // top, even if the viewer had previously sampled it. The in-place swap
    // path (_openPlayerDirect) doesn't consult the resume store, and that's
    // the intended behaviour here - not an oversight.
    final args = episodePlayerArgs(
      episode: next,
      seriesId: seriesId,
      seriesName:
          (widget.args.metadata['series_name'] as String?) ?? widget.args.title,
      series: _upNextSeries,
    );
    if (args != null) onReplace(args);
  }

  /// The one active skip prompt (comskip or TheIntroDB — the two never
  /// overlap since comskip is DVR-only and TheIntroDB is VOD/series-only),
  /// or null when neither is active. `context` is only needed for
  /// localized labels.
  Widget? _buildSkipPrompt(BuildContext context) {
    if (_activeComskipSegment != null) {
      return _SkipSegmentPrompt(
        label: AppLocalizations.of(context).playerSkipCommercial,
        onSkip: _confirmComskipSkip,
      );
    }
    // Once the "up next" card is up it takes over the end-of-episode moment;
    // a redundant "skip credits" button beside it just competes for focus.
    if (_introDbPromptVisible && !_upNextVisible) {
      return _SkipSegmentPrompt(
        label: _introDbMatchedKind == _IntroDbSegmentKind.intro
            ? AppLocalizations.of(context).playerSkipIntro
            : AppLocalizations.of(context).playerSkipCredits,
        onSkip: _confirmIntroDbSkip,
        countdownShownAt: _introDbCountdownActive
            ? _introDbCountdownShownAt
            : null,
        countdownDuration: _introDbCountdownActive
            ? _kIntroDbPromptCountdown
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
    if (widget.isHandheld) {
      unawaited(
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
      );
    }
    if (_traktScrobbleActive) _scrobble('stop');
    _loadingTimer?.cancel();
    _overlayHideTimer?.cancel();
    _progressTimer?.cancel();
    _positionTimer?.cancel();
    _epgTimer?.cancel();
    _comskipBadgeTimer?.cancel();
    _pendingComskipSeekTimer?.cancel();
    _introDbPromptTimer?.cancel();
    _introDbPendingSkipTimer?.cancel();
    _screenFocusNode.dispose();
    _controlsFocusNode.dispose();
    _errorButtonFocusNode.dispose();
    _upNextFocusNode.dispose();
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_nativePlaneSubscription?.cancel());
    unawaited(widget.wakelockController.disable());
    unawaited(widget.orchestrator.stop());
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

  void _openSource(PlayerArgs args) {
    unawaited(
      _openAndSeek(
        args.toPlaybackSource().copyWith(
          hdrEnabled: _hdrEnabled,
          matchDisplayRefreshRate:
              widget.viewSettingsService?.matchRefreshRateSync ?? false,
        ),
      ),
    );
  }

  Future<void> _openAndSeek(PlaybackSource source) async {
    try {
      await widget.orchestrator.open(source);
      // Native backends default to HDR on; only push an explicit call when
      // the persisted setting disagrees, so backends without the capability
      // (and the common case of it already being on) skip the round trip.
      if (!_hdrEnabled) {
        unawaited(
          widget.orchestrator.activeHdrToggleProvider?.setHdrEnabled(false),
        );
      }
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

    // While a comskip auto-skip seek is in flight, ignore orchestrator
    // position reports that would regress _currentPosition backward into
    // the segment (orchestrator onState can lag/oscillate during the real
    // seek's buffering). Accept state.position only once it's at or past
    // the pending target — that proves the real seek genuinely caught up.
    final pendingTarget = _pendingComskipSeekTarget;
    final acceptedPosition =
        pendingTarget != null && state.position < pendingTarget
        ? _currentPosition
        : state.position;

    setState(() {
      _status = state.status;
      _retryStatusMessage = null;
      _currentPosition = acceptedPosition;
      if (state.duration != null && state.duration! > Duration.zero) {
        _duration = state.duration!;
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
      } else if (state.status == PlaybackStatus.completed) {
        _isPlaying = false;
        _stopPositionTimer();
        if (_traktScrobbleActive) {
          _traktScrobbleActive = false;
          _scrobble('stop');
        }
        _goBack();
      }
    });

    // If the orchestrator genuinely caught up to (or past) the pending
    // seek target, the real seek has landed — release the guard so the
    // next segment / next scrub-back can fire normally.
    if (pendingTarget != null && state.position >= pendingTarget) {
      _pendingComskipSeekTarget = null;
      _pendingComskipSeekTimer?.cancel();
      _pendingComskipSeekTimer = null;
    }
    _checkComskip();
    _checkIntroDb();
    _checkUpNext();

    // Only re-evaluate the hide timer on an actual play/pause transition:
    // pausing cancels it (keeping the overlay up), resuming restarts the
    // countdown fresh. Ignore same-status ticks (e.g. position updates)
    // or the timer would never survive long enough to fire.
    if (_isPlaying != wasPlaying && _overlayVisible) {
      _scheduleOverlayHide();
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
    // A manual seek always supersedes any in-flight comskip seek — the
    // user's deliberate new position should never be guarded by the
    // auto-skip's pending target. Without this, the orchestrator's
    // confirmation of the manual seek (which may briefly report a
    // position before the auto-skip's target during the real seek's
    // buffering) would be rejected as a stale regression and the
    // player would hold _currentPosition at the auto-skip's target
    // until the 5s safety-net timer cleared the guard.
    _pendingComskipSeekTarget = null;
    _pendingComskipSeekTimer?.cancel();
    _pendingComskipSeekTimer = null;
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _duration ? _duration : position);
    setState(() => _currentPosition = clamped);
    _reportProgress(clamped);
    unawaited(widget.orchestrator.seek(clamped));
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

  void _showOverlay() {
    // No extra intro-db handling needed here — `_introDbPromptVisible` is
    // derived from `_overlayVisible`, so this setState alone re-shows the
    // prompt (without restarting its countdown) if one is still pending.
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
    if (_trackDialogVisible) {
      unawaited(Navigator.of(context, rootNavigator: true).maybePop());
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
    return Scaffold(
      backgroundColor: _isNativePlaneActive && _errorMessage == null
          ? Colors.transparent
          : Colors.black,
      body: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.escape): const _BackIntent(),
          LogicalKeySet(LogicalKeyboardKey.goBack): const _BackIntent(),
          LogicalKeySet(LogicalKeyboardKey.mediaPlayPause):
              const _PlayPauseIntent(),
          // Only claim arrow keys when the overlay is hidden - when visible,
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
                // Compact/handheld now sits to the right of the back
                // button, the same corner PlaybackControls itself uses --
                // mirroring tvOS's existing placement below. It used to sit
                // below the back button instead, which ate a big chunk of
                // vertical space that's especially scarce in the short
                // landscape orientation the player locks to on phones.
                // Derive the offset from the actual button geometry instead
                // of a magic constant: safe-area inset + PlaybackControls'
                // own padding (edgePadding, shared with it so the two can't
                // drift apart) + the ~44px circular back button + a gap.
                final rightOfBackButton =
                    isCompact || Platform.operatingSystem == 'tvos';
                final overlayLeft = rightOfBackButton
                    ? mediaQuery.padding.left +
                          edgePadding +
                          44.0 +
                          (isCompact ? 12.0 : 16.0)
                    : 104.0;
                // Must match PlaybackControls' own edgePadding or the
                // back button and this overlay's top edges drift apart.
                final overlayTop = mediaQuery.padding.top + edgePadding;
                // Reserve room on the right for the diagnostics panel (debug
                // builds only) so the two don't draw on top of each other --
                // on a compact/handheld screen the title overlay would
                // otherwise stretch to within a few pixels of the right
                // edge, exactly where the diagnostics panel sits.
                final diagnosticsWidth = _showPlaybackDiagnostics
                    ? (isCompact ? 200.0 : 300.0)
                    : 0.0;
                final overlayWidth = isCompact
                    ? mediaQuery.size.width -
                          overlayLeft -
                          (mediaQuery.padding.right + edgePadding) -
                          (diagnosticsWidth > 0 ? diagnosticsWidth + 12 : 0)
                    : 420.0;
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
                      child: NativeVideoSurface(
                        textureId: widget.orchestrator.activeTextureId,
                        platformView:
                            widget.orchestrator.activePlatformViewProvider,
                        nativePlane:
                            widget.orchestrator.activeNativePlaneProvider,
                        aspectRatio: _videoAspectRatio,
                      ),
                    ),

                    // Loading indicator
                    if (_status == PlaybackStatus.loading &&
                        _errorMessage == null)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _retryStatusMessage ?? 'Loading stream...',
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
                                  label: Text(
                                    AppLocalizations.of(context).playerGoBack,
                                  ),
                                ),
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
                            currentPosition: _currentPosition,
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
                            onTrackDialogVisibilityChanged:
                                _handleTrackDialogVisibilityChanged,
                            fallbackReason: _showPlaybackDiagnostics
                                ? _fallbackReason
                                : null,
                            playPauseFocusNode: _controlsFocusNode,
                            onNextChannel: widget.onNextChannel,
                            onPreviousChannel: widget.onPreviousChannel,
                            onRecordNow:
                                (_isLive &&
                                    widget.onRecordProgram != null &&
                                    _epgData?.current != null)
                                ? () =>
                                      widget.onRecordProgram!(_epgData!.current)
                                : null,
                            isRecording: widget.isRecordingCurrentChannel,
                            skipPrompt: skipPrompt,
                            upNextPrompt: upNextPrompt,
                          ),
                        ),
                      ),

                    if (_showPlaybackDiagnostics &&
                        _overlayVisible &&
                        _errorMessage == null)
                      Positioned(
                        top: overlayTop,
                        right: mediaQuery.padding.right + edgePadding,
                        child: _PlaybackDiagnosticsPanel(
                          compact: isCompact,
                          width: diagnosticsWidth,
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
                    if (_showComskipSkippedBadge)
                      Positioned(
                        top: edgePadding,
                        left: edgePadding,
                        child: _ComskipSkippedBadge(
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

class _PlaybackDiagnosticsPanel extends StatelessWidget {
  const _PlaybackDiagnosticsPanel({
    required this.activeBackend,
    required this.diagnostics,
    this.compact = false,
    this.width = 360,
  });

  final PlaybackBackend? activeBackend;
  final List<String> diagnostics;

  /// Shrinks padding/fonts/label width for phones/tablets, where the fixed
  /// 360px panel used to run off the edge of the screen in portrait and
  /// collide with the title overlay in the short landscape orientation.
  final bool compact;

  /// Caller-supplied width (see `PlayerScreen`'s `diagnosticsWidth`), so this
  /// panel and the title overlay it sits beside can agree on how much of the
  /// screen each one gets instead of overlapping.
  final double width;

  @override
  Widget build(BuildContext context) {
    final snapshot = _PlaybackDiagnosticsSnapshot.from(
      activeBackend: activeBackend,
      diagnostics: diagnostics,
    );
    final rows = <Widget>[
      _DiagnosticsRow(
        label: 'Backend',
        value: snapshot.backendLabel,
        compact: compact,
      ),
      if (snapshot.fallbackReason != null)
        _DiagnosticsRow(
          label: 'Fallback',
          value: snapshot.fallbackReason!,
          compact: compact,
        ),
      if (snapshot.codecDecision != null)
        _DiagnosticsRow(
          label: 'Codec',
          value: snapshot.codecDecision!,
          compact: compact,
        ),
      if (snapshot.transcodeSession != null)
        _DiagnosticsRow(
          label: 'Transcode',
          value: snapshot.transcodeSession!,
          compact: compact,
        ),
      if (snapshot.cleanupStatus != null)
        _DiagnosticsRow(
          label: 'Cleanup',
          value: snapshot.cleanupStatus!,
          compact: compact,
        ),
    ];

    return IgnorePointer(
      child: Container(
        width: width,
        padding: EdgeInsets.all(compact ? 8 : 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
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
  const _DiagnosticsRow({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: compact ? 72 : 118,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white60,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: compact ? 2 : 3,
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
  });

  final String backendLabel;
  final String? fallbackReason;
  final String? codecDecision;
  final String? transcodeSession;
  final String? cleanupStatus;

  static _PlaybackDiagnosticsSnapshot from({
    required PlaybackBackend? activeBackend,
    required List<String> diagnostics,
  }) {
    var backendLabel = _backendLabel(activeBackend);
    String? fallbackReason;
    String? codecDecision;
    String? transcodeSession;
    String? cleanupStatus;

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
      }
    }

    return _PlaybackDiagnosticsSnapshot(
      backendLabel: backendLabel,
      fallbackReason: fallbackReason,
      codecDecision: codecDecision,
      transcodeSession: transcodeSession,
      cleanupStatus: cleanupStatus,
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
      'appleMpvNative' => PlaybackBackend.appleMpvNative,
      'appleAvKit' => PlaybackBackend.appleAvKit,
      'desktopLibmpv' => PlaybackBackend.desktopLibmpv,
      'macMpvNative' => PlaybackBackend.macMpvNative,
      'serverTranscode' => PlaybackBackend.serverTranscode,
      _ => null,
    };
  }

  static String _backendLabel(PlaybackBackend? backend) {
    return switch (backend) {
      PlaybackBackend.androidExoPlayer => 'Android ExoPlayer',
      PlaybackBackend.androidMpv => 'Android native mpv',
      PlaybackBackend.appleMpvNative => 'Apple native mpv',
      PlaybackBackend.appleAvKit => 'Apple AVKit fallback',
      PlaybackBackend.desktopLibmpv => 'Desktop libmpv',
      PlaybackBackend.macMpvNative => 'macOS native mpv',
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

/// Brief, non-interactive indicator shown when a commercial segment was
/// auto-skipped. Self-dismisses via [_PlayerScreenState._flashComskipSkippedBadge].
class _ComskipSkippedBadge extends StatelessWidget {
  const _ComskipSkippedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fast_forward, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirm-to-skip control shown while playback is inside a commercial,
/// intro, or credits window — comskip's and TheIntroDB's prompts share this
/// one look. Renders as the app's `primaryInverted` [AppButton] (the same
/// hero-action pill used for the resume/play button on detail screens) so it
/// reads as a real UI control instead of a floating overlay chip, and always
/// autofocuses so a D-pad user can hit Select the instant it appears.
///
/// When [countdownShownAt]/[countdownDuration] are both provided (TheIntroDB
/// only — comskip's prompt has no auto-hide), a slim bar under the button
/// counts down to when the prompt will fade. Comskip passes neither and the
/// bar is simply omitted.
class _SkipSegmentPrompt extends StatelessWidget {
  const _SkipSegmentPrompt({
    required this.label,
    required this.onSkip,
    this.countdownShownAt,
    this.countdownDuration,
  });

  final String label;
  final VoidCallback onSkip;
  final DateTime? countdownShownAt;
  final Duration? countdownDuration;

  @override
  Widget build(BuildContext context) {
    final shownAt = countdownShownAt;
    final total = countdownDuration;
    Widget? footer;
    if (shownAt != null && total != null) {
      final remaining = total - DateTime.now().difference(shownAt);
      final startFraction = remaining.isNegative
          ? 0.0
          : remaining.inMilliseconds / total.inMilliseconds;
      footer = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 3,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: startFraction, end: 0),
            duration: remaining.isNegative ? Duration.zero : remaining,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Colors.black87),
            ),
          ),
        ),
      );
    }

    return AppButton(
      label: label,
      icon: Icons.fast_forward,
      variant: AppButtonVariant.primaryInverted,
      autofocus: true,
      onPressed: onSkip,
      footer: footer,
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
