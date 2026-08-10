import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';

typedef Clock = DateTime Function();

class EpgService extends ChangeNotifier {
  EpgService({Clock? clock, this.cacheTtl = const Duration(minutes: 30)})
    : _clock = clock ?? DateTime.now;

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
    for (final program in programs) {
      final channelPrograms = _programsByChannel.putIfAbsent(
        program.channelId,
        () => <EpgProgram>[],
      );
      final existingIndex = channelPrograms.indexWhere(
        (existing) =>
            existing.start == program.start && existing.end == program.end,
      );
      if (existingIndex == -1) {
        channelPrograms.add(program);
      } else {
        channelPrograms[existingIndex] = program;
      }
    }
    for (final entry in _programsByChannel.entries) {
      entry.value.sort((a, b) => a.start.compareTo(b.start));
    }
    if (markFresh) {
      markFetched(programs.map((program) => program.channelId));
    }
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

  void clear() {
    _programsByChannel.clear();
    _fetchedAtByChannel.clear();
    _failedAtByChannel.clear();
    _fetchesInFlight.clear();
    _loadedAt = null;
    notifyListeners();
  }
}
