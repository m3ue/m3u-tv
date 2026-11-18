/// A watch-history tracker the player reports playback to (Trakt, Simkl,
/// MDBList).
abstract interface class WatchHistoryService {
  /// Whether a signed-in account can currently receive scrobbles.
  bool get isConnected;

  /// Whether to repeat `'start'` periodically during playback. Simkl asks for
  /// events on user actions only and extrapolates progress itself.
  bool get wantsProgressHeartbeat;

  /// Reports playback. [action] is one of `'start'`, `'pause'`, or `'stop'`;
  /// [progress] is 0 to 100. Best-effort: never throws. Pass [seriesTitle],
  /// [season], and [episode] for TV episodes; omit them for movies.
  Future<void> scrobble({
    required String action,
    required String title,
    String? seriesTitle,
    int? season,
    int? episode,
    int? tmdbId,
    String? imdbId,
    int? year,
    required double progress,
  });
}
