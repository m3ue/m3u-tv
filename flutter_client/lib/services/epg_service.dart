// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_store.dart';

typedef Clock = DateTime Function();

/// The in-memory guide.
///
/// Without a store (tests, and before one is attached) every fetched
/// programme stays resident, as it always did. With an [EpgProgrammeStore]
/// attached, the SQLite guide is the store of record and memory is bounded:
///
/// - every channel keeps a short *hot* list (the current programme and the
///   next [hotSize] - 1), which is all the list/grid/Home/player/spotlight
///   now-next lookups read;
/// - full schedules (timeline rows, catchup, details) live in an LRU of
///   [residentCapacity] channels, loaded from the store on first use;
/// - every write is applied to the store as the same replace/merge op.
///
/// The sweep alone used to keep ~8 full programmes for every channel
/// resident for the whole session.
class EpgService extends ChangeNotifier {
  EpgService({
    Clock? clock,
    this.cacheTtl = const Duration(minutes: 30),
    EpgProgrammeStore? store,
    this.residentCapacity = 300,
    this.hotSize = 3,
  }) : _clock = clock ?? DateTime.now,
       _store = store;

  EpgProgrammeStore? _store;

  /// Channels whose full schedule is kept in memory (store mode only).
  final int residentCapacity;

  /// Upcoming programmes kept per non-resident channel (store mode only).
  final int hotSize;

  /// Called when a channel's full schedule is evicted from memory, so the
  /// owner can forget it fetched that channel's dated ranges and refetch
  /// whatever only lived in memory (e.g. catchup history).
  void Function(String channelId)? onEvicted;

  bool get hasStore => _store != null;

  /// Switches to bounded, store-backed mode. Call before any programmes are
  /// loaded; what is already held stays resident.
  void attachStore(EpgProgrammeStore store) => _store = store;

  /// Fallback catchup retention window (in days) used when a channel
  /// supports catchup but does not advertise an explicit [Channel.catchupDays].
  static const int kCatchupFallbackDays = 7;

  /// Resolves the number of days of catchup a channel actually offers: `0`
  /// if catchup isn't supported, otherwise [catchupDays] or
  /// [kCatchupFallbackDays] when unspecified.
  static int effectiveCatchupRetentionDays(
    // ignore: avoid_positional_boolean_parameters
    bool catchupSupported,
    int? catchupDays,
  ) {
    if (!catchupSupported) return 0;
    return catchupDays ?? kCatchupFallbackDays;
  }

