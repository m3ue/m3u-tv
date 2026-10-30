import 'package:m3u_tv/services/domain_models.dart';

/// One guide write, recorded in the order `EpgService` applied it in memory
/// so the on-disk guide follows exactly the same replace/merge semantics.
/// Plain data so a batch can be handed to a database worker isolate.
sealed class EpgStoreOp {
  const EpgStoreOp();
}

/// Replace each channel's whole schedule with its new list (an empty list
/// clears the channel). Mirrors a full per-channel fetch response.
final class EpgReplaceChannels extends EpgStoreOp {
  const EpgReplaceChannels(this.byChannel);

  final Map<String, List<EpgProgram>> byChannel;
}

/// Merge each channel's programmes in, newer wins: stored programmes
/// overlapping an incoming one are dropped first. Mirrors a dated (timeline)
/// or catchup-window fetch.
final class EpgMergeIntoChannels extends EpgStoreOp {
  const EpgMergeIntoChannels(this.byChannel);

  final Map<String, List<EpgProgram>> byChannel;
}

/// Drop every stored programme.
final class EpgClearAll extends EpgStoreOp {
  const EpgClearAll();
}

/// Drop every programme that ended before [cutoff].
final class EpgPruneBefore extends EpgStoreOp {
  const EpgPruneBefore(this.cutoff);

  final DateTime cutoff;
}

/// Where `EpgService` keeps the guide it doesn't hold in memory. Implemented
/// over the SQLite catalog by `CatalogRepository`.
abstract interface class EpgProgrammeStore {
  /// Applies [ops] in order, atomically.
  Future<void> applyEpgOps(List<EpgStoreOp> ops);

  /// Every stored programme of each of [channelIds], start-ordered.
  Future<Map<String, List<EpgProgram>>> programmesForChannels(
    Set<String> channelIds,
  );

  /// Programmes that end after [endAfter] and start before [startBefore],
  /// grouped by channel, each start-ordered.
  Future<Map<String, List<EpgProgram>>> programmesBetween(
    DateTime endAfter,
    DateTime startBefore, {
    Set<String>? channelIds,
  });
}

/// The incoming programmes' disjoint spans (start-sorted input), the unit a
/// merge drops overlapping stored programmes by.
List<(DateTime, DateTime)> epgDisjointSpans(List<EpgProgram> startSorted) {
  final spans = <(DateTime, DateTime)>[];
  for (final program in startSorted) {
    final last = spans.isEmpty ? null : spans.last;
    if (last != null && !program.start.isAfter(last.$2)) {
      if (program.end.isAfter(last.$2)) {
        spans[spans.length - 1] = (last.$1, program.end);
      }
    } else {
      spans.add((program.start, program.end));
    }
  }
  return spans;
}
