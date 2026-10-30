// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' hide Category;
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// The guide's network and persistence lifecycle, split out of
/// `AppStateController`: lazy per-row fetches, the startup prime and
/// background sweep, catchup-window fetches, the debounced on-disk persist
/// and the cold-start restore. [EpgService] stays the in-memory store; this
/// decides what to fetch and when.
///
/// The controller still owns the source, the channel list and the loading
/// state, and reads them back through the callbacks passed in.
class EpgCoordinator {
  EpgCoordinator({
    required this.epgService,
    required this.xtreamService,
    required this.cacheService,
    required Generation sourceOperationGeneration,
    required bool Function() isXtreamSource,
    required Future<List<Channel>> Function(int offset, int limit) channelPage,
    required Future<int> Function() channelCount,
    required bool Function() isLoadingContent,
    required VoidCallback notifyListeners,
  }) : _sourceOperationGeneration = sourceOperationGeneration,
       _isXtreamSource = isXtreamSource,
       _channelPage = channelPage,
       _channelCount = channelCount,
       _isLoadingContentOf = isLoadingContent,
       _notifyListeners = notifyListeners {
    epgService.onEvicted = _onScheduleEvicted;
  }

  final EpgService epgService;
  final XtreamService xtreamService;
  final CacheService cacheService;
  final Generation _sourceOperationGeneration;
  final bool Function() _isXtreamSource;

  /// The live lineup in provider order, read a page at a time from the
  /// catalog so the prime and sweep never hold every channel at once.
  final Future<List<Channel>> Function(int offset, int limit) _channelPage;
  final Future<int> Function() _channelCount;
  final bool Function() _isLoadingContentOf;
  final VoidCallback _notifyListeners;

  bool get _isXtream => _isXtreamSource();
  bool get _isLoadingContent => _isLoadingContentOf();
  bool _disposed = false;

  final StreamController<EpgSweepProgress?> _epgSweepProgressController =
      StreamController<EpgSweepProgress?>.broadcast();

  /// Background-sweep progress; see `AppStateController.epgSweepProgress`.
  Stream<EpgSweepProgress?> get sweepProgress =>
      _epgSweepProgressController.stream;

  final Map<int, Channel> _pendingEpgChannels = <int, Channel>{};
  final Set<int> _pendingForcedEpgChannelIds = <int>{};
  final Map<String, DateTime> _fetchedEpgRanges = <String, DateTime>{};
  final Map<int, DateTime> _catchupEpgFetchedAt = <int, DateTime>{};

  /// The EPG id of every channel with an entry in [_fetchedEpgRanges] or
  /// [_catchupEpgFetchedAt], so an eviction (which names the EPG id) can
  /// find them.
  final Map<int, String> _trackedEpgIds = <int, String>{};
  final Map<int, Completer<void>> _inFlightCatchupEpgFetches =
      <int, Completer<void>>{};
  Timer? _epgFetchDebounce;
  DateTime? _pendingEpgStartDate;
  DateTime? _pendingEpgEndDate;
  String _activeEpgRangeKey = '';
  // Deliberately separate from epgService's own source-generation counter:
  // this one invalidates in-flight per-range/channel-batch fetches (bumped
  // on every guide range navigation, not just a full source reset), while
  // epgService's tracks whether the entire EPG source has been swapped.
  // The two must both advance together in resetSession - a reset path
  // that bumps only one would let a stale fetch write into the new source.
  int _epgRequestGeneration = 0;
  // Bumped whenever a background full-guide sweep should stop (source reset,
  // dispose, or a newer sweep superseding this one). The sweep captures this
  // and bails between chunks once it no longer matches.
  int _epgSweepGeneration = 0;
  static const _epgPrimeCount = 90;
  static const _epgFetchDebounceDelay = Duration(milliseconds: 150);
  // After priming the first screen's worth of channels, the rest of the guide
  // is pulled in the background in [_epgSweepChunkSize] batches spaced by
  // [_epgSweepChunkDelay], so scrolling a large playlist hits already-loaded
  // EPG instead of waiting on a lazy fetch. [_epgSweepStartDelay] lets the
  // prime response and first frame settle before the sweep adds load.
  static const _epgSweepChunkSize = 100;
  static const _epgSweepStartDelay = Duration(seconds: 2);
  static const _epgSweepChunkDelay = Duration(milliseconds: 350);
  // When the last guide prime succeeded, so a resume can tell whether the
  // guide is older than [EpgService.cacheTtl]. Only set on success: a prime
  // that fails (waking from standby before Wi-Fi is back) must not count as
  // fresh, or every resume for the next TTL would skip the refresh.
  DateTime? _epgGuideRefreshedAt;
  int _epgPrimesInFlight = 0;
  Timer? _epgPrimeRetry;

