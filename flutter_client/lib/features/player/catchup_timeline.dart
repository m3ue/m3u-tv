/// How [CatchupTimeline.planSeek] reaches a programme position.
sealed class CatchupSeek {
  const CatchupSeek();
}

/// Seek inside the open timeshift stream, to [streamPosition] on its own
/// clock.
final class CatchupInStreamSeek extends CatchupSeek {
  const CatchupInStreamSeek(this.streamPosition);

  final Duration streamPosition;
}

/// Reopen the programme as a new timeshift stream that starts at [start] and
/// runs for [duration].
final class CatchupReopen extends CatchupSeek {
  const CatchupReopen({required this.start, required this.duration});

  final DateTime start;
  final Duration duration;
}

/// A catchup programme's timeline, mapped onto the timeshift stream currently
/// open for it.
///
/// Xtream timeshift URLs carry their start time, so a long seek reopens the
/// programme at the target minute instead of seeking inside the stream. A
/// seek inside a timeshift stream costs a run of Range requests (ExoPlayer
/// sends every one back through the editor's redirect), and a stream the
/// proxy transcodes, or a provider serves without Range support, can't seek
/// at all. Short seeks still seek in place when the stream can.
class CatchupTimeline {
  CatchupTimeline({
    required this.programStart,
    required this.programEnd,
    DateTime? streamStart,
  }) : streamStart = streamStart ?? _floorToMinute(programStart);

  /// Reads the programme window the catchup launcher stores on the player
  /// args. Null when it is missing or empty.
  static CatchupTimeline? fromMetadata(Map<String, Object?> metadata) {
    DateTime? read(String key) {
      final value = metadata[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    final start = read('program_start');
    final end = read('program_end');
    if (start == null || end == null || !end.isAfter(start)) return null;
    return CatchupTimeline(programStart: start, programEnd: end);
  }

  /// The furthest a seek may travel and still seek inside the open stream.
  static const Duration reopenThreshold = Duration(minutes: 1);

  final DateTime programStart;
  final DateTime programEnd;

  /// Wall-clock start of the open stream. Timeshift starts are whole
  /// minutes, so the first stream can start up to a minute before the
  /// programme does.
  final DateTime streamStart;

  Duration get duration => programEnd.difference(programStart);

  Duration get _streamOffset => streamStart.difference(programStart);

  /// The programme position of [streamPosition] on the open stream.
  Duration positionOf(Duration streamPosition) =>
      _clamp(_streamOffset + streamPosition);

  CatchupTimeline withStreamStart(DateTime start) => CatchupTimeline(
    programStart: programStart,
    programEnd: programEnd,
    streamStart: start,
  );

  /// Plans a seek from programme position [from] to [target], or returns
  /// null when there is nowhere to go.
  CatchupSeek? planSeek(
    Duration target, {
    required Duration from,
    required bool streamSeekable,
  }) {
    final to = _clamp(target);
    if (to == from) return null;
    final inStream = to - _streamOffset;
    if (streamSeekable &&
        !inStream.isNegative &&
        (to - from).abs() <= reopenThreshold) {
      return CatchupInStreamSeek(inStream);
    }

    // Providers only take whole-minute starts, so the stream reopens at the
    // target's minute and plays from up to a minute early. A forward skip
    // that would floor back onto the current position moves on a minute
    // instead.
    var start = _floorToMinute(programStart.add(to));
    if (to > from && !start.isAfter(programStart.add(from))) {
      start = start.add(const Duration(minutes: 1));
    }
    if (!start.isBefore(programEnd)) return null;
    final minutesLeft = (programEnd.difference(start).inSeconds / 60).ceil();
    return CatchupReopen(
      start: start,
      duration: Duration(minutes: minutesLeft),
    );
  }

  Duration _clamp(Duration position) {
    if (position.isNegative) return Duration.zero;
    return position > duration ? duration : position;
  }

  static DateTime _floorToMinute(DateTime time) {
    final ms = time.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
      ms - ms % Duration.millisecondsPerMinute,
      isUtc: true,
    );
  }
}
