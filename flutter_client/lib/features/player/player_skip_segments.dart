// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/comskip_service.dart';
import 'package:m3u_tv/services/introdb_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Which TheIntroDB segment a skip prompt refers to.
enum IntroDbSegmentKind { intro, credits }

/// How long TheIntroDB's skip prompt stays up before fading (with a
/// countdown bar showing the time remaining).
const kIntroDbPromptCountdown = Duration(seconds: 15);

/// Comskip (commercial-skip) and TheIntroDB (skip intro/credits) state for
/// one player session, split out of `PlayerScreen`. The screen owns the
/// play-head: it hands over live `position`/`duration` reads, a `seek`, and
/// `bumpPosition` for the optimistic jump past a skipped segment, then calls
/// [check] after every position update and rebuilds on [notifyListeners].
class PlayerSkipSegments extends ChangeNotifier {
  PlayerSkipSegments({
    required Duration Function() position,
    required Duration Function() duration,
    required void Function(Duration position) bumpPosition,
    required Future<void> Function(Duration position) seek,
    required ComskipService comskipService,
    required bool Function() autoSkipEnabled,
    required bool Function() introDbEnabled,
    IntroDbService? introDbService,
  }) : _position = position,
       _duration = duration,
       _bumpPosition = bumpPosition,
       _seek = seek,
       _comskipService = comskipService,
       _autoSkipEnabled = autoSkipEnabled,
       _introDbEnabled = introDbEnabled,
       _introDbService = introDbService ?? IntroDbService();

  final Duration Function() _position;
  final Duration Function() _duration;
  final void Function(Duration position) _bumpPosition;
  final Future<void> Function(Duration position) _seek;
  final ComskipService _comskipService;
  final IntroDbService _introDbService;
  final bool Function() _autoSkipEnabled;
  final bool Function() _introDbEnabled;
  bool _disposed = false;

  // Comskip (commercial-skip) state - only populated when args.metadata
  // carries an 'edl_url' (completed DVR recordings with comskip enabled).
  List<ComskipSegment> _comskipSegments = const [];
  ({double start, double end})? _activeComskipSegment;
  bool _showComskipSkippedBadge = false;
  Timer? _comskipBadgeTimer;
  // Set while an auto-skip seek is in flight so orchestrator position
  // reports that lag/oscillate behind the optimistic bump can't clobber
  // the screen's position backward into the segment. Cleared the moment the
  // orchestrator genuinely reports a position at or past the target.
  Duration? _pendingComskipSeekTarget;
  // Safety net: if the orchestrator never confirms the seek (player stuck,
  // decode failure, etc.), auto-clear after a few seconds so we don't hold
  // the position hostage indefinitely and silently break future skips.
  Timer? _pendingComskipSeekTimer;

  // TheIntroDB (skip intro/credits) state - populated when the currently
  // playing VOD/series item resolves to a tmdb_id (or, for AIOStreams, an
  // imdb-style aio_item_id) with community-submitted timestamps.
  IntroDbSegments? _introDbSegments;
  // The segment kind the play-head is currently inside, independent of
  // whether the prompt is actually on screen right now.
  IntroDbSegmentKind? _introDbMatchedKind;
  // True only during the one-time countdown window that plays the moment
  // a segment is entered. Once it elapses this goes false for good (for that
  // segment) - the prompt then only shows/hides in lockstep with the OSD via
  // [introDbPromptVisible], with no further auto-hide timer.
  bool _introDbCountdownActive = false;
  DateTime? _introDbCountdownShownAt;
  Timer? _introDbPromptTimer;
  // Segments are matched purely by current position, not remembered forever
  // - scrubbing back into an already-watched (or already-skipped) segment's
  // range re-offers its prompt. The one exception is right after the user
  // taps Skip: the orchestrator's seek is async, so the position can
  // still read as "inside the segment" for a tick or two afterward. This
  // guard excludes that one kind from matching until the seek's target
  // position is actually reached (or, as a safety net if it never confirms,
  // until this timer fires) - mirrors comskip's `_pendingComskipSeekTarget`.
  IntroDbSegmentKind? _introDbPendingSkipKind;
  int? _introDbPendingSkipEndMs;
  Timer? _introDbPendingSkipTimer;