  /// Whether [program] is still within the catchup retention window and has
  /// already finished airing, given [catchupRetentionDays] and the current
  /// time [now].
  static bool canReplay(
    int catchupRetentionDays,
    EpgProgram program,
    DateTime now,
  ) {
    if (catchupRetentionDays <= 0 || !program.end.isBefore(now)) return false;
    final earliest = DateTime(
      now.year,
      now.month,
      now.day - catchupRetentionDays,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    return !program.start.isBefore(earliest);
  }

  final Clock _clock;
  static const retryBackoff = Duration(minutes: 1);
  Duration cacheTtl;

  /// The service's notion of "now": the injected [Clock] in tests, real
  /// wall-clock time otherwise. Callers that need to reason about EPG
  /// program timing (e.g. "is this program still in the future") should use
  /// this instead of `DateTime.now()` directly, so they stay consistent with
  /// this service's own current/next computation under a fake clock.
  DateTime get now => _clock();
  // Insertion-ordered, so in store mode the first key is the least recently
  // used resident schedule.
  final LinkedHashMap<String, List<EpgProgram>> _programsByChannel =
      LinkedHashMap<String, List<EpgProgram>>();
  final Map<String, List<EpgProgram>> _hot = <String, List<EpgProgram>>{};
  final Map<String, int> _versions = <String, int>{};
  final Generation _storeGeneration = Generation();
  final SerialQueue _storeQueue = SerialQueue();
  final List<EpgStoreOp> _pendingOps = <EpgStoreOp>[];
  bool _flushScheduled = false;
  final Set<String> _loadQueue = <String>{};
  final Set<String> _loadsInFlight = <String>{};
  bool _loadScheduled = false;
  final Set<String> _hotRefillQueue = <String>{};
  final Map<String, DateTime> _hotRefilledAt = <String, DateTime>{};
  bool _hotRefillScheduled = false;
  static const Duration _hotRefillCooldown = Duration(minutes: 5);
  static const Duration _hotHorizon = Duration(hours: 12);
  static const Duration _prunePastSlack = Duration(hours: 2);
  final Map<String, DateTime> _fetchedAtByChannel = <String, DateTime>{};
  final Map<String, DateTime> _failedAtByChannel = <String, DateTime>{};
  final Set<String> _fetchesInFlight = <String>{};
  final Generation _sourceGeneration = Generation();
  DateTime? _loadedAt;

  void loadPrograms(List<EpgProgram> programs) {
    _programsByChannel.clear();
    _storePrograms(programs, markFresh: true);
    _loadedAt = _clock();
    notifyListeners();
  }

  void mergePrograms(
    List<EpgProgram> programs, {
    Iterable<String>? channelIds,
    bool replaceExisting = true,
    bool markFresh = true,
  }) {
    final replaced = <String>{};
    if (replaceExisting) {
      replaced.addAll(
        (channelIds ??
                programs
                    .map((program) => program.channelId)
                    .where((channelId) => channelId.isNotEmpty))
            .toSet(),
      );
      for (final channelId in replaced) {
        _programsByChannel.remove(channelId);
        _hot.remove(channelId);
        _versions[channelId] = (_versions[channelId] ?? 0) + 1;
      }
    }
    _storePrograms(programs, markFresh: markFresh, replaced: replaced);
    if (_store != null) _persist(programs, replaced);
    _loadedAt = _clock();
    notifyListeners();
  }

  /// Records [programs] for the store as the same ops just applied in
  /// memory: [replaced] channels are replaced wholesale, anything else is
  /// merged in.
  void _persist(List<EpgProgram> programs, Set<String> replaced) {
    final byChannel = <String, List<EpgProgram>>{};
    for (final program in programs) {
      if (program.channelId.isEmpty) continue;
      byChannel.putIfAbsent(program.channelId, () => []).add(program);
    }
    if (replaced.isNotEmpty) {
      _enqueue(
        EpgReplaceChannels({
          for (final id in replaced) id: byChannel[id] ?? const <EpgProgram>[],
        }),
      );
    }
    final merged = {
      for (final entry in byChannel.entries)
        if (!replaced.contains(entry.key)) entry.key: entry.value,
    };
    if (merged.isNotEmpty) _enqueue(EpgMergeIntoChannels(merged));
  }

  void applySuccessfulResponse(
    Iterable<String> channelIds,
    List<EpgProgram> programs, {
    int? sourceGeneration,
  }) {
    if (sourceGeneration != null &&
        _sourceGeneration.isStale(sourceGeneration)) {
      return;
    }
    markFetched(channelIds);
    mergePrograms(
      programs,
      channelIds: channelIds,
      markFresh: false,
    );
  }

  /// Marks [channelIds] as freshly fetched even if the batch returned no
  /// programs for them, so [hasFreshDataForChannel] doesn't keep re-requesting
  /// channels that simply have no EPG data upstream.
  void markFetched(Iterable<String> channelIds) {
    final now = _clock();
    for (final channelId in channelIds) {
      if (channelId.isEmpty) continue;
      _fetchedAtByChannel[channelId] = now;
      _failedAtByChannel.remove(channelId);
      _fetchesInFlight.remove(channelId);
    }
  }

  int markFetchStarted(Iterable<String> channelIds) {
    _fetchesInFlight.addAll(
      channelIds.where((channelId) => channelId.isNotEmpty),
    );
    return _sourceGeneration.current;
  }

  void markFetchFailed(
    Iterable<String> channelIds, {
    int? sourceGeneration,
  }) {
    if (sourceGeneration != null &&
        _sourceGeneration.isStale(sourceGeneration)) {
      return;
    }
    final now = _clock();
    for (final channelId in channelIds) {
      if (channelId.isEmpty) continue;
      _fetchesInFlight.remove(channelId);
      _failedAtByChannel[channelId] = now;
    }
  }

  void invalidateSourceFetchState() {
    _sourceGeneration.advance();
    _fetchedAtByChannel.clear();
    _failedAtByChannel.clear();
    _fetchesInFlight.clear();
  }

  /// Whether any of [channel]'s known identifiers have been fetched within
  /// [cacheTtl]. Used to scope lazy EPG requests to channels that actually
  /// need refreshing (e.g. as they scroll into view).
  bool hasFreshDataForChannel(Channel channel) {
    final ids = <String?>[channel.epgChannelId, channel.tvgName, channel.name];
    final now = _clock();
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final fetchedAt = _fetchedAtByChannel[id];
      if (fetchedAt != null && now.difference(fetchedAt) < cacheTtl) {
        return true;
      }
    }
    return false;
  }

