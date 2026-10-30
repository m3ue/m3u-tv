/// Live TV, Home's live row, Search and the guide page channels from the
/// SQLite catalog instead of holding every channel in memory.
///
/// Short-lived: kept only until the windowed path has been verified on
/// low-memory Android TV hardware. Build with
/// `--dart-define=WINDOWED_LIVE_TV=false` to compare against the in-memory
/// channel list.
const bool kWindowedLiveTv = bool.fromEnvironment(
  'WINDOWED_LIVE_TV',
  defaultValue: true,
);
