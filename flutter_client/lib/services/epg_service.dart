import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';

typedef Clock = DateTime Function();

class EpgService extends ChangeNotifier {
  EpgService({Clock? clock, this.cacheTtl = const Duration(minutes: 30)})
    : _clock = clock ?? DateTime.now;

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
  final Map<String, List<EpgProgram>> _programsByChannel =
      <String, List<EpgProgram>>{};
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
    if (replaceExisting) {
      final replacedChannelIds =
          channelIds ??
          programs
              .map((program) => program.channelId)
              .where((channelId) => channelId.isNotEmpty);
      for (final channelId in replacedChannelIds) {
        _programsByChannel.remove(channelId);
      }
    }
    _storePrograms(programs, markFresh: markFresh);
    _loadedAt = _clock();
    notifyListeners();
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
    }
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
    final programs = _programsByChannel[channelId];
    if (programs == null || programs.isEmpty) return null;
    final now = _clock();
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

  /// Returns every known program for [channel], sorted by start time.
  List<EpgProgram> programsForChannel(Channel channel) {
    final ids = <String?>[channel.epgChannelId, channel.tvgName, channel.name];
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final programs = _programsByChannel[id];
      if (programs != null && programs.isNotEmpty) return programs;
    }
    return const <EpgProgram>[];
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
    _fetchedAtByChannel.clear();
    _failedAtByChannel.clear();
    _fetchesInFlight.clear();
    _loadedAt = null;
    notifyListeners();
  }
}
