/// Route name constants matching the current RN navigation structure.
///
/// Main tab/sidebar routes: Home, Search, LiveTV, VOD, Series, DVR,
/// Requests, Notifications, Settings.
/// Modal/overlay routes: Player, Details, SeriesDetails, ViewerSelection.
class RouteNames {
  RouteNames._();

  // Main tab/sidebar destinations
  static const String home = '/home';
  static const String search = '/search';
  static const String liveTv = '/live-tv';
  static const String vod = '/vod';
  static const String series = '/series';
  static const String aiostreams = '/aiostreams';
  static const String dvr = '/dvr';
  static const String requests = '/requests';
  static const String notifications = '/notifications';
  static const String settings = '/settings';

  // Modal/overlay routes
  static const String player = '/player';
  static const String details = '/details';
  static const String seriesDetails = '/series-details';
  static const String viewerSelection = '/viewer-selection';

  /// All main tab/sidebar destinations, in display order. The TV/desktop
  /// sidebar shows all of these flat (plenty of vertical room). The mobile
  /// bottom nav only has room for [mobilePrimaryCount] before it gets
  /// cramped, so it shows that many directly and collapses the rest into a
  /// "More" sheet — see `AppShellState._buildMobileLayout`.
  static const List<String> mainRoutes = [
    home,
    search,
    liveTv,
    vod,
    series,
    aiostreams,
    dvr,
    requests,
    notifications,
    settings,
  ];

  /// How many leading [mainRoutes] the mobile bottom nav shows directly.
  static const int mobilePrimaryCount = 5;

  // Nested detail route path templates
  static const String vodDetailsPath = '/vod/details/:vodId';
  static const String seriesDetailsPath = '/series/details/:seriesId';
  static const String aiostreamsDetailsPath =
      '/aiostreams/details/:integrationId/:type/:id';

  /// Builds a path to a VOD details screen for deep linking.
  static String vodDetailsFor(int vodId) => '/vod/details/$vodId';

  /// Builds a path to a series details screen for deep linking.
  static String seriesDetailsFor(int seriesId) => '/series/details/$seriesId';

  /// Builds a path to an AIOStreams item detail screen.
  static String aiostreamsDetailsFor(
    int integrationId,
    String type,
    String id,
  ) => '/aiostreams/details/$integrationId/$type/$id';

  /// Human-readable labels for main routes.
  static const Map<String, String> routeLabels = {
    home: 'Home',
    search: 'Search',
    liveTv: 'Live TV',
    vod: 'Movies',
    series: 'Series',
    aiostreams: 'Streaming',
    dvr: 'DVR',
    requests: 'Requests',
    notifications: 'Notifications',
    settings: 'Settings',
  };
}