  ({double start, double end})? get activeComskipSegment =>
      _activeComskipSegment;
  bool get showComskipSkippedBadge => _showComskipSkippedBadge;
  Duration? get pendingComskipSeekTarget => _pendingComskipSeekTarget;
  IntroDbSegments? get introDbSegments => _introDbSegments;
  IntroDbSegmentKind? get introDbMatchedKind => _introDbMatchedKind;
  bool get introDbCountdownActive => _introDbCountdownActive;
  DateTime? get introDbCountdownShownAt => _introDbCountdownShownAt;

  /// Whether the skip prompt should be on screen right now: either the
  /// one-time countdown is still running, or the OSD is up and the play-head
  /// is still inside an unskipped segment. Purely derived - bringing the OSD
  /// back up after the countdown has already elapsed re-shows the prompt
  /// without restarting the countdown, and hiding the OSD hides it again.
  bool introDbPromptVisible({required bool overlayVisible}) =>
      _introDbMatchedKind != null &&
      (_introDbCountdownActive || overlayVisible);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Drops every segment and prompt ahead of a new playback session. Leaves
  /// an in-flight comskip seek guard to its own confirm or safety timer.
  void reset() {
    _comskipBadgeTimer?.cancel();
    _introDbPromptTimer?.cancel();
    _introDbPendingSkipTimer?.cancel();
    _comskipSegments = const [];
    _activeComskipSegment = null;
    _showComskipSkippedBadge = false;
    _introDbSegments = null;
    _introDbMatchedKind = null;
    _introDbCountdownActive = false;
    _introDbCountdownShownAt = null;
    _introDbPendingSkipKind = null;
    _introDbPendingSkipEndMs = null;
  }

  /// Checks the current position against both segment lists.
  void check() {
    _checkComskip();
    _checkIntroDb();
  }

  /// Releases the comskip seek guard: the orchestrator reached its target,
  /// or a manual seek superseded it.
  void clearPendingComskipSeek() {
    _pendingComskipSeekTarget = null;
    _pendingComskipSeekTimer?.cancel();
    _pendingComskipSeekTimer = null;
  }

  // ── Comskip (commercial-skip) ──────────────────────────────────────────

  /// Fetches the comskip EDL segment list for completed DVR recordings.
  /// Fire-and-forget: an older server, a recording with comskip disabled, or
  /// any fetch failure just leaves [_comskipSegments] empty, so the rest of
  /// the player behaves exactly as if this recording had no EDL at all.
  Future<void> loadComskip(
    PlayerArgs args, {
    required XtreamService? xtreamService,
    required bool hasDvrFeature,
    required bool Function() isCurrent,
  }) async {
    final segments = await _comskipService.segmentsFor(
      edlUrl: args.metadata['edl_url'] as String?,
      type: args.type,
      streamId: args.streamId,
      seriesId: args.seriesId,
      xtreamService: xtreamService,
      canLookUp: hasDvrFeature,
    );
    if (segments.isEmpty || _disposed || !isCurrent()) return;
    _comskipSegments = segments;
    _notify();
  }

  /// Checks whether the current playback position has entered a commercial
  /// segment and reacts per the user's auto-skip/prompt preference. Called
  /// after every position update, mirroring the web player's
  /// timeupdate-driven `_checkComskip`.
  void _checkComskip() {
    if (_comskipSegments.isEmpty || _disposed) return;

    final positionSeconds = _position().inMilliseconds / 1000.0;
    ({double start, double end})? current;
    for (final segment in _comskipSegments) {
      if (positionSeconds >= segment.start && positionSeconds < segment.end) {
        current = segment;
        break;
      }
    }

    if (current == null) {
      if (_activeComskipSegment != null) {
        _activeComskipSegment = null;
        _notify();
      }
      return;
    }

    final autoSkip = _autoSkipEnabled();
    if (autoSkip) {
      _fireComskipSeek(current);
      _flashComskipSkippedBadge();
    } else if (_activeComskipSegment?.end != current.end) {
      _activeComskipSegment = current;
      _notify();
    }
  }

