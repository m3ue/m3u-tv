import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpStatus;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/now_playing_overlay.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

const bool _showPlaybackDiagnostics = bool.fromEnvironment(
  'M3U_TV_SHOW_PLAYBACK_DIAGNOSTICS',
);

/// Full-screen player screen with playback controls, EPG overlay,
/// resume prompt, backend fallback display, and progress reporting.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.args,
    required this.orchestrator,
    required this.epgService,
    this.xtreamService,
    this.comskipSettings,
    this.progressReporter,
    this.traktService,
    this.wakelockController = const PlatformWakelockController(),
    this.viewerId = '',
    this.onClose,
    this.onPlaybackFailure,
    this.onNextChannel,
    this.onPreviousChannel,
    this.onRecordProgram,
    this.onTrackDialogVisibilityChanged,
    this.isRecordingCurrentChannel = false,
    super.key,
  });

  final PlayerArgs args;
  final PlaybackOrchestrator orchestrator;
  final EpgService epgService;
  final XtreamService? xtreamService;
  final ComskipSettings? comskipSettings;
  final void Function(Progress progress)? progressReporter;
  final TraktService? traktService;
  final WakelockController wakelockController;
  final String viewerId;
  final VoidCallback? onClose;
  final VoidCallback? onPlaybackFailure;
  final VoidCallback? onNextChannel;
  final VoidCallback? onPreviousChannel;
  final void Function(EpgProgram program)? onRecordProgram;
  final ValueChanged<bool>? onTrackDialogVisibilityChanged;
  final bool isRecordingCurrentChannel;

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
  double _videoAspectRatio = 16 / 9;

  List<PlaybackTrack> _audioTracks = [];
  List<PlaybackTrack> _subtitleTracks = [];
  String? _selectedAudioTrackId;
  String? _selectedSubtitleTrackId;
  bool _isAudioTrackSelectionKnown = false;
  bool _isSubtitleTrackSelectionKnown = false;

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

  bool _disposed = false;
  bool _traktScrobbleActive = false;
  bool _failureReported = false;
  double _lastValidProgress = 0;

  bool get _isLive => widget.args.type == 'live';
  bool get _canSeek => !_isLive && _duration > Duration.zero;
  bool get _isSeries => widget.args.type == 'series';

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
    _openSource(widget.args);
    _startLoadingTimeout();
    _scheduleOverlayHide();
    unawaited(_initComskip(widget.args));
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

    setState(() {
      _status = PlaybackStatus.idle;
      _currentPosition = Duration.zero;
      _duration = Duration.zero;
      _errorMessage = null;
      _fallbackReason = null;
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
    });

    _openSource(widget.args);
    _startLoadingTimeout();
    _scheduleOverlayHide();
    unawaited(_initComskip(widget.args));
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
    final edlUrl = args.metadata['edl_url'] as String?;
    if (edlUrl == null || edlUrl.isEmpty) return;

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
    if (_traktScrobbleActive) _scrobble('stop');
    _loadingTimer?.cancel();
    _overlayHideTimer?.cancel();
    _progressTimer?.cancel();
    _positionTimer?.cancel();
    _epgTimer?.cancel();
    _comskipBadgeTimer?.cancel();
    _pendingComskipSeekTimer?.cancel();
    _screenFocusNode.dispose();
    _controlsFocusNode.dispose();
    _errorButtonFocusNode.dispose();
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
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
    unawaited(_openAndSeek(args.toPlaybackSource()));
  }

  Future<void> _openAndSeek(PlaybackSource source) async {
    try {
      await widget.orchestrator.open(source);
      if (_disposed || !mounted || source.isLive) return;
      if (source.startPosition > Duration.zero) {
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
    if (_trackDialogVisible) {
      unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      return;
    }
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
      backgroundColor: Colors.black,
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
                final isCompact = mediaQuery.size.width < 600;
                final overlayLeft = isCompact ? 16.0 : 104.0;
                // On compact/portrait layouts the back button lives in
                // PlaybackControls' own top-left corner (40px padding + a
                // ~44px circular hit target); the overlay must clear that
                // whole row instead of overlapping it.
                final overlayTop =
                    mediaQuery.padding.top + (isCompact ? 96.0 : 40.0);
                final overlayWidth = isCompact
                    ? mediaQuery.size.width - overlayLeft * 2
                    : 420.0;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: _VideoSurface(
                        textureId: widget.orchestrator.activeTextureId,
                        aspectRatio: _videoAspectRatio,
                      ),
                    ),

                    if (widget.orchestrator.activeSubtitleController != null)
                      Positioned.fill(
                        child: mkv.SubtitleView(
                          controller:
                              widget.orchestrator.activeSubtitleController!,
                          configuration: const mkv.SubtitleViewConfiguration(),
                        ),
                      ),

                    // Loading indicator
                    if (_status == PlaybackStatus.loading &&
                        _errorMessage == null)
                      const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Loading stream...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
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
                      GestureDetector(
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
                          onSubtitleTrackSelected: _handleSubtitleTrackSelected,
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
                              ? () => widget.onRecordProgram!(_epgData!.current)
                              : null,
                          isRecording: widget.isRecordingCurrentChannel,
                        ),
                      ),

                    if (_showPlaybackDiagnostics &&
                        _overlayVisible &&
                        _errorMessage == null)
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
                        top: 40,
                        left: 40,
                        child: _ComskipSkippedBadge(
                          label: AppLocalizations.of(
                            context,
                          ).playerCommercialSkipped,
                        ),
                      ),

                    // Comskip: confirm-to-skip prompt (auto-skip disabled)
                    if (_activeComskipSegment != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 140,
                        child: Center(
                          child: _ComskipSkipPrompt(
                            label: AppLocalizations.of(
                              context,
                            ).playerSkipCommercial,
                            onSkip: _confirmComskipSkip,
                            // Only steal focus when the controls overlay is
                            // hidden (nothing else is being actively
                            // navigated). If the user is mid-interaction
                            // with visible controls, let the prompt appear
                            // without yanking focus away from them.
                            autofocus: !_overlayVisible,
                          ),
                        ),
                      ),
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

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({required this.textureId, required this.aspectRatio});

  final int? textureId;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final id = textureId;
    if (id == null) return const ColoredBox(color: Colors.black);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
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
      'appleMediaKit' => PlaybackBackend.appleMediaKit,
      'appleAvKit' => PlaybackBackend.appleAvKit,
      'desktopLibmpv' => PlaybackBackend.desktopLibmpv,
      'desktopMediaKit' => PlaybackBackend.desktopMediaKit,
      'serverTranscode' => PlaybackBackend.serverTranscode,
      _ => null,
    };
  }

  static String _backendLabel(PlaybackBackend? backend) {
    return switch (backend) {
      PlaybackBackend.androidExoPlayer => 'Android ExoPlayer',
      PlaybackBackend.androidMpv => 'Android mpv/libmpv disabled',
      PlaybackBackend.appleMediaKit => 'Apple Media Kit',
      PlaybackBackend.appleAvKit => 'Apple AVKit fallback',
      PlaybackBackend.desktopLibmpv => 'Desktop libmpv',
      PlaybackBackend.desktopMediaKit => 'Desktop Media Kit',
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

/// Confirm-to-skip control shown while playback is inside a commercial
/// segment and auto-skip is disabled. Hides itself once the play-head
/// exits the segment — see [_PlayerScreenState._checkComskip].
class _ComskipSkipPrompt extends StatelessWidget {
  const _ComskipSkipPrompt({
    required this.label,
    required this.onSkip,
    required this.autofocus,
  });

  final String label;
  final VoidCallback onSkip;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onSkip,
      borderRadius: BorderRadius.circular(50),
      color: Colors.black.withValues(alpha: 0.75),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
