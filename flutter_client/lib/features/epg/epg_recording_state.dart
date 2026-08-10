/// How a single EPG programme block relates to DVR recording, for the
/// indicator drawn on it in the timeline grid (see issue #185).
///
/// Deliberately smaller than `DvrRecordingStatus`: the grid only needs to
/// distinguish "nothing to show", "queued for later", and "capturing right
/// now". Terminal states (completed / failed / cancelled / deleted) collapse
/// to [none] — once a recording is finished or gone there is nothing useful
/// to badge on a programme block, and the DVR Recordings screen owns that
/// history.
///
/// This is the shared contract between the recording→programme matcher and
/// the widget that renders the indicator, so the two can be built
/// independently.
enum EpgRecordingState {
  /// No recording is scheduled or running for this programme.
  none,

  /// A recording exists for this programme but has not started capturing.
  /// Maps from `DvrRecordingStatus.scheduled`.
  scheduled,

  /// A recording for this programme is capturing now, or is in
  /// post-processing and so has not yet left the "in flight" phase. Maps from
  /// `DvrRecordingStatus.recording` and `DvrRecordingStatus.postProcessing`.
  recording,
}