  /// Queues [channels] for a lazy, debounced EPG fetch — only channels
  /// without fresh cached data are requested. Call this from a screen's
  /// `itemBuilder` (list/grid) so only currently visible channels get fetched
  /// as the user scrolls, instead of fetching the whole channel list upfront.
  void ensureEpgForChannels(
    List<Channel> channels, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (!_isXtream) return;
    final rangeKey = _epgRangeKey(startDate, endDate);
    final returningToCurrentGuide =
        rangeKey.isEmpty && _activeEpgRangeKey.isNotEmpty;
    if (rangeKey != _activeEpgRangeKey) {
      _activeEpgRangeKey = rangeKey;
      _pendingEpgStartDate = startDate;
      _pendingEpgEndDate = endDate;
      _pendingEpgChannels.clear();
      _pendingForcedEpgChannelIds.clear();
      _epgFetchDebounce?.cancel();
      _epgRequestGeneration += 1;
    }
    var added = false;
    for (final channel in channels) {
      if (rangeKey.isEmpty) {
        final forceRefresh =
            returningToCurrentGuide && !epgService.hasProgramsFor(channel);
        if (!forceRefresh && !epgService.shouldFetchDataForChannel(channel)) {
          continue;
        }
        if (forceRefresh) _pendingForcedEpgChannelIds.add(channel.id);
      } else {
        if (_hasFreshEpgRange(channel.id, rangeKey) ||
            !epgService.shouldFetchData(_epgRangeFetchId(channel, rangeKey))) {
          continue;
        }
      }
      if (_pendingEpgChannels.containsKey(channel.id)) continue;
      _pendingEpgChannels[channel.id] = channel;
      added = true;
    }
    if (!added) return;
    _epgFetchDebounce?.cancel();
    _epgFetchDebounce = Timer(_epgFetchDebounceDelay, _flushPendingEpgFetch);
  }

  /// Fetches the full retention window of EPG programs for [channel] so the
  /// catchup dialog can list history beyond today+tomorrow (which is all
  /// `ensureEpgForChannels` ever asks the server for).
  ///
  /// Deliberately does not read or write `_activeEpgRangeKey`,
  /// `_pendingEpg*`, or `_epgRequestGeneration`: those gate the default-guide
  /// range fetches that the list/grid itemBuilders kick off on every rebuild,
  /// which would race a dialog-open fetch and discard the response. It does
  /// re-check `_sourceOperationGeneration` after the network round-trips so a
  /// source switch mid-fetch can't merge stale programs back into a guide
  /// that `resetSession` just cleared.
  ///
  /// On success it also marks the channel fetched in [EpgService] so the
  /// itemBuilders' no-date `ensureEpgForChannels` calls stop returning true
  /// for it until [EpgService.cacheTtl] lapses. Without that, the very
  /// `notifyListeners` this merge fires would rebuild the list, trigger a
  /// default-guide fetch, and `replaceExisting` the retention window straight
  /// back out. The freshness mark and the [_catchupEpgFetchedAt] memo share
  /// the same TTL, so they lapse together: once the guide is allowed to wipe
  /// history again, the next dialog open re-fetches it.
  ///
  /// Concurrent calls for the same channel await one shared fetch, and
  /// successes are memoized against [EpgService.cacheTtl] (both the memo and
  /// the in-flight map are cleared by `resetSession`).
  Future<void> ensureCatchupEpgForChannel(Channel channel) async {
    final existing = _inFlightCatchupEpgFetches[channel.id];
    if (existing != null) {
      await existing.future;
      return;
    }
    final completer = Completer<void>();
    _inFlightCatchupEpgFetches[channel.id] = completer;
    try {
      await _fetchCatchupEpgForChannel(channel);
    } finally {
      if (identical(_inFlightCatchupEpgFetches[channel.id], completer)) {
        _inFlightCatchupEpgFetches.remove(channel.id);
      }
      completer.complete();
    }
  }

