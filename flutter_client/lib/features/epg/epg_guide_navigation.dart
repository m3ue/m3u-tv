import 'package:m3u_tv/services/domain_models.dart';

/// Pure programme lookups behind the timeline guide's D-pad cursor.
///
/// The guide moves a logical cursor over (row, programme) instead of
/// letting spatial focus traversal pick between hundreds of rendered
/// blocks: left/right step through a row's programmes in order, and
/// up/down land on whatever the adjacent row is airing at the cursor's
/// anchor time, so a vertical run stays in the same time column.
abstract final class EpgGuideNavigation {
  /// The programmes of [programs] (sorted by start) that overlap
  /// [windowStart]..[windowEnd] for at least a minute once clamped to it.
  static List<EpgProgram> inWindow(
    List<EpgProgram> programs,
    DateTime windowStart,
    DateTime windowEnd,
  ) {
    final result = <EpgProgram>[];
    for (final program in programs) {
      if (!program.end.isAfter(windowStart)) continue;
      if (!program.start.isBefore(windowEnd)) break;
      final start = program.start.isBefore(windowStart)
          ? windowStart
          : program.start;
      final end = program.end.isAfter(windowEnd) ? windowEnd : program.end;
      if (end.difference(start).inMinutes < 1) continue;
      result.add(program);
    }
    return result;
  }

  /// The programme airing at [time], or the one closest to it when [time]
  /// falls in a gap (ties go to the later programme). Null when empty.
  static EpgProgram? at(List<EpgProgram> programs, DateTime time) {
    EpgProgram? best;
    Duration? bestDistance;
    for (final program in programs) {
      if (!time.isBefore(program.start) && time.isBefore(program.end)) {
        return program;
      }
      final distance = time.isBefore(program.start)
          ? program.start.difference(time)
          : time.difference(program.end);
      if (bestDistance == null || distance <= bestDistance) {
        best = program;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int indexOf(List<EpgProgram> programs, EpgProgram program) =>
      programs.indexWhere((candidate) => candidate.start == program.start);

  static EpgProgram? next(List<EpgProgram> programs, EpgProgram current) {
    final index = indexOf(programs, current);
    if (index < 0) return at(programs, current.end);
    return index + 1 < programs.length ? programs[index + 1] : null;
  }

  static EpgProgram? previous(List<EpgProgram> programs, EpgProgram current) {
    final index = indexOf(programs, current);
    if (index < 0) return null;
    return index > 0 ? programs[index - 1] : null;
  }

  /// The time vertical moves stay aligned with after the cursor lands on
  /// [program] horizontally: "now" while it's airing (so up/down from a
  /// live programme stays on live programmes), otherwise its start, pulled
  /// forward to [visibleStart] when that start is scrolled off-screen.
  static DateTime anchorFor(
    EpgProgram program, {
    required DateTime now,
    required DateTime visibleStart,
  }) {
    if (!now.isBefore(program.start) && now.isBefore(program.end)) return now;
    if (program.start.isBefore(visibleStart) &&
        program.end.isAfter(visibleStart)) {
      return visibleStart;
    }
    return program.start;
  }
}
