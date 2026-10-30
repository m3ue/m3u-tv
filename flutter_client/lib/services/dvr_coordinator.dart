// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Per-episode outcome from [DvrCoordinator.scheduleDvrAirings]. One
/// entry per input episode, in input order. Per-item failures (e.g.
/// `XtreamDvrScheduleException` for the 422 concurrent recording limit case)
/// land here instead of aborting the rest of the batch.
class DvrAiringScheduleResult {
  const DvrAiringScheduleResult({
    required this.episode,
    required this.success,
    this.errorMessage,
  });

  final EpgShowEpisode episode;
  final bool success;

  /// Server-side error message when [success] is false. Null on success.
  final String? errorMessage;
}

/// Which content lists need to be re-fetched after a DVR recording finishes
/// post-processing so its upserted VOD/episode surfaces in the UI. Private
/// to this file - only the debounce/coalesce machinery in [DvrCoordinator]
/// reasons about it.
enum _DvrContentRefreshTarget { vod, series }

/// DVR state (recordings, series rules, storage, which channels are
/// recording) and the server calls that keep it current, split out of
/// `AppStateController`. Every async path re-checks the ownership closure the
/// controller hands it (`captureOwnership`), so a source, viewer or
/// notification-session switch mid-call can't write stale DVR state back.
class DvrCoordinator {
  DvrCoordinator({
    required this.xtreamService,
    required this.catalogRepository,
    required UserCredentials? Function() credentials,
    required bool Function() Function(UserCredentials credentials)
    captureOwnership,
    required bool Function() hasDvrFeature,
    required VoidCallback notifyListeners,
  }) : _credentials = credentials,
       _captureOwnership = captureOwnership,
       _hasDvrFeature = hasDvrFeature,
       _notifyListeners = notifyListeners;

  final XtreamService xtreamService;
  final CatalogRepository catalogRepository;
  final UserCredentials? Function() _credentials;
  final bool Function() Function(UserCredentials credentials) _captureOwnership;
  final bool Function() _hasDvrFeature;
  final VoidCallback _notifyListeners;
  bool _disposed = false;

  List<DvrRecording> _dvrRecordings = const <DvrRecording>[];
  DvrStorageInfo? _dvrStorageInfo;
  Set<int> _recordingChannelIds = const <int>{};
  List<DvrSeriesRule> _dvrSeriesRules = const <DvrSeriesRule>[];

  List<DvrRecording> get recordings => _dvrRecordings;
  DvrStorageInfo? get storageInfo => _dvrStorageInfo;
  Set<int> get recordingChannelIds => _recordingChannelIds;
  List<DvrSeriesRule> get seriesRules => _dvrSeriesRules;

  // Coalesce multiple DVR post-processing pushes that land in quick
  // succession (e.g. several recordings finishing back-to-back) into a
  // single re-fetch of VOD/Series. Mirrors the [_epgFetchDebounce] pattern.
  Timer? _dvrContentRefreshDebounce;

  Set<_DvrContentRefreshTarget> _dvrContentRefreshPending =
      const <_DvrContentRefreshTarget>{};
  // Guards against a second flush starting while one is already awaiting its
  // fetches. Without it, a push landing mid-flush (its debounce timer already
  // cleared by the in-flight run) would start an independent flush and
  // duplicate the network call instead of being coalesced into it - see the
  // while-loop in [_flushDvrContentRefresh].
  bool _dvrContentRefreshFlushing = false;
  static const _dvrContentRefreshDebounceDelay = Duration(milliseconds: 1500);

  /// Drops all DVR state (a source switch or sign-out). The caller notifies.
  /// [clearStorage] false keeps the last storage reading, as a same-account
  /// content refresh does.
  void reset({bool clearStorage = true}) {
    _dvrRecordings = const <DvrRecording>[];
    if (clearStorage) _dvrStorageInfo = null;
    _recordingChannelIds = const <int>{};
    _dvrSeriesRules = const <DvrSeriesRule>[];
  }

  /// Applies the recordings and rules fetched alongside a content load. The
  /// caller notifies. Keeps local DVR state if the server returned nothing
  /// (sync lag or a transient failure swallowed by the catchError on each
  /// future), mirroring the progress-list guard in the controller's
  /// `_replaceWithXtreamContent`.
  void applyFetched(
    List<DvrRecording> fetchedRecordings,
    List<DvrSeriesRule> fetchedSeriesRules,
  ) {
    final dvrRecordings = fetchedRecordings.isEmpty && _dvrRecordings.isNotEmpty
        ? _dvrRecordings
        : fetchedRecordings;
    final dvrSeriesRules =
        fetchedSeriesRules.isEmpty && _dvrSeriesRules.isNotEmpty
        ? _dvrSeriesRules
        : fetchedSeriesRules;
    _dvrRecordings = dvrRecordings;
    _recordingChannelIds = _extractRecordingChannelIds(dvrRecordings);
    _dvrSeriesRules = dvrSeriesRules;
  }

