import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// O(1)-per-query index that answers "what is this EPG programme's DVR
/// recording state?" for the indicator badges drawn on the timeline grid
/// (see issue #185).
///
/// The grid renders many programme blocks across many channels and asks
/// once per block, so we bucket recordings by [DvrRecording.channelId] at
/// construction time and never scan the full list during [stateFor].
///
/// ## Matching predicate — coverage-based
///
/// A recording matches a programme when
/// `overlap(programme, recording) / programme_duration >= 0.8`.
///
/// ### Why coverage, not strict containment or midpoint
///
/// **Strict containment** (`programme ⊆ recording`) is the tightest match:
/// it false-matches an adjacent programme only when the adjacent programme
/// is at most as long as the padding (`D <= P`). But it has zero tolerance
/// for EPG or schedule drift — if the EPG timing is off by even a second
/// relative to the planned window, a perfectly-scheduled recording fails
/// to match.
///
/// **Midpoint containment** (`programme.midpoint ∈ recording`) is the
/// loosest of the three: it false-matches whenever `D <= 2P`. Verified
/// empirically: a 45s adjacent programme under default 30s padding, and a
/// 15-minute adjacent programme under 10-minute padding, both false-match
/// under midpoint. The same reasoning generalises — midpoint is strictly
/// worse than strict containment for the adjacent-programme failure mode,
/// because its false-positive range (D <= 2P) is a strict superset of
/// strict containment's (D <= P).
///
/// **Coverage at 0.8** sits between them: false-positive range
/// `D <= 1.25 * P`, while tolerating up to 20% EPG or schedule drift.
/// See the derivation below.
///
/// ### False-positive threshold derivation
///
/// For an adjacent programme `A` with window `[A_start, A_end]` and
/// duration `D = A_end - A_start`, whose later neighbour has a recording
/// with window `[B_start - P, B_end + P]` and padding `P` (where
/// `B_start = A_end`):
///
/// ```text
/// overlap = min(A_end, B_end + P) - max(A_start, A_end - P)
/// ```
///
/// `min(A_end, B_end + P) = A_end` (B is later than A), so:
///
/// * If `D > P`, `max(...) = A_end - P` and `overlap = P`.
/// * If `D <= P`, `max(...) = A_start` and `overlap = D` (programme is
///   fully inside the recording's padded window).
///
/// Coverage becomes:
///
/// * `D > P`: `coverage = P / D`. False-match when `P / D >= 0.8`,
///   i.e. `D <= 1.25 * P`.
/// * `D <= P`: `coverage = 1.0`. Always false-matches — same range as
///   strict containment exhibits, intrinsic to any time-overlap predicate
///   once padding approaches programme length.
///
/// ### Residual limitation
///
/// As padding approaches or exceeds the adjacent programme's duration,
/// coverage-based matching degrades. The badge may then appear on the
/// wrong block, but only for extremely short adjacent programmes (e.g.
/// 30-second station IDs under 30-second padding, or 10-minute news
/// briefs under 10-minute padding). This is inherent to any time-overlap
/// predicate when padding is comparable to programme length, and is
/// accepted as a cosmetic edge case for a non-critical indicator.
///
/// ## Status mapping
///
/// Terminal statuses ([DvrRecordingStatus.completed], [DvrRecordingStatus.failed],
/// [DvrRecordingStatus.cancelled], [DvrRecordingStatus.deleted],
/// [DvrRecordingStatus.unknown]) are skipped at build time — see
/// [EpgRecordingState]'s contract for the rationale.
class EpgRecordingIndex {
  const EpgRecordingIndex._(this._byChannel);