  Future<void> _fetchCatchupEpgForChannel(Channel channel) async {
    if (!_isXtream) return;
    final retentionDays = EpgService.effectiveCatchupRetentionDays(
      channel.catchupSupported,
      channel.catchupDays,
    );
    if (retentionDays <= 0) return;
    final lastSuccess = _catchupEpgFetchedAt[channel.id];
    final now = DateTime.now();
    if (lastSuccess != null &&
        now.difference(lastSuccess) < epgService.cacheTtl) {
      return;
    }
    final sourceGeneration = _sourceOperationGeneration.current;
    final today = DateTime(now.year, now.month, now.day);
    // canReplay admits programs starting as far back as now - retentionDays,
    // a timestamp on calendar day (today - retentionDays), so that partial
    // day must be fetched too; canReplay filters out its too-old programs.
    // The final day request also returns tomorrow (the server fetches
    // date + date+1), so this covers the whole default-guide window too.
    final start = DateTime.utc(
      today.year,
      today.month,
      today.day - retentionDays,
    );
    final end = DateTime.utc(today.year, today.month, today.day);
    try {
      final programs = await xtreamService.getEpgBatch(
        [channel],
        startDate: start,
        endDate: end,
        dropPlaceholders: true,
      );
      if (_disposed || _sourceOperationGeneration.isStale(sourceGeneration)) {
        return;
      }
      epgService
        ..markFetched([_epgChannelId(channel)])
        ..mergePrograms(
          programs,
          channelIds: [_epgChannelId(channel)],
          replaceExisting: false,
          markFresh: false,
        );
      _catchupEpgFetchedAt[channel.id] = DateTime.now();
      _trackedEpgIds[channel.id] = _epgChannelId(channel);
    } on Object catch (_) {
      _catchupEpgFetchedAt.remove(channel.id);
    }
  }