  void onStatusPush(
    DvrRecording recording,
    UserCredentials credentials,
    bool Function() ownsWork,
  ) {
    if (!ownsWork()) return;
    final channelId = recording.channelId;
    if (channelId != null) {
      final updated = Set<int>.of(_recordingChannelIds);
      if (recording.isInProgress) {
        updated.add(channelId);
      } else {
        updated.remove(channelId);
      }
      if (!setEquals(_recordingChannelIds, updated)) {
        if (!ownsWork()) return;
        _recordingChannelIds = updated;
        if (!ownsWork()) return;
        _notifyListeners();
      }
    }

    if (recording.status == DvrRecordingStatus.deleted) {
      // The server is the source of truth: a deleted recording has no
      // get_dvr_recording row left to fetch, so drop it locally instead of
      // refreshing its detail.
      final next = _dvrRecordings
          .where((r) => r.uuid != recording.uuid)
          .toList(growable: false);
      if (next.length != _dvrRecordings.length) {
        if (!ownsWork()) return;
        _dvrRecordings = next;
        if (!ownsWork()) return;
        _notifyListeners();
      }
      return;
    }

    // The push payload is a lightweight status ping (no stream_url/live_url -
    // those need this viewer's Xtream credentials to build). Fetch the full
    // record so the DVR Recordings screen updates its status label and gets
    // a playable URL as soon as a recording starts, not just on next reload.
    //
    // Toasts for user-facing transitions (started/completed/failed/cancelled)
    // are no longer sent from here - the server dispatches a persisted
    // TvNotification on the 'dvr' channel at those points instead, which
    // arrives through the same _onPushNotification path as every other
    // notification (unread badge, history, subscription filter all for free).
    if (!ownsWork()) return;
    unawaited(
      _refreshDvrRecordingDetail(
        recording.uuid,
        credentials,
        ownsWork,
      ),
    );
  }

  Future<void> _refreshDvrRecordingDetail(
    String uuid,
    UserCredentials credentials,
    bool Function() ownsWork,
  ) async {
    if (!ownsWork()) return;
    try {
      final detail = await xtreamService.getDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
      final next = [..._dvrRecordings];
      final index = next.indexWhere((r) => r.uuid == uuid);
      if (index >= 0) {
        next[index] = detail;
      } else {
        next.insert(0, detail);
      }
      if (!ownsWork()) return;
      _dvrRecordings = next;
      if (!ownsWork()) return;
      _notifyListeners();

      // When a recording lands in `completed` or `postProcessing`, the server
      // has just upserted it as a VOD movie or series episode. Re-fetch the
      // affected list(s) so the new item appears in Movies / Series / Home
      // without requiring a full reconnect - fixes #179.
      if (detail.status == DvrRecordingStatus.completed ||
          detail.status == DvrRecordingStatus.postProcessing) {
        _scheduleDvrContentRefresh(_classifyContentTargets(detail), ownsWork);
      }
    } on Object catch (error) {
      debugPrint('DVR: refresh recording detail after push failed: $error');
    }
  }

  /// Decide which content lists to refresh for a finished recording. A
  /// recording with both a season and episode number is unambiguously a
  /// series episode; everything else (movies, one-offs, or server payloads
  /// that omit season/episode metadata) falls back to refreshing both lists
  /// - the issue permits over-refresh, never under-refresh.
  Set<_DvrContentRefreshTarget> _classifyContentTargets(
    DvrRecording recording,
  ) {
    if (recording.seasonNumber != null && recording.episodeNumber != null) {
      return const <_DvrContentRefreshTarget>{_DvrContentRefreshTarget.series};
    }
    return const <_DvrContentRefreshTarget>{
      _DvrContentRefreshTarget.vod,
      _DvrContentRefreshTarget.series,
    };
  }