  /// Build an index from the current recordings list.
  ///
  /// Recordings missing [DvrRecording.channelId], [DvrRecording.scheduledStart]
  /// or [DvrRecording.scheduledEnd], or whose end is not strictly after their
  /// start, or whose status maps to [EpgRecordingState.none], are skipped
  /// silently. Returns [empty] when every input is skipped.
  factory EpgRecordingIndex.fromRecordings(List<DvrRecording> recordings) {
    final byChannel = <int, List<_Match>>{};
    for (final r in recordings) {
      final id = r.channelId;
      final start = r.scheduledStart;
      final end = r.scheduledEnd;
      if (id == null || start == null || end == null) continue;
      if (!end.isAfter(start)) continue;
      final state = _mapStatus(r.status);
      if (state == EpgRecordingState.none) continue;
      byChannel
          .putIfAbsent(id, () => <_Match>[])
          .add(_Match(start, end, state));
    }
    if (byChannel.isEmpty) return empty;
    return EpgRecordingIndex._(byChannel);
  }

  /// Sentinel for "no recordings indexed" — e.g., DVR feature disabled,
  /// empty recordings list, or every input recording was skipped. Always
  /// returns [EpgRecordingState.none] from [stateFor].
  static const EpgRecordingIndex empty = EpgRecordingIndex._(
    <int, List<_Match>>{},
  );

  /// Minimum fraction of the programme window that must overlap the
  /// recording window for the recording to count as a match. See the
  /// class docstring for the rationale and false-positive threshold
  /// derivation.
  static const double _coverageThreshold = 0.8;

  final Map<int, List<_Match>> _byChannel;

  /// Query the recording state for an EPG programme.
  ///
  /// Returns [EpgRecordingState.recording] if any indexed in-flight recording
  /// (status `recording` or `postProcessing`) covers at least
  /// `[_coverageThreshold]` of the programme. Otherwise
  /// [EpgRecordingState.scheduled] if any indexed queued recording does.
  /// Otherwise [EpgRecordingState.none].
  ///
  /// A programme with `programEnd` not strictly after `programStart` is
  /// treated as invalid and returns [EpgRecordingState.none] without
  /// scanning — protects against malformed grid data.
  EpgRecordingState stateFor({
    required int channelId,
    required DateTime programStart,
    required DateTime programEnd,
  }) {
    final entries = _byChannel[channelId];
    if (entries == null || entries.isEmpty) return EpgRecordingState.none;
    if (!programEnd.isAfter(programStart)) return EpgRecordingState.none;
    final programStartMs = programStart.millisecondsSinceEpoch;
    final programEndMs = programEnd.millisecondsSinceEpoch;
    final programDurationMs = programEndMs - programStartMs;
    final coverageThresholdMs = (programDurationMs * _coverageThreshold)
        .round();
    var best = EpgRecordingState.none;
    for (final e in entries) {
      final recordingStartMs = e.start.millisecondsSinceEpoch;
      final recordingEndMs = e.end.millisecondsSinceEpoch;
      final overlapStartMs = programStartMs > recordingStartMs
          ? programStartMs
          : recordingStartMs;
      final overlapEndMs = programEndMs < recordingEndMs
          ? programEndMs
          : recordingEndMs;
      final overlapMs = overlapEndMs - overlapStartMs;
      if (overlapMs < coverageThresholdMs) continue;
      if (e.state == EpgRecordingState.recording) {
        return EpgRecordingState.recording;
      }
      best = EpgRecordingState.scheduled;
    }
    return best;
  }
}

class _Match {
  const _Match(this.start, this.end, this.state);
  final DateTime start;
  final DateTime end;
  final EpgRecordingState state;
}

EpgRecordingState _mapStatus(DvrRecordingStatus s) {
  switch (s) {
    case DvrRecordingStatus.scheduled:
      return EpgRecordingState.scheduled;
    case DvrRecordingStatus.recording:
    case DvrRecordingStatus.postProcessing:
      return EpgRecordingState.recording;
    case DvrRecordingStatus.completed:
    case DvrRecordingStatus.failed:
    case DvrRecordingStatus.cancelled:
    case DvrRecordingStatus.deleted:
    case DvrRecordingStatus.unknown:
      return EpgRecordingState.none;
  }
}
