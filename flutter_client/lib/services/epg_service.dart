import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:m3u_tv/services/domain_models.dart';

typedef Clock = DateTime Function();

class EpgService extends ChangeNotifier {
  EpgService({Clock? clock, this.cacheTtl = const Duration(minutes: 30)})
    : _clock = clock ?? DateTime.now;

  final Clock _clock;
  final Duration cacheTtl;
  final Map<String, List<EpgProgram>> _programsByChannel =
      <String, List<EpgProgram>>{};
  final Map<String, DateTime> _fetchedAtByChannel = <String, DateTime>{};
  DateTime? _loadedAt;

  void loadPrograms(List<EpgProgram> programs) {
    _programsByChannel.clear();
    _storePrograms(programs);
    _loadedAt = _clock();
    notifyListeners();
  }

  void mergePrograms(List<EpgProgram> programs) {
    final channelIds = programs
        .map((program) => program.channelId)
        .where((channelId) => channelId.isNotEmpty)
        .toSet();
    for (final channelId in channelIds) {
      _programsByChannel.remove(channelId);
    }
    _storePrograms(programs);
    _loadedAt = _clock();
    notifyListeners();
  }

  /// Marks [channelIds] as freshly fetched even if the batch returned no
  /// programs for them, so [hasFreshDataForChannel] doesn't keep re-requesting
  /// channels that simply have no EPG data upstream.
  void markFetched(Iterable<String> channelIds) {
    final now = _clock();
    for (final channelId in channelIds) {
      if (channelId.isEmpty) continue;
      _fetchedAtByChannel[channelId] = now;
    }
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

  void _storePrograms(List<EpgProgram> programs) {
    for (final program in programs) {
      _programsByChannel
          .putIfAbsent(program.channelId, () => <EpgProgram>[])
          .add(program);
    }
    for (final entry in _programsByChannel.entries) {
      entry.value.sort((a, b) => a.start.compareTo(b.start));
    }
    markFetched(programs.map((program) => program.channelId));
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
    _loadedAt = null;
  }
}