  void _scheduleDvrContentRefresh(
    Set<_DvrContentRefreshTarget> targets,
    bool Function() ownsWork,
  ) {
    if (targets.isEmpty) return;
    _dvrContentRefreshPending = <_DvrContentRefreshTarget>{
      ..._dvrContentRefreshPending,
      ...targets,
    };
    _dvrContentRefreshDebounce?.cancel();
    _dvrContentRefreshDebounce = Timer(
      _dvrContentRefreshDebounceDelay,
      () => _flushDvrContentRefresh(ownsWork),
    );
  }

  Future<void> _flushDvrContentRefresh(bool Function() ownsWork) async {
    // A flush is already looping (see below) and will pick up whatever this
    // call just merged into `_dvrContentRefreshPending` on its next
    // iteration - starting a second, concurrent flush here would duplicate
    // the network calls the first one is already making.
    if (_dvrContentRefreshFlushing) return;
    _dvrContentRefreshFlushing = true;
    try {
      // Loop rather than flushing once: a push that lands while this flush is
      // awaiting its fetches merges into `_dvrContentRefreshPending` with no
      // timer to pick it up (this flush already consumed and nulled it), so
      // it must be handled before this method returns.
      while (true) {
        if (_disposed || _dvrContentRefreshPending.isEmpty) return;
        if (!ownsWork()) return;
        final targets = _dvrContentRefreshPending;
        _dvrContentRefreshPending = const <_DvrContentRefreshTarget>{};
        _dvrContentRefreshDebounce?.cancel();
        _dvrContentRefreshDebounce = null;

        final results = await Future.wait<bool>(<Future<bool>>[
          if (targets.contains(_DvrContentRefreshTarget.vod))
            _refreshContentAfterDvr<VodItem>(
              fetch: xtreamService.getVodStreams,
              kind: kCatalogKindVod,
              ownsWork: ownsWork,
              label: 'VOD',
            ),
          if (targets.contains(_DvrContentRefreshTarget.series))
            _refreshContentAfterDvr<Series>(
              fetch: xtreamService.getSeries,
              kind: kCatalogKindSeries,
              ownsWork: ownsWork,
              label: 'series',
            ),
        ]);
        if (_disposed || !ownsWork()) return;
        if (results.contains(true)) _notifyListeners();
      }
    } finally {
      _dvrContentRefreshFlushing = false;
    }
  }

  /// Writes straight to the SQLite catalog (unlike the whole-bundle guarded
  /// replace in `_sourceReplacementQueue`, this is a single-kind partial
  /// write) so a post-DVR content refresh actually reaches the windowed
  /// grids. [ownsWork] is re-checked immediately before and after the write
  /// to keep the stale-ownership window as narrow as possible, though unlike
  /// the in-memory field this replaced, the write itself is not atomic with
  /// that check - see the caller's history for why this was a deliberate
  /// (accepted) trade rather than an oversight.
  Future<bool> _refreshContentAfterDvr<T extends Object>({
    required Future<List<T>> Function() fetch,
    required String kind,
    required bool Function() ownsWork,
    required String label,
  }) async {
    try {
      final next = await fetch();
      if (!ownsWork() || _disposed) return false;
      await catalogRepository.replaceItems(
        sourceKey: CatalogRepository.activeSource,
        kind: kind,
        items: next,
      );
      if (!ownsWork() || _disposed) return false;
      return true;
    } on Object catch (error) {
      debugPrint('DVR: refresh $label after post-processing failed: $error');
      return false;
    }
  }