  /// Seeks past the end of a commercial segment using sub-second EDL
  /// precision, with the optimistic position bump and
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
    // the very next tick no longer matches it - the screen's manually
    // incremented position otherwise lags the orchestrator's true position
    // until onState confirms the seek asynchronously, which would
    // re-match and re-fire on the next tick. _pendingComskipSeekTarget
    // then prevents the screen's state handler from clobbering the bump
    // backward (the orchestrator's mid-seek position reports can
    // lag/oscillate behind the optimistic value, which previously caused a
    // re-fire loop). There's deliberately no persistent already-skipped
    // tracking, since that would (and did) suppress a legitimate
    // re-skip on scrub-back, replay, or restart-from-0.
    _bumpPosition(seekTarget);
    _pendingComskipSeekTarget = seekTarget;
    _pendingComskipSeekTimer?.cancel();
    _pendingComskipSeekTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      // Real seek never confirmed - give up holding position hostage so
      // future comskip seeks aren't silently broken.
      _pendingComskipSeekTarget = null;
      _pendingComskipSeekTimer = null;
    });
    unawaited(_seek(seekTarget));
  }

  void _flashComskipSkippedBadge() {
    _comskipBadgeTimer?.cancel();
    _showComskipSkippedBadge = true;
    _notify();
    _comskipBadgeTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      _showComskipSkippedBadge = false;
      _notify();
    });
  }

  /// Confirms the prompt-mode skip control, jumping to the active segment's
  /// end the same way auto-skip would.
  void confirmComskipSkip() {
    final segment = _activeComskipSegment;
    if (segment == null) return;
    _fireComskipSeek(segment);
    _activeComskipSegment = null;
    _notify();
  }

  // ── TheIntroDB (skip intro/credits) ─────────────────────────────────────

  static final RegExp _imdbIdPattern = RegExp(r'^tt[0-9]{7,8}$');

  /// Fetches intro/credits timestamps for the currently playing VOD/series
  /// item. Fire-and-forget, mirroring [loadComskip]: TheIntroDB disabled in
  /// settings, no tmdb_id/imdb_id, an older/unlisted title, or any fetch
  /// failure just leaves [introDbSegments] null, so the rest of the player
  /// behaves exactly as if this title had no TheIntroDB data at all.
  Future<void> loadIntroDb(
    PlayerArgs args, {
    required bool Function() isCurrent,
  }) async {
    if (args.type != 'vod' && args.type != 'series') return;
    if (!_introDbEnabled()) return;

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
    if (_disposed || !isCurrent()) return;
    _introDbSegments = segments;
    _notify();
  }

  /// True when [positionMs] falls within [segment]'s effective range. A
  /// missing `endMs` means "end of media" (credits only), so it falls back
  /// to the known stream duration; until duration is known this can't match.
  bool _isWithinIntroDbSegment(IntroDbSegment segment, int positionMs) {
    final start = segment.startMs ?? 0;
    final end = segment.endMs ?? _duration().inMilliseconds;
    if (end <= 0) return false;
    return positionMs >= start && positionMs < end;
  }

  /// Picks whichever segment kind (intro takes priority over credits, since
  /// their windows never overlap in practice) the current position falls
  /// inside. Purely position-based - scrubbing back into a segment you've
  /// already watched through (or already tapped Skip on) re-matches it, so
  /// its prompt is offered again, not just on the way forward. The one
  /// exception is `_introDbPendingSkipKind`, a short-lived guard (see its
  /// field doc) for the moment right after tapping Skip.
  IntroDbSegmentKind? _matchingIntroDbSegment(int positionMs) {
    final segments = _introDbSegments;
    if (segments == null) return null;
    if (_introDbPendingSkipKind != IntroDbSegmentKind.intro &&
        segments.intro != null &&
        _isWithinIntroDbSegment(segments.intro!, positionMs)) {
      return IntroDbSegmentKind.intro;
    }
    if (_introDbPendingSkipKind != IntroDbSegmentKind.credits &&
        segments.credits != null &&
        _isWithinIntroDbSegment(segments.credits!, positionMs)) {
      return IntroDbSegmentKind.credits;
    }
    return null;
  }

  /// Checks the current position against the fetched intro/credits ranges.
  /// Called after every position update, mirroring `_checkComskip`. Entering
  /// a segment (from outside it, in either direction) starts its one-time
  /// countdown; OSD visibility changes alone are handled entirely by
  /// [introDbPromptVisible], not here.
  void _checkIntroDb() {
    if (_introDbSegments == null || _disposed) return;

    final positionMs = _position().inMilliseconds;
    final pendingEnd = _introDbPendingSkipEndMs;
    if (pendingEnd != null && positionMs >= pendingEnd) {
      _introDbPendingSkipTimer?.cancel();
      _introDbPendingSkipTimer = null;
      _introDbPendingSkipKind = null;
      _introDbPendingSkipEndMs = null;
    }

    final matched = _matchingIntroDbSegment(positionMs);
    if (matched == null) {
      if (_introDbMatchedKind != null) _resetIntroDbPromptState();
      return;
    }

    if (_introDbMatchedKind != matched) _startIntroDbCountdown(matched);
  }

  /// Enters a new segment kind and plays its one-time countdown. After it
  /// elapses, `_introDbCountdownActive` simply goes false - the prompt then
  /// only shows/hides in lockstep with the OSD ([introDbPromptVisible]),
  /// with no further timer and no restart on subsequent OSD toggles.
  void _startIntroDbCountdown(IntroDbSegmentKind kind) {
    _introDbPromptTimer?.cancel();
    _introDbMatchedKind = kind;
    _introDbCountdownActive = true;
    _introDbCountdownShownAt = DateTime.now();
    _notify();
    _introDbPromptTimer = Timer(kIntroDbPromptCountdown, () {
      if (_disposed) return;
      _introDbCountdownActive = false;
      _introDbCountdownShownAt = null;
      _notify();
    });
  }

  void _resetIntroDbPromptState() {
    _introDbPromptTimer?.cancel();
    _introDbPromptTimer = null;
    if (_introDbMatchedKind == null && !_introDbCountdownActive) return;
    _introDbMatchedKind = null;
    _introDbCountdownActive = false;
    _introDbCountdownShownAt = null;
    _notify();
  }

  void confirmIntroDbSkip() {
    final kind = _introDbMatchedKind;
    final segments = _introDbSegments;
    if (kind == null || segments == null) return;
    final segment = kind == IntroDbSegmentKind.intro
        ? segments.intro
        : segments.credits;
    if (segment == null) return;
    final endMs = segment.endMs ?? _duration().inMilliseconds;

    _introDbPendingSkipKind = kind;
    _introDbPendingSkipEndMs = endMs;
    _introDbPendingSkipTimer?.cancel();
    _introDbPendingSkipTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      _introDbPendingSkipKind = null;
      _introDbPendingSkipEndMs = null;
    });

    _resetIntroDbPromptState();
    unawaited(_seek(Duration(milliseconds: endMs)));
  }

  @override
  void dispose() {
    _disposed = true;
    _comskipBadgeTimer?.cancel();
    _pendingComskipSeekTimer?.cancel();
    _introDbPromptTimer?.cancel();
    _introDbPendingSkipTimer?.cancel();
    super.dispose();
  }
}
