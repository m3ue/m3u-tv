/// Route name constants matching the current RN navigation structure.
///
/// Main tab/sidebar routes: Home, Search, LiveTV, Sports, VOD, Series, DVR,
/// Requests, Notifications, Settings.
/// Modal/overlay routes: Player, Details, SeriesDetails, ViewerSelection.
///
/// `Shows` (EPG series browse + per-show detail) is no longer a top-level
/// sidebar destination — it now lives as a nested route under `DVR` and a
/// third tab on `DvrRecordingsScreen`. Deep-link helpers under
/// [showsDetailsPath] / [showDetailsFor] therefore build paths under `/dvr`.
class RouteNames {
  RouteNames._();

  // Main tab/sidebar destinations
  static const String home = '/home';
  static const String search = '/search';
  static const String liveTv = '/live-tv';
  static const String sports = '/sports';
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
  static const String personDetails = '/person-details';

  /// All main tab/sidebar destinations, in display order. The TV/desktop
  /// sidebar shows all of these flat (plenty of vertical room). The mobile
  /// bottom nav only has room for [mobilePrimaryCount] before it gets
  /// cramped, so it shows that many directly and collapses the rest into a
  /// "More" sheet — see `AppShellState._buildMobileLayout`.
  static const List<String> mainRoutes = [
    home,
    search,
    liveTv,
    sports,
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
  static const String showsDetailsPath = 'shows/:normalizedTitle';
  static const String showDetailsPath = '/dvr/shows/:normalizedTitle';
  static const String aiostreamsDetailsPath =
      '/aiostreams/details/:integrationId/:type/:id';
  static const String aiostreamsSearchPath = '/aiostreams/search';
  static const String continueWatchingPath = '/home/continue-watching';
  static const String requestsDetailsPath =
      '/requests/details/:integrationId/:type/:externalId';

  /// Builds a path to a VOD details screen for deep linking.
  static String vodDetailsFor(int vodId) => '/vod/details/$vodId';

  /// Builds a path to a series details screen for deep linking.
  static String seriesDetailsFor(int seriesId) => '/series/details/$seriesId';

  /// Builds a path to an EPG show detail screen for a normalized title.
  /// Nested under `/dvr` because Shows now lives as a DVR sub-route and a
  /// third DVR tab, not as a standalone sidebar destination.
  static String showDetailsFor(String normalizedTitle) =>
      '/dvr/shows/$normalizedTitle';

  /// Builds a path to an AIOStreams item detail screen.
  static String aiostreamsDetailsFor(
    int integrationId,
    String type,
    String id,
  ) => '/aiostreams/details/$integrationId/$type/$id';

  /// Builds a path to a content-request search result's detail screen.
  static String requestsDetailsFor(
    int integrationId,
    String type,
    String externalId,
  ) => '/requests/details/$integrationId/$type/$externalId';

  /// Builds a path to an actor's filmography screen. At least one of
  /// [personId] (the TMDB person id, when known from `CastMember.id`) or
  /// [name] (the server's TMDB-person-search fallback) must be given -
  /// mirrors m3u-editor's own `ActorFilmography` query-param mount shape.
  ///
  /// [includeLibraryFilter] controls the All/In Library filter toggle above
  /// the filmography grid - pass `false` from AIOStreams call sites, where
  /// `FilmographyCredit.inLibrary` (resolved against the Xtream playlist's
  /// Series/VOD library) doesn't reflect AIOStreams content.
  ///
  /// [aiostreamsIntegrationId], when set, tells the filmography screen every
  /// credit is reachable via AIOStreams's own `tmdb:{id}` meta form (see
  /// `AIOStreamsService::buildMetaFromTmdb` in m3u-editor) rather than
  /// gating tap/opacity on `inLibrary`/`localId` - AIOStreams is on-demand,
  /// not library-driven, so every credit is always navigable.
  static String personDetailsFor({
    int? personId,
    String? name,
    bool includeLibraryFilter = true,
    int? aiostreamsIntegrationId,
  }) {
    return Uri(
      path: personDetails,
      queryParameters: {
        if (personId != null) 'personId': '$personId',
        if (name != null && name.isNotEmpty) 'name': name,
        if (!includeLibraryFilter) 'includeLibraryFilter': 'false',
        if (aiostreamsIntegrationId != null)
          'aiostreamsIntegrationId': '$aiostreamsIntegrationId',
      },
    ).toString();
  }

  /// Human-readable labels for main routes.
  static const Map<String, String> routeLabels = {
    home: 'Home',
    search: 'Search',
    liveTv: 'Live TV',
    sports: 'Sports',
    vod: 'Movies',
    series: 'Series',
    aiostreams: 'AIOStreams',
    dvr: 'DVR',
    requests: 'Requests',
    notifications: 'Notifications',
    settings: 'Settings',
  };
}