  Future<void> refreshDvrSeriesRules() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final rules = await xtreamService.listDvrSeriesRulesFor(credentials);
      if (!ownsWork()) return;
      _dvrSeriesRules = rules;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh series rules failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    if (!ownsWork()) return;
    _notifyListeners();
  }

  /// Refreshes the cached DVR recordings list from `get_dvr_recordings`.
  ///
  /// Series rules can produce a matching `DvrRecording` synchronously (see
  /// [scheduleDvrAiring]'s doc comment for the same server-side behaviour on
  /// one-shot recordings), so the UI agent should call this after a
  /// successful `createDvrSeriesRule` / `updateDvrSeriesRule` round-trip, not
  /// just after [refreshDvrSeriesRules]. Otherwise, a newly matched recording
  /// will not show up in the Recordings tab until the next full reload.
  Future<void> refreshDvrRecordings() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return;
      final recordingChannelIds = _extractRecordingChannelIds(recordings);
      if (!ownsWork()) return;
      _dvrRecordings = recordings;
      if (!ownsWork()) return;
      _recordingChannelIds = recordingChannelIds;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh recordings failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    if (!ownsWork()) return;
    _notifyListeners();
  }

  /// Schedules a one-shot DVR recording and refreshes the local list.
  ///
  /// m3u-editor's `schedule_dvr` creates a DVR rule and (when DVR is enabled
  /// for the playlist) returns synchronously after the rule's scheduler has
  /// produced the corresponding `DvrRecording` row. We refresh the local list
  /// from `get_dvr_recordings` so the UI shows the real entry instead of a
  /// phantom row synthesised from a stale client-side response.
  ///
  /// Returns the matching recording if the refresh surfaced one for this
  /// channel + start time; otherwise null (the scheduler tick may not have
  /// produced the row yet on slower servers).
  Future<DvrRecording?> scheduleDvrAiring({
    required int channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return null;
    // Optimistically mark the channel as recording *before* the (slow)
    // network call so the red dot and stop-button appear instantly.
    final previousRecordingChannelIds = _recordingChannelIds;
    _recordingChannelIds = {..._recordingChannelIds, channelId};
    _notifyListeners();
    try {
      await xtreamService.scheduleDvrFor(
        credentials,
        channelId: channelId,
        title: title,
        startTime: startTime,
        endTime: endTime,
      );
    } on Object {
      // Roll back the optimistic channel id on failure so the dot and
      // stop-button revert immediately - the caller rethrows after this.
      _recordingChannelIds = previousRecordingChannelIds;
      _notifyListeners();
      rethrow;
    }
    if (!ownsWork()) return null;
    // Optimistically add a placeholder with 'recording' status so the stop
    // button works immediately (isInProgress must be true) - before the
    // (slow) full-list refresh completes.
    final placeholder = DvrRecording(
      uuid: 'optimistic-$channelId-${startTime.millisecondsSinceEpoch}',
      title: title,
      status: DvrRecordingStatus.recording,
      channelId: channelId,
      scheduledStart: startTime,
      scheduledEnd: endTime,
    );
    _dvrRecordings = [..._dvrRecordings, placeholder];
    _notifyListeners();
    // Now fetch the real list in the background; it will replace the
    // placeholder. Since the schedule succeeded we know the recording
    // will appear eventually - always keep the optimistic channel id so
    // the dot and stop-button stay visible until the push transitions it.
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return null;
      // If the server list doesn't include this recording yet (still
      // processing), keep the optimistic placeholder so the stop dialog
      // can find it.
      final foundInServer = recordings.any(
        (r) =>
            r.channelId == channelId &&
            r.scheduledStart != null &&
            startTime.difference(r.scheduledStart!).abs() <=
                const Duration(minutes: 1),
      );
      _dvrRecordings = foundInServer
          ? recordings
          : [...recordings, placeholder];
      _recordingChannelIds = {
        ..._extractRecordingChannelIds(_dvrRecordings),
        channelId,
      };
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return null;
      debugPrint('DVR: refresh after schedule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!ownsWork()) return null;
    _notifyListeners();
    unawaited(refreshDvrStorage());
    for (final recording in _dvrRecordings) {
      if (recording.channelId != channelId) continue;
      final start = recording.scheduledStart;
      if (start == null) continue;
      if (startTime.difference(start).abs() <= const Duration(minutes: 1)) {
        return recording;
      }
    }
    return null;
  }

  /// Schedules a batch of one-shot DVR recordings and refreshes the local
  /// list once, after the whole loop completes. The single-item
  /// [scheduleDvrAiring] does this per call (applying it per item in a
  /// batch would mean N `getDvrRecordingsFor` round-trips, N
  /// `notifyListeners()` rebuilds, and N `refreshDvrStorage()` calls).
  ///
  /// Per-item failures (e.g. `XtreamDvrScheduleException` for the 422
  /// concurrent recording limit case) are captured into each
  /// [DvrAiringScheduleResult] rather than aborting the rest of the batch.
  ///
  /// Throws [StateError] when credentials are not configured (a wholesale
  /// precondition fail, not a per-item failure). Matches [scheduleDvrAiring].
  Future<List<DvrAiringScheduleResult>> scheduleDvrAirings(
    List<EpgShowEpisode> episodes,
  ) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return const <DvrAiringScheduleResult>[];

    final results = <DvrAiringScheduleResult>[];
    for (final episode in episodes) {
      if (!ownsWork()) break;
      // Optimistically mark the channel as recording before the network
      // call so the red dot appears instantly.
      final previousRecordingChannelIds = _recordingChannelIds;
      _recordingChannelIds = {..._recordingChannelIds, episode.channelId};
      _notifyListeners();
      try {
        await xtreamService.scheduleDvrFor(
          credentials,
          channelId: episode.channelId,
          title: episode.displayTitle,
          startTime: episode.startTime,
          endTime: episode.endTime,
        );
        // Optimistically add a placeholder per successful schedule so the
        // stop button works immediately. The channel is already in
        // _recordingChannelIds from the optimistic update above.
        _dvrRecordings = [
          ..._dvrRecordings,
          DvrRecording(
            uuid:
                'optimistic-${episode.channelId}-'
                '${episode.startTime.millisecondsSinceEpoch}',
            title: episode.displayTitle,
            status: DvrRecordingStatus.recording,
            channelId: episode.channelId,
            scheduledStart: episode.startTime,
            scheduledEnd: episode.endTime,
          ),
        ];
        _notifyListeners();
        results.add(DvrAiringScheduleResult(episode: episode, success: true));
      } on XtreamDvrScheduleException catch (error) {
        // Roll back the optimistic channel id on per-item failure.
        _recordingChannelIds = previousRecordingChannelIds;
        _notifyListeners();
        results.add(
          DvrAiringScheduleResult(
            episode: episode,
            success: false,
            errorMessage: error.message,
          ),
        );
      } on Object catch (error, stackTrace) {
        debugPrint('DVR: batch schedule item failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        _recordingChannelIds = previousRecordingChannelIds;
        _notifyListeners();
        results.add(
          DvrAiringScheduleResult(
            episode: episode,
            success: false,
            errorMessage: error.toString(),
          ),
        );
      }
    }

    // Ownership was lost partway through the loop above: report the
    // untried episodes as failed instead of silently dropping them from
    // the caller's success/failure count.
    for (final episode in episodes.skip(results.length)) {
      results.add(
        DvrAiringScheduleResult(
          episode: episode,
          success: false,
          errorMessage: 'Cancelled: DVR ownership changed mid-batch',
        ),
      );
    }

    if (!ownsWork()) return results;
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return results;
      _dvrRecordings = recordings;
      _recordingChannelIds = _extractRecordingChannelIds(recordings);
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return results;
      debugPrint('DVR: refresh after batch schedule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!ownsWork()) return results;
    _notifyListeners();
    unawaited(refreshDvrStorage());
    return results;
  }

  static Set<int> _extractRecordingChannelIds(List<DvrRecording> recordings) {
    return recordings
        .where((recording) => recording.isInProgress)
        .map((recording) => recording.channelId)
        .whereType<int>()
        .toSet();
  }

  /// Splices freshly-fetched `active` (status=recording) entries into
  /// `_dvrRecordings` by uuid - inserting one this list doesn't know about
  /// yet, replacing one whose locally-known status disagrees with the
  /// server's. Returns null when every entry already matches, so a caller
  /// that finds nothing new doesn't force a `dvrRecordingsProvider` rebuild.
  ///
  /// This exists because [onStatusPush] is the only other writer of
  /// `_dvrRecordings`, and it only runs for pushes actually received. A
  /// `Scheduled -> Recording` push missed while disconnected previously left
  /// `_dvrRecordings` stuck on `Scheduled` even after `_recordingChannelIds`
  /// self-healed via this same function - the DVR Recordings screen and EPG
  /// recording badges (#185) are both backed by `_dvrRecordings`, not
  /// `_recordingChannelIds`.
  List<DvrRecording>? _mergeActiveDvrRecordings(List<DvrRecording> active) {
    List<DvrRecording>? next;
    for (final recording in active) {
      final source = next ?? _dvrRecordings;
      final index = source.indexWhere((r) => r.uuid == recording.uuid);
      if (index >= 0) {
        if (source[index].status == recording.status) continue;
        next ??= [..._dvrRecordings];
        next[index] = recording;
      } else {
        next ??= [..._dvrRecordings];
        next.insert(0, recording);
      }
    }
    return next;
  }

  /// Cancels a scheduled or in-progress DVR recording, keeping it in the
  /// local list with its refreshed (Cancelled) status - the server itself
  /// only marks the row cancelled and keeps history; deleting it is a
  /// separate, explicit action (see [deleteDvrRecording]). If the post-cancel
  /// detail fetch 404s (the row is already gone server-side for some other
  /// reason), drops it locally instead of leaving a stale pre-cancel row.
  Future<void> cancelDvrRecording(String uuid) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    try {
      await xtreamService.cancelDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: cancel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    try {
      final detail = await xtreamService.getDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
      final next = [..._dvrRecordings];
      final index = next.indexWhere((recording) => recording.uuid == uuid);
      if (index >= 0) {
        next[index] = detail;
      } else {
        next.insert(0, detail);
      }
      _dvrRecordings = next;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh recording detail after cancel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _dvrRecordings = _dvrRecordings
          .where((recording) => recording.uuid != uuid)
          .toList(growable: false);
    }
    if (!ownsWork()) return;
    _recordingChannelIds = _extractRecordingChannelIds(_dvrRecordings);
    if (!ownsWork()) return;
    _notifyListeners();
  }

  /// Deletes a completed/failed/cancelled DVR recording and removes it from
  /// the local list. Same fail-safe: 404 still drops the row locally.
  Future<void> deleteDvrRecording(String uuid) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    try {
      await xtreamService.deleteDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: delete failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    _dvrRecordings = _dvrRecordings
        .where((recording) => recording.uuid != uuid)
        .toList(growable: false);
    _recordingChannelIds = _extractRecordingChannelIds(_dvrRecordings);
    if (!ownsWork()) return;
    _notifyListeners();
    unawaited(refreshDvrStorage());
  }

  /// One-shot reconciliation of which channels are currently recording,
  /// fetched from the server's authoritative `status=recording`/`scheduled`
  /// lists. DVR status otherwise arrives entirely via WebSocket push (see
  /// [onStatusPush]) - there is no background poll - so callers invoke
  /// this on-demand at the points a push might plausibly have been missed:
  /// opening the DVR tab (`AppShell.didUpdateWidget`) and an unexpected live
  /// stream end (`AppShell._handleLiveStreamEnded`), on top of the
  /// WebSocket's own reconnect-time reconciliation (`onConnected` in
  /// the controller's `_connectTvNotifications`).
  Future<void> refreshActiveDvrRecordings() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsWork = _captureOwnership(credentials);
    await refreshActiveWith(credentials, ownsWork);
  }

  Future<void> refreshActiveWith(
    UserCredentials credentials,
    bool Function() ownsWork,
  ) async {
    if (!ownsWork() || !_hasDvrFeature()) return;
    try {
      final active = await xtreamService.getDvrRecordingsFor(
        credentials,
        status: DvrRecordingStatus.recording,
        limit: 200,
      );
      if (!ownsWork()) return;

      // Fetch the server's scheduled list too. Reconcile against BOTH -
      // otherwise a recording that FAILED while its local row still said
      // "scheduled" keeps its red dot forever (the active-only poll never
      // learns the row is gone).
      final scheduled = await xtreamService.getDvrRecordingsFor(
        credentials,
        status: DvrRecordingStatus.scheduled,
        limit: 200,
      );
      if (!ownsWork()) return;

      // _recordingChannelIds drives the "currently recording" indicator, so
      // it must stay limited to in-progress channels -- a channel with only
      // a future scheduled recording is not currently recording.
      final ids = _extractRecordingChannelIds(active);
      final idsChanged = !setEquals(_recordingChannelIds, ids);
      // Active entries are authoritative for the same uuid (a recording that
      // started must not be downgraded back to Scheduled by the stale
      // scheduled-side row), so the merge processes scheduled first and
      // lets the active list win for overlapping uuids.
      final merged = _mergeActiveDvrRecordings([...scheduled, ...active]);

      if (!idsChanged && merged == null) return;
      if (!ownsWork()) return;
      if (idsChanged) _recordingChannelIds = ids;
      if (merged != null) _dvrRecordings = merged;
      if (!ownsWork()) return;
      _notifyListeners();
    } on Object catch (error) {
      debugPrint('DVR: refresh active recordings failed: $error');
    }
  }

  /// Refreshes DVR storage usage against quota via `get_dvr_storage`.
  /// Older m3u-editor servers without this action fail the request, which
  /// we treat as "unsupported" - the storage display just stays hidden
  /// rather than surfacing an error.
  Future<void> refreshDvrStorage() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork() || !_hasDvrFeature()) return;
    try {
      final storageInfo = await xtreamService.getDvrStorageFor(credentials);
      if (!ownsWork()) return;
      _dvrStorageInfo = storageInfo;
    } on Object catch (error) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh storage failed: $error');
      if (!ownsWork()) return;
      _dvrStorageInfo = null;
    }
    if (!ownsWork()) return;
    _notifyListeners();
  }

  void dispose() {
    _disposed = true;
    _dvrContentRefreshDebounce?.cancel();
  }
}