  Future<void> _flushPendingEpgFetch() async {
    if (_pendingEpgChannels.isEmpty) return;
    final pending = _pendingEpgChannels.values.toList(growable: false);
    _pendingEpgChannels.clear();
    final ids = {for (final channel in pending) channel.id};
    final forcedIds = _pendingForcedEpgChannelIds.intersection(ids);
    _pendingForcedEpgChannelIds.removeAll(ids);
    final startDate = _pendingEpgStartDate;
    final endDate = _pendingEpgEndDate;
    final rangeKey = _activeEpgRangeKey;
    final generation = _epgRequestGeneration;
    final channels = pending
        .where(
          (channel) => rangeKey.isEmpty
              ? forcedIds.contains(channel.id) ||
                    epgService.shouldFetchDataForChannel(channel)
              : !_hasFreshEpgRange(channel.id, rangeKey) &&
                    epgService.shouldFetchData(
                      _epgRangeFetchId(channel, rangeKey),
                    ),
        )
        .toList(growable: false);
    if (channels.isEmpty) return;
    final channelIds = channels.map(_epgChannelId).toList(growable: false);
    final fetchIds = rangeKey.isEmpty
        ? channelIds
        : channels
              .map((channel) => _epgRangeFetchId(channel, rangeKey))
              .toList(growable: false);
    final sourceGeneration = epgService.markFetchStarted(fetchIds);
    try {
      final programs = await xtreamService.getEpgBatch(
        channels,
        startDate: startDate,
        endDate: endDate,
      );
      if (generation != _epgRequestGeneration ||
          rangeKey != _activeEpgRangeKey) {
        epgService.markFetchFailed(
          fetchIds,
          sourceGeneration: sourceGeneration,
        );
        return;
      }
      if (rangeKey.isEmpty) {
        epgService.applySuccessfulResponse(
          channelIds,
          programs,
          sourceGeneration: sourceGeneration,
        );
      } else {
        _markEpgRangeFetched(channels, rangeKey);
        epgService
          ..mergePrograms(
            programs,
            channelIds: channelIds,
            replaceExisting: false,
            markFresh: false,
          )
          ..markFetched(fetchIds);
      }
      if (kDebugMode) {
        debugPrint(
          '[EPG] lazy fetch → ${programs.length} programs for ${channels.length} channels',
        );
      }
    } on Object catch (e) {
      epgService.markFetchFailed(
        fetchIds,
        sourceGeneration: sourceGeneration,
      );
      if (generation != _epgRequestGeneration ||
          rangeKey != _activeEpgRangeKey) {
        return;
      }
      if (kDebugMode) debugPrint('[EPG] lazy fetch failed: $e');
    }
  }

  /// Re-fetches the guide for every channel without touching the catalog.
  /// The in-memory guide is kept so rows stay populated until each channel's
  /// fresh response replaces them.
  void refreshGuide() {
    if (!_isXtream) return;
    resetSession(clearGuide: false);
    _notifyListeners();
    unawaited(primeAndSweep());
  }

  /// Re-primes the guide when the app returns from the background and the
  /// last successful prime is older than [EpgService.cacheTtl]. TV apps are
  /// usually resumed rather than relaunched, and only the guide rows a screen
  /// happens to rebuild refresh lazily, so without this a long-resident app
  /// keeps showing yesterday's guide until a manual clear.
  ///
  /// Unlike a manual clear this keeps the session: only channels whose data
  /// has outlived the TTL are fetched, and in-flight dated (timeline) and
  /// catch-up fetches carry on. A failed prime is retried once after
  /// [EpgService.retryBackoff], the usual case being Wi-Fi still reconnecting
  /// after standby.
  void refreshEpgGuideIfStale({bool retryOnFailure = true}) {
    if (_disposed ||
        !_isXtream ||
        _isLoadingContent ||
        _epgPrimesInFlight > 0) {
      return;
    }
    final refreshedAt = _epgGuideRefreshedAt;
    if (refreshedAt != null &&
        epgService.now.difference(refreshedAt) < epgService.cacheTtl) {
      return;
    }
    _epgPrimeRetry?.cancel();
    unawaited(primeAndSweep(retryOnFailure: retryOnFailure));
  }

  /// Primes EPG for the first [_epgPrimeCount] channels, then - once that
  /// response and the first frame have settled - sweeps the remaining channels
  /// in the background so the guide is fully populated without the user having
  /// to scroll each row into view.
  ///
  /// [lineup], when the caller already holds the freshly fetched channels,
  /// starts the prime without a catalog read; only its first page is kept.
  Future<void> primeAndSweep({
    List<Channel>? lineup,
    bool retryOnFailure = false,
  }) async {
    final generation = _epgRequestGeneration;
    final primeChannels =
        lineup?.take(_epgPrimeCount).toList(growable: false) ??
        await _channelPage(0, _epgPrimeCount);
    if (_disposed || generation != _epgRequestGeneration) return;
    _epgPrimesInFlight += 1;
    try {
      await _loadXtreamEpg(primeChannels);
    } finally {
      _epgPrimesInFlight -= 1;
    }
    if (_disposed || generation != _epgRequestGeneration) return;
    // Judged by the result, not the request: a prime that skipped channels
    // still in their failure backoff (or mid-fetch elsewhere) didn't refresh
    // them either.
    final primed = primeChannels.every(epgService.hasFreshDataForChannel);
    if (primed) {
      _epgGuideRefreshedAt = epgService.now;
    } else if (retryOnFailure) {
      // The retry sweeps too; sweeping now would only fail chunk by chunk.
      _epgPrimeRetry?.cancel();
      _epgPrimeRetry = Timer(
        EpgService.retryBackoff,
        () => refreshEpgGuideIfStale(retryOnFailure: false),
      );
      return;
    }
    if (!_isXtream || primeChannels.length < _epgPrimeCount) return;
    unawaited(_sweepXtreamEpgInBackground(from: _epgPrimeCount));
  }

