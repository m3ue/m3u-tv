/// Route name constants matching the current RN navigation structure.
///
/// Main tab/sidebar routes: Home, Search, LiveTV, VOD, Series, DVR, Requests,
/// Settings.
/// Modal/overlay routes: Player, Details, SeriesDetails, ViewerSelection.
class RouteNames {
  RouteNames._();

  // Main tab/sidebar destinations
  static const String home = '/home';
  static const String search = '/search';
  static const String liveTv = '/live-tv';
  static const String vod = '/vod';
  static const String series = '/series';
  static const String dvr = '/dvr';
  static const String requests = '/requests';
  static const String settings = '/settings';

  // Modal/overlay routes
  static const String player = '/player';
  static const String details = '/details';
  static const String seriesDetails = '/series-details';
  static const String viewerSelection = '/viewer-selection';

  /// All main tab routes in sidebar/tab order.
  static const List<String> mainRoutes = [
    home,
    search,
    liveTv,
    vod,
    series,
    dvr,
    requests,
    settings,
  ];

  /// Human-readable labels for main routes.
  static const Map<String, String> routeLabels = {
    home: 'Home',
    search: 'Search',
    liveTv: 'Live TV',
    vod: 'Movies',
    series: 'Series',
    dvr: 'DVR',
    requests: 'Requests',
    settings: 'Settings',
  };
}