  bool shouldFetchDataForChannel(Channel channel) {
    final ids = <String?>[channel.epgChannelId, channel.tvgName, channel.name];
    return _shouldFetchData(ids);
  }

  bool shouldFetchData(String channelId) =>
      _shouldFetchData(<String>[channelId]);

  bool _shouldFetchData(Iterable<String?> ids) {
    final now = _clock();
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      if (_fetchesInFlight.contains(id)) return false;
      final failedAt = _failedAtByChannel[id];
      if (failedAt != null) {
        final elapsed = now.difference(failedAt);
        if (!elapsed.isNegative && elapsed < retryBackoff) return false;
        continue;
      }
      final fetchedAt = _fetchedAtByChannel[id];
      if (fetchedAt != null && now.difference(fetchedAt) < cacheTtl) {
        return false;
      }
    }
    return true;
  }

  void _storePrograms(
    List<EpgProgram> programs, {
    required bool markFresh,
    Set<String> replaced = const <String>{},
  }) {
    // Keyed by slot so a repeat within the batch replaces the earlier copy
    // (the server's date + next-day reads can return a programme twice).
    final incomingByChannel = <String, Map<(DateTime, DateTime), EpgProgram>>{};
    for (final program in programs) {
      incomingByChannel.putIfAbsent(program.channelId, () => {})[(
            program.start,
            program.end,
          )] =
          program;
    }
    for (final MapEntry(key: channelId, value: incomingBySlot)
        in incomingByChannel.entries) {
      final incoming = incomingBySlot.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (_store != null &&
          !_programsByChannel.containsKey(channelId) &&
          replaced.contains(channelId)) {
        // A full fetch for a channel whose schedule isn't resident: keep just
        // the hot slice; the rest is in the store.
        _hot[channelId] = _trimHot(incoming);
        continue;
      }
      if (_store != null && !_programsByChannel.containsKey(channelId)) {
        // A dated/catchup merge: the caller is about to show this channel's
        // schedule, so make it resident now from what memory has, and fill
        // in the rest from the store.
        _programsByChannel[channelId] = _mergeNewerWins(
          _hot[channelId] ?? const <EpgProgram>[],
          incoming,
        );
        _hot[channelId] = _trimHot(_programsByChannel[channelId]!);
        _queueLoad(channelId);
        _evictOverCapacity();
        continue;
      }
      final channelPrograms = _programsByChannel.putIfAbsent(
        channelId,
        () => <EpgProgram>[],
      );
      if (channelPrograms.isEmpty) {
        channelPrograms.addAll(incoming);
        continue;
      }
      // Only touched channels are re-sorted, and in one linear pass: this
      // runs on the UI isolate for every sweep batch, so re-sorting the whole
      // guide each time (or comparing every held programme with every
      // incoming one) shows up as jank on low-end TV boxes.
      // Updated in place: callers may hold the list programsForChannel
      // returned.
      final merged = _mergeNewerWins(channelPrograms, incoming);
      channelPrograms
        ..clear()
        ..addAll(merged);
      if (_store != null) {
        _touch(channelId);
        _hot[channelId] = _trimHot(channelPrograms);
      }
    }
    if (_store != null) _evictOverCapacity();
    if (markFresh) {
      markFetched(programs.map((program) => program.channelId));
    }
  }

  /// Merges two start-sorted lists, dropping every [existing] programme that
  /// overlaps an [incoming] one so newer data wins: a rescheduled slot or a
  /// "no data" placeholder from an earlier fetch can't linger beside its
  /// replacement. Linear in the size of both lists.
  static List<EpgProgram> _mergeNewerWins(
    List<EpgProgram> existing,
    List<EpgProgram> incoming,
  ) {
    // The incoming programmes as disjoint, start-sorted spans.
    final spans = <(DateTime, DateTime)>[];
    for (final program in incoming) {
      final last = spans.isEmpty ? null : spans.last;
      if (last != null && !program.start.isAfter(last.$2)) {
        if (program.end.isAfter(last.$2)) {
          spans[spans.length - 1] = (last.$1, program.end);
        }
      } else {
        spans.add((program.start, program.end));
      }
    }
    final merged = <EpgProgram>[];
    var span = 0;
    var next = 0;
    for (final program in existing) {
      // Both lists are start-sorted, so spans ending before this programme
      // starts can't overlap any later one either.
      while (span < spans.length && !spans[span].$2.isAfter(program.start)) {
        span += 1;
      }
      if (span < spans.length && spans[span].$1.isBefore(program.end)) {
        continue;
      }
      while (next < incoming.length &&
          incoming[next].start.isBefore(program.start)) {
        merged.add(incoming[next++]);
      }
      merged.add(program);
    }
    merged.addAll(incoming.skip(next));
    return merged;
  }

  void loadBatch(Map<String, List<EpgProgram>> batch) {
    loadPrograms(
      batch.values.expand((programs) => programs).toList(growable: false),
    );
  }

  bool get isFresh =>
      _loadedAt != null && _clock().difference(_loadedAt!) < cacheTtl;

  EpgCurrentNext? lookupForChannel(Channel channel) {
    final ids = <String?>[channel.epgChannelId, channel.tvgName, channel.name];
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final result = lookup(id);
      if (result != null) return result;
    }
    return null;
  }

  EpgCurrentNext? lookup(String channelId) {
    final resident = _programsByChannel[channelId];
    final programs = resident ?? _hot[channelId];
    if (programs == null || programs.isEmpty) return null;
    final now = _clock();
    if (_store != null && resident == null) _maybeRefillHot(channelId, now);
    for (var index = 0; index < programs.length; index++) {
      final program = programs[index];
      if (!now.isBefore(program.start) && now.isBefore(program.end)) {
        final total = program.end.difference(program.start).inMilliseconds;
        final elapsed = now.difference(program.start).inMilliseconds;
        return EpgCurrentNext(
          current: program,
          next: index + 1 < programs.length ? programs[index + 1] : null,
          progress: total <= 0 ? 0 : (elapsed / total).clamp(0, 1).toDouble(),
        );
      }
    }
    return null;
  }

  /// The held programmes for one EPG channel id, start-ordered (empty when
  /// none).
  List<EpgProgram> programsForId(String channelId) =>
      _programsByChannel[channelId] ?? _hot[channelId] ?? const <EpgProgram>[];

  /// Whether any of [channel]'s identifiers has programmes in memory (hot or
  /// resident). Unlike [programsForChannel] this never triggers a store load.
  bool hasProgramsFor(Channel channel) {
    for (final id in [channel.epgChannelId, channel.tvgName, channel.name]) {
      if (id == null || id.isEmpty) continue;
      if ((_programsByChannel[id] ?? _hot[id] ?? const []).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Returns every known program for [channel], sorted by start time.
  ///
  /// In store mode a channel that isn't resident returns its hot slice now
  /// and loads its full schedule from the store, notifying when it lands.
  List<EpgProgram> programsForChannel(Channel channel) {
    final ids = <String?>[channel.epgChannelId, channel.tvgName, channel.name];
    String? loadId;
    List<EpgProgram>? fallback;
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final programs = _programsByChannel[id];
      if (programs != null) {
        if (_store != null) _touch(id);
        if (programs.isNotEmpty) return programs;
        continue;
      }
      if (_store == null) continue;
      final hot = _hot[id];
      if (fallback == null && hot != null && hot.isNotEmpty) {
        fallback = hot;
        loadId = id;
      }
      loadId ??= id;
    }
    // One load per channel: the identifier its hot data lives under, else
    // its primary one, so a channel doesn't take several resident slots.
    if (loadId != null) _queueLoad(loadId);
    return fallback ?? const <EpgProgram>[];
  }

  /// Returns [channel]'s replayable catchup programs, most-recent-first.
  /// Empty if the channel doesn't support catchup or none currently qualify.
  List<EpgProgram> catchupProgramsForChannel(Channel channel) {
    final retentionDays = effectiveCatchupRetentionDays(
      channel.catchupSupported,
      channel.catchupDays,
    );
    if (retentionDays <= 0) return const <EpgProgram>[];
    final programs = programsForChannel(
      channel,
    ).where((p) => canReplay(retentionDays, p, now)).toList();
    return programs.reversed.toList();
  }

  /// A flat snapshot of every known program whose [EpgProgram.end] is at or
  /// after [from], for offline persistence. Grouped by channel (map iteration
  /// order), each channel's programs already sorted by start.
  List<EpgProgram> programsEndingAfter(DateTime from) {
    final result = <EpgProgram>[];
    for (final programs in _programsByChannel.values) {
      for (final program in programs) {
        if (!program.end.isBefore(from)) result.add(program);
      }
    }
    return result;
  }

  void clear() {
    _programsByChannel.clear();
    _hot.clear();
    _versions.clear();
    _pendingOps.clear();
    _loadQueue.clear();
    _hotRefillQueue.clear();
    _hotRefilledAt.clear();
    _storeGeneration.advance();
    _fetchedAtByChannel.clear();
    _failedAtByChannel.clear();
    _fetchesInFlight.clear();
    _loadedAt = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Store mode
  // ---------------------------------------------------------------------------

  /// Fills the hot slices from the store on a cold start, so the grids can
  /// paint now/next before the network prime lands. Not marked fresh, so the
  /// prime and sweep still refresh every channel. Never writes back.
  Future<void> restoreFromStore() async {
    final store = _store;
    if (store == null) return;
    final generation = _storeGeneration.current;
    final now = _clock();
    final byChannel = await store.programmesBetween(now, now.add(_hotHorizon));
    if (_storeGeneration.isStale(generation) || byChannel.isEmpty) return;
    for (final MapEntry(key: id, value: programs) in byChannel.entries) {
      if (_programsByChannel.containsKey(id) || _hot.containsKey(id)) continue;
      _hot[id] = _trimHot(programs);
    }
    _loadedAt = _clock();
    notifyListeners();
  }

  /// Writes every queued op to the store, in order. Loads await this first,
  /// so a read always sees what memory already applied.
  Future<void> flushStore() => _storeQueue.run(() async {
    final store = _store;
    if (store == null || _pendingOps.isEmpty) return;
    final ops = [
      ..._pendingOps,
      EpgPruneBefore(_clock().subtract(_prunePastSlack)),
    ];
    _pendingOps.clear();
    try {
      await store.applyEpgOps(ops);
    } on Object catch (error) {
      debugPrint('[EPG] store write failed: $error');
    }
  });

  void _enqueue(EpgStoreOp op) {
    _pendingOps.add(op);
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(() {
      _flushScheduled = false;
      unawaited(flushStore());
    });
  }

  List<EpgProgram> _trimHot(List<EpgProgram> startSorted) {
    final now = _clock();
    final hot = <EpgProgram>[];
    for (final program in startSorted) {
      if (!program.end.isAfter(now)) continue;
      hot.add(program);
      if (hot.length >= hotSize) break;
    }
    return hot;
  }

  void _touch(String channelId) {
    final programs = _programsByChannel.remove(channelId);
    if (programs != null) _programsByChannel[channelId] = programs;
  }

  void _evictOverCapacity() {
    while (_programsByChannel.length > residentCapacity) {
      final id = _programsByChannel.keys.first;
      final programs = _programsByChannel.remove(id)!;
      _hot[id] = _trimHot(programs);
      // Dated-range freshness for this channel described data that is now
      // only in the store (or, for catchup history, gone): forget it.
      _fetchedAtByChannel.removeWhere((key, _) => key.startsWith('$id:'));
      onEvicted?.call(id);
    }
  }

  void _queueLoad(String channelId) {
    if (_loadsInFlight.contains(channelId)) return;
    _loadQueue.add(channelId);
    if (_loadScheduled) return;
    _loadScheduled = true;
    scheduleMicrotask(() {
      _loadScheduled = false;
      unawaited(_runLoads());
    });
  }

  Future<void> _runLoads() async {
    final store = _store;
    if (store == null || _loadQueue.isEmpty) return;
    final ids = {..._loadQueue};
    _loadQueue.clear();
    _loadsInFlight.addAll(ids);
    final generation = _storeGeneration.current;
    final versions = {for (final id in ids) id: _versions[id] ?? 0};
    try {
      await flushStore();
      final stored = await store.programmesForChannels(ids);
      if (_storeGeneration.isStale(generation)) return;
      final reload = <String>[];
      for (final id in ids) {
        if ((_versions[id] ?? 0) != versions[id]) {
          reload.add(id);
          continue;
        }
        // Memory wins over the store for overlapping slots: anything merged
        // in since the read began is newer than what the store returned.
        final memory = _programsByChannel[id] ?? _hot[id] ?? const [];
        _programsByChannel.remove(id);
        _programsByChannel[id] = _mergeNewerWins(
          stored[id] ?? const <EpgProgram>[],
          memory,
        );
        _hot[id] = _trimHot(_programsByChannel[id]!);
      }
      _evictOverCapacity();
      notifyListeners();
      reload.forEach(_queueLoad);
    } on Object catch (error) {
      debugPrint('[EPG] store load failed: $error');
    } finally {
      _loadsInFlight.removeAll(ids);
    }
  }

  void _maybeRefillHot(String channelId, DateTime now) {
    final hot = _hot[channelId];
    if (hot == null) return;
    var upcoming = 0;
    for (final program in hot) {
      if (program.end.isAfter(now)) upcoming += 1;
    }
    if (upcoming >= 2) return;
    final last = _hotRefilledAt[channelId];
    if (last != null && now.difference(last) < _hotRefillCooldown) return;
    _hotRefilledAt[channelId] = now;
    _hotRefillQueue.add(channelId);
    if (_hotRefillScheduled) return;
    _hotRefillScheduled = true;
    scheduleMicrotask(() {
      _hotRefillScheduled = false;
      unawaited(_runHotRefills());
    });
  }

  Future<void> _runHotRefills() async {
    final store = _store;
    if (store == null || _hotRefillQueue.isEmpty) return;
    final ids = {..._hotRefillQueue};
    _hotRefillQueue.clear();
    final generation = _storeGeneration.current;
    try {
      await flushStore();
      final now = _clock();
      final stored = await store.programmesBetween(
        now,
        now.add(_hotHorizon),
        channelIds: ids,
      );
      if (_storeGeneration.isStale(generation)) return;
      var changed = false;
      for (final id in ids) {
        if (_programsByChannel.containsKey(id)) continue;
        final rows = stored[id];
        if (rows == null || rows.isEmpty) continue;
        _hot[id] = _trimHot(
          _mergeNewerWins(rows, _hot[id] ?? const <EpgProgram>[]),
        );
        changed = true;
      }
      if (changed) notifyListeners();
    } on Object catch (error) {
      debugPrint('[EPG] hot refill failed: $error');
    }
  }
}