  /// Walks the lineup from offset [from] in [_epgSweepChunkSize] batches,
  /// read from the catalog one batch at a time, spaced out so the sweep
  /// never competes hard with foreground work. Bails between chunks on dispose,
  /// a source/guide reset, or a newer sweep; yields to in-flight lazy fetches
  /// (a user actively scrolling the guide) so those stay responsive.
  Future<void> _sweepXtreamEpgInBackground({required int from}) async {
    final sweepGeneration = ++_epgSweepGeneration;
    final requestGeneration = _epgRequestGeneration;
    final total = math.max(0, await _channelCount() - from);
    if (_disposed || sweepGeneration != _epgSweepGeneration) return;
    if (total == 0) {
      // Clears any progress a superseded sweep left showing.
      _epgSweepProgressController.add(null);
      return;
    }
    _epgSweepProgressController.add(EpgSweepProgress(loaded: 0, total: total));
    await Future<void>.delayed(_epgSweepStartDelay);

    void bail() {
      if (sweepGeneration == _epgSweepGeneration) {
        _epgSweepProgressController.add(null);
      }
    }

    var start = 0;
    while (start < total) {
      if (_disposed ||
          sweepGeneration != _epgSweepGeneration ||
          requestGeneration != _epgRequestGeneration ||
          !_isXtream) {
        bail();
        return;
      }
      // A foreground lazy fetch is queued or running - let it go first and
      // re-check this same window on the next pass.
      if (_pendingEpgChannels.isNotEmpty ||
          (_epgFetchDebounce?.isActive ?? false)) {
        await Future<void>.delayed(_epgSweepChunkDelay);
        continue;
      }
      final chunk = await _channelPage(from + start, _epgSweepChunkSize);
      if (chunk.isEmpty) break;
      await _loadXtreamEpg(chunk);
      start += _epgSweepChunkSize;
      if (!_disposed && sweepGeneration == _epgSweepGeneration) {
        _epgSweepProgressController.add(
          EpgSweepProgress(loaded: start.clamp(0, total), total: total),
        );
      }
      await Future<void>.delayed(_epgSweepChunkDelay);
    }
    if (kDebugMode) {
      debugPrint(
        '[EPG] background sweep complete ($total channels)',
      );
    }
    if (!_disposed && sweepGeneration == _epgSweepGeneration) {
      _epgSweepProgressController.add(null);
    }
  }

  Future<void> _loadXtreamEpg(List<Channel> channels) async {
    final generation = _epgRequestGeneration;
    final channelsToFetch = channels
        .where(epgService.shouldFetchDataForChannel)
        .toList(growable: false);
    if (channelsToFetch.isEmpty) return;
    final channelIds = channelsToFetch
        .map(_epgChannelId)
        .toList(growable: false);
    final sourceGeneration = epgService.markFetchStarted(channelIds);
    try {
      final programs = await xtreamService.getEpgBatch(channelsToFetch);
      if (generation != _epgRequestGeneration) {
        epgService.markFetchFailed(
          channelIds,
          sourceGeneration: sourceGeneration,
        );
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[EPG] getEpgBatch → ${programs.length} programs for ${channelsToFetch.length} channels',
        );
      }
      epgService.applySuccessfulResponse(
        channelIds,
        programs,
        sourceGeneration: sourceGeneration,
      );
    } on Object catch (e) {
      epgService.markFetchFailed(
        channelIds,
        sourceGeneration: sourceGeneration,
      );
      if (kDebugMode) debugPrint('[EPG] getEpgBatch failed: $e');
      // Don't clear existing EPG data on a batch failure. A transient network
      // error shouldn't wipe a previously loaded guide.
    }
  }

  /// Fills the guide's now/next from the store on a cold start so the grids
  /// can paint before the network prime lands. Not marked fresh, so the prime
  /// and background sweep still refresh every channel. ([EpgService] writes
  /// every fetch through to the store itself.)
  Future<void> restoreCachedGuide() => epgService.restoreFromStore();

  /// [EpgService.onEvicted]: the channel's full schedule left memory, so
  /// forget which dated ranges and catchup windows were fetched for it - the
  /// next time its timeline row or catchup dialog asks, fetch again rather
  /// than trust data that may only have lived in memory.
  void _onScheduleEvicted(String epgChannelId) {
    final channelIds = [
      for (final MapEntry(:key, :value) in _trackedEpgIds.entries)
        if (value == epgChannelId) key,
    ];
    for (final channelId in channelIds) {
      _fetchedEpgRanges.removeWhere((key, _) => key.startsWith('$channelId:'));
      _catchupEpgFetchedAt.remove(channelId);
      _trackedEpgIds.remove(channelId);
    }
  }

  String _epgChannelId(Channel channel) =>
      channel.epgChannelId ?? channel.tvgName ?? channel.name;

  String _epgRangeFetchId(Channel channel, String rangeKey) =>
      '${_epgChannelId(channel)}:$rangeKey';

  String _epgRangeKey(DateTime? startDate, DateTime? endDate) {
    if (startDate == null) return '';
    String dateKey(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return '${dateKey(startDate)}:${dateKey(endDate ?? startDate)}';
  }

  bool _hasFreshEpgRange(int channelId, String rangeKey) {
    final key = '$channelId:$rangeKey';
    final fetchedAt = _fetchedEpgRanges[key];
    if (fetchedAt == null) return false;
    final elapsed = epgService.now.difference(fetchedAt);
    if (!elapsed.isNegative && elapsed < epgService.cacheTtl) return true;
    _fetchedEpgRanges.remove(key);
    return false;
  }

  void _markEpgRangeFetched(List<Channel> channels, String rangeKey) {
    final now = epgService.now;
    for (final channel in channels) {
      _fetchedEpgRanges['${channel.id}:$rangeKey'] = now;
      _trackedEpgIds[channel.id] = _epgChannelId(channel);
    }
  }

  void resetSession({bool clearGuide = true}) {
    _epgPrimeRetry?.cancel();
    _epgRequestGeneration += 1;
    _epgSweepGeneration += 1;
    _epgFetchDebounce?.cancel();
    _epgFetchDebounce = null;
    _pendingEpgChannels.clear();
    _pendingForcedEpgChannelIds.clear();
    _fetchedEpgRanges.clear();
    _catchupEpgFetchedAt.clear();
    _trackedEpgIds.clear();
    _inFlightCatchupEpgFetches.clear();
    _pendingEpgStartDate = null;
    _pendingEpgEndDate = null;
    _activeEpgRangeKey = '';
    epgService.invalidateSourceFetchState();
    if (clearGuide) epgService.clear();
  }

  void dispose() {
    _disposed = true;
    _epgRequestGeneration += 1;
    _epgSweepGeneration += 1;
    _epgFetchDebounce?.cancel();
    _epgPrimeRetry?.cancel();
    unawaited(_epgSweepProgressController.close());
  }
}
