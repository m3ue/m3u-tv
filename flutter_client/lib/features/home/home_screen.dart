import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart'
    show ValueListenable, mapEquals, setEquals;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/features/home/home_spotlight_hero.dart';
import 'package:m3u_tv/features/sports/sports_fixture_actions.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/features/sports/sports_fixture_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/home_screen_config.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/channel_grid_tile.dart';
import 'package:m3u_tv/shared/channel_sort.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_sort.dart';
import 'package:material_ui/material_ui.dart';

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCallout(message: message, variant: AppCalloutVariant.error);
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onChannelSelect,
    this.onChannelContextChanged,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    required this.onContinueWatchingMore,
    required this.onLiveTvMore,
    this.onSportsMore,
    required this.onMoviesMore,
    required this.onSeriesMore,
    required this.onRecordingsSelect,
    this.onAioStreamsSelect,
    this.onRequestsSelect,
    required this.onAioStreamsItemSelect,
    this.useSidebarLayout = false,
    this.onSidebarActivate,
    this.onHandleTopLevelBack,
    this.fetchVodInfo,
  });

  final void Function(Channel) onChannelSelect;
  final void Function(ChannelContext)? onChannelContextChanged;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;
  final VoidCallback onContinueWatchingMore;
  final VoidCallback onLiveTvMore;

  /// Opens the Sports screen from the Sports row's View All card.
  final VoidCallback? onSportsMore;

  /// Hardware Back on a page the Sports row opens over the shell.
  final bool Function()? onHandleTopLevelBack;
  final VoidCallback onMoviesMore;
  final VoidCallback onSeriesMore;
  final VoidCallback onRecordingsSelect;

  /// Open the AIOStreams and Requests screens from their opt-in Home rows.
  final VoidCallback? onAioStreamsSelect;
  final VoidCallback? onRequestsSelect;
  final void Function(AIOStreamsItem, int integrationId) onAioStreamsItemSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;

  /// Fetches `get_vod_info` for the rich Home's spotlight (movie rows only
  /// carry poster/year/rating). Null leaves movie heroes at list-level data.
  final Future<VodInfo?> Function(int vodId)? fetchVodInfo;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The home rows are previews - [MediaPreviewSection] only renders its first
  /// [MediaPreviewSection.maxVisibleItems]. Capping before the `.map` keeps a
  /// provider tick (progress, EPG, favorites) from allocating a fresh
  /// MediaPreviewItem for every entry in a multi-thousand-item VOD/Series
  /// catalog on each rebuild.
  static const int _rowItemLimit = MediaPreviewSection.maxVisibleItems;

  /// Null until read for the shown playlist: they decide what the Live row
  /// shows, so it waits for them.
  Set<int>? _favoriteChannelIds;
  Set<int> _favoriteVodIds = {};
  Set<int> _favoriteSeriesIds = {};

  /// Moves on a playlist switch, so a read of the last playlist's favorites
  /// that lands afterwards is dropped.
  int _favoritesGeneration = 0;

  late final FavoritesService _liveFavoritesService;
  late final FavoritesService _vodFavoritesService;
  late final FavoritesService _seriesFavoritesService;
  late final ViewSettingsService _viewSettings;
  late ChannelBrowseOrder _liveTvOrder;
  late MediaBrowseOrder _vodOrder;
  late MediaBrowseOrder _seriesOrder;

  /// Seeded from the cache `main.dart` fills before the first frame, so the
  /// right layout builds immediately (a Simplified-then-Rich swap flashed and
  /// remounted every row). Falls back to Simplified if nothing was cached.
  late HomeScreenStyle _style;
  late NavLayout _navLayout;
  final HomeSpotlightController _spotlight = HomeSpotlightController();
  late final HomeSpotlightEnricher _enricher = HomeSpotlightEnricher(
    fetchVodInfo: widget.fetchVodInfo,
    lookupSeries: (id) async {
      final rows = await ref
          .read(catalogRepositoryProvider)
          .activeItemsByIds<Series>(kind: kCatalogKindSeries, ids: {id});
      return rows.isEmpty ? null : rows.first;
    },
  );

  // Startup focus hand-off to Continue Watching: see
  // [_onContinueWatchingShown].
  final FocusNode _homeNode = FocusNode(
    debugLabel: 'home',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final FocusNode _continueWatchingNode = FocusNode(
    debugLabel: 'home-continue-watching',
    canRequestFocus: false,
    skipTraversal: true,
  );
  FocusNode? _initialFocus;
  bool _canClaimInitialFocus = true;

  /// Whether each catalog row found anything once loaded; empty rows hide,
  /// and Home says so when every source of rows came up empty.
  final Map<_CatalogRow, bool> _catalogRowHasItems = {};

  /// The same for server rows, by row id.
  final Map<String, bool> _customRowHasItems = {};

  /// Each Home section's rows, so a server change rebuilds Home.
  Map<String, List<HomeRowSpec>> _homeRows = const {};

  /// The rows are keyed to the shown playlist, so a switch starts them over
  /// (loading, not the last playlist's items).
  late String? _shownPlaylistKey;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    _viewSettings = ref.read(viewSettingsServiceProvider);
    _shownPlaylistKey = ref.read(shownPlaylistKeyProvider);
    _style = _viewSettings.homeScreenStyleCached ?? HomeScreenStyle.rich;
    _navLayout = _viewSettings.navLayoutSync;
    _homeRows = _readHomeRows();
    _liveTvOrder = _viewSettings.liveTvBrowseOrder;
    _vodOrder = _viewSettings.vodBrowseOrder;
    _seriesOrder = _viewSettings.seriesBrowseOrder;
    _viewSettings.addListener(_onViewSettingsChanged);
    unawaited(_loadStyle());
    _liveFavoritesService = ref.read(liveFavoritesServiceProvider);
    _vodFavoritesService = ref.read(vodFavoritesServiceProvider);
    _seriesFavoritesService = ref.read(seriesFavoritesServiceProvider);
    _liveFavoritesService.addListener(_onChannelFavoritesChanged);
    _vodFavoritesService.addListener(_onMediaFavoritesChanged);
    _seriesFavoritesService.addListener(_onMediaFavoritesChanged);
    unawaited(_loadFavorites());
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _homeNode.dispose();
    _continueWatchingNode.dispose();
    _viewSettings.removeListener(_onViewSettingsChanged);
    _liveFavoritesService.removeListener(_onChannelFavoritesChanged);
    _vodFavoritesService.removeListener(_onMediaFavoritesChanged);
    _seriesFavoritesService.removeListener(_onMediaFavoritesChanged);
    _spotlight.dispose();
    super.dispose();
  }

  Map<String, List<HomeRowSpec>> _readHomeRows() => {
    for (final route in NavLayout.customizableRoutes)
      route: _viewSettings.homeRowsFor(route),
  };

  void _onViewSettingsChanged() {
    unawaited(_loadStyle());
    final layout = _viewSettings.navLayoutSync;
    final homeRows = _readHomeRows();
    final rowsChanged = !mapEquals(
      homeRows.map((route, rows) => MapEntry(route, Object.hashAll(rows))),
      _homeRows.map((route, rows) => MapEntry(route, Object.hashAll(rows))),
    );
    if (rowsChanged ||
        layout != _navLayout ||
        _liveTvOrder != _viewSettings.liveTvBrowseOrder ||
        _vodOrder != _viewSettings.vodBrowseOrder ||
        _seriesOrder != _viewSettings.seriesBrowseOrder) {
      setState(() {
        _homeRows = homeRows;
        _navLayout = layout;
        _liveTvOrder = _viewSettings.liveTvBrowseOrder;
        _vodOrder = _viewSettings.vodBrowseOrder;
        _seriesOrder = _viewSettings.seriesBrowseOrder;
      });
    }
  }

  /// Continue Watching re-syncs with the server after launch and can drop
  /// entries. A focused card that is rebuilt in place with another entry
  /// re-announces itself (see MediaPreviewCard), but one that disappears
  /// outright takes focus with it, leaving the spotlight on an item that is
  /// gone. Put focus back on the row (or the page) so both recover.
  void _onContinueWatchingChanged() {
    if (_spotlight.value == null || _style != HomeScreenStyle.rich) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _spotlight.value;
      final fromContinueWatching =
          target is ProgressSpotlightTarget ||
          target?.key == 'static:continue-watching-more';
      if (!fromContinueWatching) return;
      // An entry removed while the hero shows it (e.g. tapped and found to
      // be gone) must not stay on screen - with a pointer tap focus may not
      // have moved at all, so nothing else would replace it.
      if (target is ProgressSpotlightTarget &&
          !ref
              .read(progressListProvider)
              .any((p) => ProgressSpotlightTarget(p).key == target.key)) {
        _spotlight.forget(target.key);
      }
      final primary = FocusManager.instance.primaryFocus;
      // Only when focus was actually lost - never pull it back from the
      // sidebar or anywhere else the user has moved to.
      final focusLost = primary == null || primary is FocusScopeNode;
      if (!focusLost) return;
      final next =
          _continueWatchingNode.traversalDescendants.firstOrNull ??
          _homeNode.traversalDescendants.firstOrNull;
      next?.requestFocus();
    });
  }

  /// Remembers the first card Home's autofocus landed on.
  /// Only needed until that first target is known (or the hand-off is off
  /// the table), so it unregisters itself.
  void _onPrimaryFocusChanged() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && primary.ancestors.contains(_homeNode)) {
      _initialFocus = primary;
      _stopWatchingInitialFocus();
    }
  }

  void _stopWatchingInitialFocus() =>
      FocusManager.instance.removeListener(_onPrimaryFocusChanged);

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_canClaimInitialFocus) {
      _canClaimInitialFocus = false;
      _stopWatchingInitialFocus();
    }
    // The keyboard/remote wins over a hover still waiting to land.
    _spotlight.cancelHover();
    return false;
  }

  /// Continue Watching resolves asynchronously (a catalog lookup, and the
  /// progress list itself can arrive from the server after launch), so a
  /// lower row's first card has usually autofocused by the time its cards
  /// exist - and autofocus never steals focus that is already placed. When
  /// its cards first appear, hand focus up to them, but only while focus is
  /// still on that initial autofocus target and no key has been pressed, so
  /// it never pulls focus away from someone already navigating.
  void _onContinueWatchingShown() {
    if (!_canClaimInitialFocus) return;
    _canClaimInitialFocus = false;
    _stopWatchingInitialFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      // No recorded target means the Continue Watching cards' own autofocus
      // already applies (nothing else had focus) or focus is elsewhere.
      if (_initialFocus == null || primary != _initialFocus) return;
      final first = _continueWatchingNode.traversalDescendants.firstOrNull;
      if (first == null || first == primary) return;
      first.requestFocus();
    });
  }

  Future<void> _loadStyle() async {
    final style = await _viewSettings.homeScreenStyle();
    if (!mounted || style == _style) return;
    // The rows remount under the new layout; without this the hero would
    // describe whatever was focused before the switch until focus moves.
    _spotlight.reset();
    setState(() => _style = style);
  }

  void _onChannelFavoritesChanged() {
    unawaited(_loadChannelFavorites());
  }

  Future<void> _loadChannelFavorites() async {
    final generation = _favoritesGeneration;
    Set<int> ids;
    try {
      ids = await _liveFavoritesService.all();
    } on Object catch (error) {
      // The Live row waits on these; show the whole lineup instead.
      debugPrint('Home: could not read favorite channels: $error');
      ids = const <int>{};
    }
    if (!mounted || generation != _favoritesGeneration) return;
    final current = _favoriteChannelIds;
    // Same ids, same Set: the Live row refetches when it gets a new one.
    if (current != null && setEquals(current, ids)) return;
    setState(() => _favoriteChannelIds = ids);
  }

  /// Movie/series favorites change outside Home too: a detail page, a server
  /// sync, or a switch to another playlist.
  void _onMediaFavoritesChanged() => unawaited(_loadMediaFavorites());

  Future<void> _loadFavorites() async {
    await _loadChannelFavorites();
    await _loadMediaFavorites();
  }

  Future<void> _loadMediaFavorites() async {
    final generation = _favoritesGeneration;
    final vod = await _vodFavoritesService.all();
    if (!mounted || generation != _favoritesGeneration) return;
    if (!setEquals(vod, _favoriteVodIds)) {
      setState(() => _favoriteVodIds = vod);
    }
    final series = await _seriesFavoritesService.all();
    if (!mounted || generation != _favoritesGeneration) return;
    if (!setEquals(series, _favoriteSeriesIds)) {
      setState(() => _favoriteSeriesIds = series);
    }
  }

  void _onCatalogRowLoaded(_CatalogRow row, bool hasItems) {
    if (_catalogRowHasItems[row] == hasItems) return;
    setState(() => _catalogRowHasItems[row] = hasItems);
  }

  void _onCustomRowLoaded(String rowId, bool hasItems) {
    if (_customRowHasItems[rowId] == hasItems) return;
    setState(() => _customRowHasItems[rowId] = hasItems);
  }

  /// Whether a section's rows have all come up empty.
  bool _sectionHasNothing(String route) =>
      _rowHasNothing(route) &&
      (_homeRows[route] ?? const <HomeRowSpec>[]).every(
        (row) => row.isBuiltIn || _customRowHasItems[row.id] == false,
      );

  /// Whether a turned-on row has come up with nothing to show. The entry-point
  /// rows always show their card when their feature is there.
  bool _rowHasNothing(String route) => switch (route) {
    RouteNames.liveTv => _catalogRowHasItems[_CatalogRow.live] == false,
    RouteNames.sports => _catalogRowHasItems[_CatalogRow.sports] == false,
    RouteNames.vod => _catalogRowHasItems[_CatalogRow.movies] == false,
    RouteNames.series => _catalogRowHasItems[_CatalogRow.series] == false,
    RouteNames.dvr => !ref.watch(hasDvrFeatureProvider),
    RouteNames.aiostreams => !ref.watch(hasAioStreamsProvider),
    RouteNames.requests => !ref.watch(hasRequestsFeatureProvider),
    _ => true,
  };

  /// One Home row: [row] is the section's built-in row or a server row.
  Widget _buildRow(
    String route,
    HomeRowSpec row,
    String? playlistKey,
    HomeSpotlightController? spotlight,
  ) {
    final custom = row.isBuiltIn ? null : row;
    // A row of a kind its section doesn't draw is skipped.
    if (custom != null &&
        custom.kind !=
            (route == RouteNames.sports
                ? HomeRowKind.sportsFixtures
                : HomeRowKind.category)) {
      return const SizedBox.shrink();
    }
    ValueChanged<bool> loaded(_CatalogRow catalogRow) => custom == null
        ? (hasItems) => _onCatalogRowLoaded(catalogRow, hasItems)
        : (hasItems) => _onCustomRowLoaded(custom.id, hasItems);
    return switch (route) {
      RouteNames.liveTv => _LiveRow(
        key: ValueKey(('live', playlistKey, row.id)),
        custom: custom,
        favoriteChannelIds: _favoriteChannelIds,
        order: _liveTvOrder,
        onChannelSelect: widget.onChannelSelect,
        onChannelContextChanged: widget.onChannelContextChanged,
        onToggleFavorite: (channel) => _liveFavoritesService.toggle(channel.id),
        rowItemLimit: _rowItemLimit,
        onViewAll: widget.onLiveTvMore,
        onLoaded: loaded(_CatalogRow.live),
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.sports => _SportsRow(
        key: ValueKey(('sports', playlistKey, row.id)),
        custom: custom,
        onChannelSelect: widget.onChannelSelect,
        onViewAll: widget.onSportsMore,
        onBack: widget.onHandleTopLevelBack,
        rowItemLimit: _rowItemLimit,
        hiddenFromNav: !_navLayout.showsInNav(RouteNames.sports),
        onLoaded: loaded(_CatalogRow.sports),
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.vod => _MoviesRow(
        key: ValueKey(('movies', playlistKey, row.id)),
        custom: custom,
        favoriteVodIds: _favoriteVodIds,
        order: _vodOrder,
        onVodSelect: widget.onVodSelect,
        onToggleFavorite: (item) => _vodFavoritesService.toggle(item.id),
        rowItemLimit: _rowItemLimit,
        onViewAll: widget.onMoviesMore,
        onLoaded: loaded(_CatalogRow.movies),
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.series => _SeriesRow(
        key: ValueKey(('series', playlistKey, row.id)),
        custom: custom,
        favoriteSeriesIds: _favoriteSeriesIds,
        order: _seriesOrder,
        onSeriesSelect: widget.onSeriesSelect,
        onToggleFavorite: (series) => _seriesFavoritesService.toggle(series.id),
        rowItemLimit: _rowItemLimit,
        onViewAll: widget.onSeriesMore,
        onLoaded: loaded(_CatalogRow.series),
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.dvr => _RecordingsRow(
        key: const ValueKey('dvr'),
        onRecordingsSelect: widget.onRecordingsSelect,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.aiostreams => _AioStreamsRow(
        key: const ValueKey('aiostreams'),
        onSelect: widget.onAioStreamsSelect,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      RouteNames.requests => _RequestsRow(
        key: const ValueKey('requests'),
        onSelect: widget.onRequestsSelect,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final sourceError = ref.watch(sourceErrorProvider);
    final playlistKey = ref.watch(shownPlaylistKeyProvider);
    if (playlistKey != _shownPlaylistKey) {
      _shownPlaylistKey = playlistKey;
      _catalogRowHasItems.clear();
      _customRowHasItems.clear();
      // The rows start over below, and must not mark (or, for Live, pick)
      // channels by the last playlist's favorites while these are re-read.
      _favoritesGeneration += 1;
      _favoriteChannelIds = null;
      _favoriteVodIds = const <int>{};
      _favoriteSeriesIds = const <int>{};
      unawaited(_loadFavorites());
      // The hero still describes the last playlist's card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _spotlight.reset();
      });
    }

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).appNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    // The spotlight follows D-pad/mouse focus, so touch layouts always get
    // the simplified Home.
    final rich = widget.useSidebarLayout && _style == HomeScreenStyle.rich;
    final spotlight = rich ? _spotlight : null;
    final hasNoProgress = ref.watch(
      progressListProvider.select((progress) => progress.isEmpty),
    );
    final homeRowRoutes = _navLayout.homeRowRoutes;
    final nothingToShow =
        hasNoProgress && homeRowRoutes.every(_sectionHasNothing);
    final rows = <Widget>[
      Focus(
        focusNode: _continueWatchingNode,
        child: _ContinueWatchingRow(
          key: ValueKey(('continue-watching', playlistKey)),
          onProgressSelect: widget.onProgressSelect,
          onContinueWatchingMore: widget.onContinueWatchingMore,
          useSidebarLayout: widget.useSidebarLayout,
          onSidebarActivate: widget.onSidebarActivate,
          spotlight: spotlight,
          onItemsShown: _onContinueWatchingShown,
          onItemsChanged: _onContinueWatchingChanged,
        ),
      ),
      for (final route in homeRowRoutes)
        for (final row in _homeRows[route] ?? const [HomeRowSpec.builtIn])
          _buildRow(route, row, playlistKey, spotlight),
      if (nothingToShow)
        // Nothing else here can take focus. Without this a remote has no way
        // to reach the sidebar on some platforms, as key events only travel up
        // from whatever holds focus.
        Focus(
          autofocus: widget.useSidebarLayout,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              widget.onSidebarActivate?.call();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: MediaBrowsingMetrics.pagePadding * 2,
            ),
            child: Center(
              child: Text(
                AppLocalizations.of(context).homeNothingToShow,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
    ];
    final hasSourceError = sourceError != null && sourceError.isNotEmpty;

    if (rich) {
      return Scaffold(
        body: Focus(
          focusNode: _homeNode,
          child: RichHomeLayout(
            controller: _spotlight,
            enricher: _enricher,
            header: hasSourceError
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MediaBrowsingMetrics.pagePadding,
                    ),
                    child: _OfflineBanner(message: sourceError),
                  )
                : null,
            rows: rows,
          ),
        ),
      );
    }

    return Scaffold(
      body: Focus(
        focusNode: _homeNode,
        child: ListView(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          children: [
            if (hasSourceError) ...[
              _OfflineBanner(message: sourceError),
              const SizedBox(height: MediaBrowsingMetrics.pagePadding),
            ],
            ...rows,
          ],
        ),
      ),
    );
  }
}

// Each Home row below is its own [ConsumerWidget] scoped to exactly the
// provider(s) it renders. AppStateController is a single ChangeNotifier with
// dozens of notifyListeners() call sites (EPG sweep chunks, DVR polling,
// progress saves, ...); before this split, _HomeScreenState.build() watched
// all of those providers directly, so ANY one of them firing rebuilt every
// row's whole widget tree. Splitting into per-row ConsumerWidgets means a
// provider tick only rebuilds the row(s) that actually watch it - e.g. an
// EPG update no longer touches the Movies/Series rows.

enum _CatalogRow { live, sports, movies, series }

/// The spotlight id of a row's View all card, apart for each server row.
String _viewAllId(String section, HomeRowSpec? custom) =>
    custom == null ? '$section-view-all' : '$section-view-all-${custom.id}';

/// A row's [MediaPreviewSection.viewAll] card. In the rich layout the hero
/// describes [target], where it leads.
MediaPreviewItem _viewAllItem(
  AppLocalizations l, {
  required StaticSpotlightTarget target,
  required VoidCallback onTap,
  required HomeSpotlightController? spotlight,
  String? subtitle,
}) => MediaPreviewItem(
  title: l.homeViewAll,
  subtitle: subtitle,
  fallbackIcon: Icons.arrow_forward,
  onTap: onTap,
  onFocused: spotlight == null ? null : () => spotlight.select(target),
  onHoverChanged: spotlight?.hoverHandler(target),
);

class _ContinueWatchingRow extends ConsumerStatefulWidget {
  const _ContinueWatchingRow({
    super.key,
    required this.onProgressSelect,
    required this.onContinueWatchingMore,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
    this.onItemsShown,
    this.onItemsChanged,
  });

  final void Function(Progress) onProgressSelect;
  final VoidCallback onContinueWatchingMore;

  /// Fires when the row first goes from no cards to some.
  final VoidCallback? onItemsShown;

  /// Fires after every change to the row's cards.
  final VoidCallback? onItemsChanged;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_ContinueWatchingRow> createState() =>
      _ContinueWatchingRowState();
}

class _ContinueWatchingRowState extends ConsumerState<_ContinueWatchingRow> {
  List<Progress>? _resolvedFor;
  List<MediaPreviewItem> _items = const [];

  @override
  void didUpdateWidget(_ContinueWatchingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The resolved cards capture the focus hook; re-resolve on a Home style
    // switch so they pick up (or drop) the spotlight.
    if (oldWidget.spotlight != widget.spotlight) _resolvedFor = null;
  }

  void _resolve(List<Progress> progressList) {
    _resolvedFor = progressList;
    final spotlight = widget.spotlight;
    unawaited(
      continueWatchingPreviewItemsFromRepo(
        context,
        progressList: progressList,
        repo: ref.read(catalogRepositoryProvider),
        onProgressSelect: widget.onProgressSelect,
        onProgressFocused: spotlight == null
            ? null
            : (progress) => spotlight.select(ProgressSpotlightTarget(progress)),
        onProgressHoverChanged: spotlight == null
            ? null
            : (progress) =>
                  spotlight.hoverHandler(ProgressSpotlightTarget(progress)),
      ).then((items) {
        if (mounted && identical(_resolvedFor, progressList)) {
          final wasEmpty = _items.isEmpty;
          setState(() => _items = items);
          if (wasEmpty && items.isNotEmpty) widget.onItemsShown?.call();
          widget.onItemsChanged?.call();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progressList = ref.watch(progressListProvider);
    if (!identical(progressList, _resolvedFor)) _resolve(progressList);

    if (_items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    const continueWatchingRowLimit = 4;
    final continueWatchingOverflow = _items.length - continueWatchingRowLimit;
    final spotlight = widget.spotlight;
    final seeAllTarget = StaticSpotlightTarget(
      id: 'continue-watching-more',
      title: l.homeContinueWatching,
      description: l.homeContinueWatchingMoreCount(continueWatchingOverflow),
    );
    return MediaPreviewSection(
      title: l.homeContinueWatching,
      titleIcon: Icons.history,
      emptyLabel: l.homeNoContinueWatching,
      items: _items.take(continueWatchingRowLimit).toList(growable: false),
      viewAll: continueWatchingOverflow > 0
          ? _viewAllItem(
              l,
              target: seeAllTarget,
              subtitle: l.homeContinueWatchingMoreCount(
                continueWatchingOverflow,
              ),
              onTap: widget.onContinueWatchingMore,
              spotlight: spotlight,
            )
          : null,
      landscapeStyle: true,
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

class _LiveRow extends ConsumerStatefulWidget {
  const _LiveRow({
    super.key,
    this.custom,
    required this.favoriteChannelIds,
    required this.order,
    required this.onChannelSelect,
    required this.onChannelContextChanged,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.onViewAll,
    required this.onLoaded,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  /// A server row showing one category, or null for the built-in row.
  final HomeRowSpec? custom;

  /// Null until known; the row waits for them before loading.
  final Set<int>? favoriteChannelIds;
  final ChannelBrowseOrder order;
  final void Function(Channel) onChannelSelect;
  final void Function(ChannelContext)? onChannelContextChanged;
  final Future<void> Function(Channel) onToggleFavorite;
  final int rowItemLimit;
  final VoidCallback onViewAll;

  /// Whether the row found any channels, after each load.
  final ValueChanged<bool> onLoaded;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_LiveRow> createState() => _LiveRowState();
}

/// The row's channels and what tapping one hands the player: favorites when
/// any are in the lineup, otherwise the whole lineup.
typedef _LiveRowSlice = ({
  List<Channel> rowChannels,
  bool showsFavorites,
  ChannelContext Function(int index) contextAt,
});

class _LiveRowState extends ConsumerState<_LiveRow> {
  // The row is read from the catalog, refetched when the catalog reloads (a
  // new category list), the favorites change, or Live TV is re-sorted.
  (List<Category>, Set<int>, int, ChannelBrowseOrder)? _fetchedFor;
  _LiveRowSlice? _windowSlice;

  void _fetch(
    List<Category> catalog,
    Set<int> favorites,
    CatalogRepository repo,
  ) {
    final order = widget.order;
    final key = (catalog, favorites, widget.rowItemLimit, order);
    _fetchedFor = key;
    unawaited(() async {
      final sort = catalogSortForChannels(order.sort);
      final categoryId = widget.custom?.categoryId;
      var query = categoryId == null
          ? LiveChannelQuery(ids: favorites, sort: sort)
          : LiveChannelQuery(categoryId: categoryId, sort: sort);
      var channels = const <Channel>[];
      var showsFavorites = false;
      var length = 0;
      try {
        // With Favorites First off, Live TV doesn't lead with them, so
        // neither does its row. A category row always shows its category.
        if (categoryId != null) {
          channels = await query.page(repo, 0, widget.rowItemLimit);
        } else if (order.favoritesFirst && favorites.isNotEmpty) {
          channels = await query.page(repo, 0, widget.rowItemLimit);
        }
        showsFavorites = categoryId == null && channels.isNotEmpty;
        if (categoryId == null && !showsFavorites) {
          query = LiveChannelQuery(sort: sort);
          channels = await query.page(repo, 0, widget.rowItemLimit);
        }
        length = await query.count(repo);
      } on Object catch (error) {
        // Hide the row rather than leave its placeholder up; the next
        // catalog load tries again.
        debugPrint('Home: could not read channels: $error');
        channels = const <Channel>[];
        showsFavorites = false;
      }
      if (!mounted || _fetchedFor != key) return;
      setState(() {
        _windowSlice = (
          rowChannels: channels,
          showsFavorites: showsFavorites,
          contextAt: (index) => CatalogChannelContext(
            repository: repo,
            query: query,
            length: length,
            indexHint: index,
          ),
        );
      });
      widget.onLoaded(channels.isNotEmpty);
    }());
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(liveCategoriesProvider);
    final favorites = widget.favoriteChannelIds;
    if (favorites != null &&
        _fetchedFor !=
            (catalog, favorites, widget.rowItemLimit, widget.order)) {
      _fetch(catalog, favorites, ref.read(catalogRepositoryProvider));
    }
    final isLoading = _windowSlice == null;
    final slice =
        _windowSlice ??
        (
          rowChannels: const <Channel>[],
          showsFavorites: false,
          contextAt: (_) => ListChannelContext.empty,
        );
    final rowChannels = slice.rowChannels;
    if (!isLoading && rowChannels.isEmpty) return const SizedBox.shrink();
    // Until it loads, guess the row shows favorites when there are any.
    final custom = widget.custom;
    final showsFavorites = isLoading
        ? custom == null &&
              widget.order.favoritesFirst &&
              (favorites?.isNotEmpty ?? false)
        : slice.showsFavorites;
    final spotlight = widget.spotlight;
    final epgService = ref.watch(epgServiceProvider);
    final l = AppLocalizations.of(context);
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);

    // Same card as Live TV's Grid view (logo, progress, current program and
    // its start/end), so the Home row matches that view.
    return MediaPreviewSection.builder(
      title:
          custom?.title ??
          (showsFavorites ? l.homeFavoriteChannels : l.navLiveTv),
      titleIcon: showsFavorites ? Icons.star : Icons.live_tv,
      emptyLabel: l.homeNoLiveTv,
      isLoading: isLoading,
      viewAll: _viewAllItem(
        l,
        target: StaticSpotlightTarget(
          id: _viewAllId('live', custom),
          title: l.navLiveTv,
          description: l.homeBrowseLiveTv,
        ),
        onTap: widget.onViewAll,
        spotlight: spotlight,
      ),
      itemCount: rowChannels.length,
      baseCardWidth: ChannelGridTile.baseWidth,
      baseCardHeight: ChannelGridTile.baseHeight,
      itemBuilder: (context, index, cardSize, {required autofocus}) {
        final channel = rowChannels[index];
        final tile = SizedBox.fromSize(
          size: cardSize,
          child: ChannelGridTile(
            channel: channel,
            epg: epgService.lookupForChannel(channel),
            isFavorite: favorites?.contains(channel.id) ?? false,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: autofocus,
            onTap: () {
              widget.onChannelContextChanged?.call(slice.contextAt(index));
              widget.onChannelSelect(channel);
            },
            onLongPress: () => widget.onToggleFavorite(channel),
          ),
        );
        if (spotlight == null) return tile;
        final target = ChannelSpotlightTarget(channel);
        return PreviewFocusAnchor(
          onFocused: () => spotlight.select(target),
          onHoverChanged: spotlight.hoverHandler(target),
          contentKey: channel.id,
          child: tile,
        );
      },
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

/// Today's games from the viewer's leagues that a channel carries: live
/// ones and followed teams first, then by kickoff. Hidden while Sports is
/// off or nothing is watchable. Selecting a game plays it the way the
/// Sports screen does.
class _SportsRow extends ConsumerStatefulWidget {
  const _SportsRow({
    super.key,
    this.custom,
    required this.onChannelSelect,
    required this.onViewAll,
    required this.onBack,
    required this.rowItemLimit,
    required this.hiddenFromNav,
    required this.onLoaded,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  /// A server row with its own leagues and days, or null for the built-in
  /// row (the viewer's own leagues, today).
  final HomeRowSpec? custom;
  final void Function(Channel) onChannelSelect;
  final VoidCallback? onViewAll;
  final bool Function()? onBack;
  final int rowItemLimit;
  final bool hiddenFromNav;
  final ValueChanged<bool> onLoaded;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_SportsRow> createState() => _SportsRowState();
}

class _SportsRowState extends ConsumerState<_SportsRow> {
  /// How often scores refresh while a game is on (and Home is shown).
  static const Duration _refreshInterval = Duration(minutes: 2);

  /// Null until the first load.
  List<SportsFixture>? _fixtures;
  bool? _reportedHasItems;
  Map<String, List<SportsChannelMatch>> _matches = const {};
  String? _matchesFor;
  DateTime? _matchesFetchedAt;
  String? _loadedFor;
  int _generation = 0;
  Timer? _refreshTimer;
  ValueListenable<TickerModeData>? _tickerMode;

  bool get _isVisible => _tickerMode?.value.enabled ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hidden branches (another tab shown) run with tickers off: no polling
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_onVisibilityChanged);
      _tickerMode = notifier..addListener(_onVisibilityChanged);
    }
  }

  @override
  void dispose() {
    _tickerMode?.removeListener(_onVisibilityChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reportLoaded(bool hasItems) {
    if (_reportedHasItems == hasItems) return;
    _reportedHasItems = hasItems;
    // Reported from build, where the parent can't be rebuilt yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onLoaded(hasItems);
    });
  }

  void _onVisibilityChanged() {
    if (_isVisible) {
      _loadedFor = null;
      if (mounted) setState(() {});
    } else {
      _refreshTimer?.cancel();
    }
  }

  Future<void> _load(
    SportsCapability capability,
    List<SportsLeague> leagues,
    Set<String> followed,
  ) async {
    final generation = ++_generation;
    _refreshTimer?.cancel();
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final from = midnight.toUtc();
    final to = DateTime(
      midnight.year,
      midnight.month,
      midnight.day + (widget.custom?.sportsDays ?? 1),
    ).toUtc();
    final rowLimit = min(
      widget.custom?.limit ?? widget.rowItemLimit,
      widget.rowItemLimit,
    );
    try {
      final service = ref.read(sportsServiceProvider);
      final fixtures = await service.fixtures(
        capability: capability,
        leagues: leagues,
        from: from,
        to: to,
      );
      final watchable = fixtures.where(isSportsFixtureWatchable).toList();
      // Score refreshes reuse the channels until they're due again
      final matchesFor = [
        from.millisecondsSinceEpoch,
        for (final league in leagues) league.id,
      ].join(',');
      final fetchedAt = _matchesFetchedAt;
      var matches = _matches;
      if (watchable.isNotEmpty &&
          (matchesFor != _matchesFor ||
              fetchedAt == null ||
              DateTime.now().difference(fetchedAt) >= kSportsChannelsMaxAge)) {
        matches = await loadSportsChannelMatches(
          service: service,
          repository: ref.read(catalogRepositoryProvider),
          capability: capability,
          leagues: leagues,
          from: from,
          to: to,
        );
        if (!mounted || generation != _generation) return;
        _matchesFor = matchesFor;
        _matchesFetchedAt = DateTime.now();
      }
      if (!mounted || generation != _generation) return;
      int rank(SportsFixture fixture) {
        final isFollowed = fixture.displayOrder.any(
          (side) => followed.contains(side.team.key),
        );
        final isLive = fixture.state == SportsFixtureState.live;
        return (isLive ? 0 : 2) + (isFollowed ? 0 : 1);
      }

      final shown =
          watchable
              .where((fixture) => matches[fixture.key]?.isNotEmpty ?? false)
              .toList()
            ..sort((a, b) {
              final byRank = rank(a).compareTo(rank(b));
              return byRank != 0 ? byRank : a.start.compareTo(b.start);
            });
      setState(() {
        _fixtures = shown.take(rowLimit).toList();
        _matches = matches;
      });
      // A refreshed score reaches the hero if its game is the one shown
      final spotlight = widget.spotlight;
      final current = spotlight?.value;
      if (current is SportsSpotlightTarget) {
        for (final fixture in shown) {
          final target = _targetFor(fixture);
          if (target.key == current.key) spotlight!.select(target);
        }
      }
    } on Object catch (error) {
      debugPrint('[Sports] Home row load failed: $error');
      if (!mounted || generation != _generation) return;
      setState(() => _fixtures ??= const []);
    }
    if (!mounted || !_isVisible) return;
    final soon = DateTime.now().toUtc().add(const Duration(hours: 1));
    final active = (_fixtures ?? const <SportsFixture>[]).any(
      (fixture) =>
          fixture.state == SportsFixtureState.live ||
          fixture.start.isBefore(soon),
    );
    if (active) {
      _refreshTimer = Timer(_refreshInterval, () {
        if (mounted) setState(() => _loadedFor = null);
      });
    }
  }

  SportsSpotlightTarget _targetFor(SportsFixture fixture) =>
      SportsSpotlightTarget(
        fixture,
        channelNames: [
          for (final match
              in _matches[fixture.key] ?? const <SportsChannelMatch>[])
            match.channel.name,
        ],
      );

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(sportsCapabilityProvider);
    if (capability == null) {
      _reportLoaded(false);
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final spotlight = widget.spotlight;
    final onViewAll = widget.onViewAll;
    // With Sports off the nav this row is the only way in, so it stays as a
    // plain entry card on days it has no games to list.
    final custom = widget.custom;
    Widget entryCardOrNothing(String subtitle) {
      // A server row is extra: it never stands in for the section.
      final keepsEntry =
          custom == null && widget.hiddenFromNav && onViewAll != null;
      _reportLoaded(keepsEntry);
      if (!keepsEntry) return const SizedBox.shrink();
      return _EntryPointRow(
        targetId: 'sports-entry',
        title: l.navSports,
        icon: Icons.stadium_rounded,
        cardTitle: l.navSports,
        subtitle: subtitle,
        onTap: onViewAll,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      );
    }

    final settings = ref.watch(sportsSettingsProvider);
    final leagues = custom == null
        ? settings.enabledLeagues(capability.leagues)
        : [
            for (final league in capability.leagues)
              if (custom.leagueIds.contains(league.id)) league,
          ];
    if (leagues.isEmpty) return entryCardOrNothing(l.homeBrowseSports);
    final followed = settings.followedTeamKeys;
    final signature = [
      for (final league in leagues) league.id,
      '|',
      ...followed,
      '|',
      custom?.sportsDays ?? 1,
      custom?.limit ?? '',
    ].join(',');
    if (_isVisible && signature != _loadedFor) {
      _loadedFor = signature;
      unawaited(_load(capability, leagues, followed));
    }

    final fixtures = _fixtures;
    final isLoading = fixtures == null;
    if (fixtures != null) {
      if (fixtures.isEmpty) return entryCardOrNothing(l.sportsNoGames);
      _reportLoaded(true);
    }
    final rowFixtures = fixtures ?? const <SportsFixture>[];
    return MediaPreviewSection.builder(
      title: custom?.title ?? l.navSports,
      titleIcon: Icons.stadium_rounded,
      emptyLabel: l.sportsNoGames,
      isLoading: isLoading,
      viewAll: onViewAll == null
          ? null
          : _viewAllItem(
              l,
              target: StaticSpotlightTarget(
                id: _viewAllId('sports', custom),
                title: l.navSports,
                description: l.homeBrowseSports,
              ),
              onTap: onViewAll,
              spotlight: spotlight,
            ),
      itemCount: rowFixtures.length,
      baseCardWidth: SportsFixtureTile.baseWidth,
      baseCardHeight: SportsFixtureTile.baseHeight,
      itemBuilder: (context, index, cardSize, {required autofocus}) {
        final fixture = rowFixtures[index];
        final matches = _matches[fixture.key] ?? const <SportsChannelMatch>[];
        final tile = SizedBox.fromSize(
          size: cardSize,
          child: SportsFixtureTile(
            fixture: fixture,
            channelCount: matches.length,
            autofocus: autofocus,
            onTap: () => unawaited(
              openSportsFixture(
                context,
                fixture: fixture,
                matches: matches,
                onChannelSelect: widget.onChannelSelect,
                onBack: widget.onBack,
              ),
            ),
            onLongTap: () => unawaited(
              openSportsFixtureDetails(
                context,
                fixture: fixture,
                matches: matches,
                onChannelSelect: widget.onChannelSelect,
                onBack: widget.onBack,
              ),
            ),
          ),
        );
        if (spotlight == null) return tile;
        final target = _targetFor(fixture);
        return PreviewFocusAnchor(
          onFocused: () => spotlight.select(target),
          onHoverChanged: spotlight.hoverHandler(target),
          contentKey: target.key,
          child: tile,
        );
      },
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

class _MoviesRow extends ConsumerStatefulWidget {
  const _MoviesRow({
    super.key,
    this.custom,
    required this.favoriteVodIds,
    required this.order,
    required this.onVodSelect,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.onViewAll,
    required this.onLoaded,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  /// A server row showing one category, or null for the built-in row.
  final HomeRowSpec? custom;
  final Set<int> favoriteVodIds;
  final MediaBrowseOrder order;
  final void Function(VodItem) onVodSelect;
  final Future<void> Function(VodItem) onToggleFavorite;
  final int rowItemLimit;
  final VoidCallback onViewAll;

  /// Whether the row found anything, after each load.
  final ValueChanged<bool> onLoaded;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_MoviesRow> createState() => _MoviesRowState();
}

class _MoviesRowState extends ConsumerState<_MoviesRow> {
  (List<Category>, MediaBrowseOrder, Set<int>, String?, int)? _fetchedFor;

  /// Null until the first page loads. A reload keeps these on screen.
  List<VodItem>? _items;

  (List<Category>, MediaBrowseOrder, Set<int>, String?, int) _fetchKey(
    List<Category> categories,
    int dvrContentRevision,
  ) => (
    categories,
    widget.order,
    // Only a change in the favorites the order leads with moves the row.
    widget.order.favoritesFirst ? widget.favoriteVodIds : const <int>{},
    widget.custom?.categoryId,
    // A DVR recording added or deleted rewrites the catalog under the row.
    dvrContentRevision,
  );

  void _fetch(
    List<Category> categories,
    int dvrContentRevision,
    CatalogRepository repo,
  ) {
    final key = _fetchKey(categories, dvrContentRevision);
    _fetchedFor = key;
    unawaited(() async {
      List<VodItem> items;
      try {
        items = await repo.pageActiveItems<VodItem>(
          kind: kCatalogKindVod,
          categoryId: key.$4,
          sort: catalogSortFor(key.$2.sort),
          favoritesFirst: key.$3,
          offset: 0,
          limit: widget.rowItemLimit,
        );
      } on Object catch (error) {
        // Hide the row rather than leave its placeholder up; the next
        // catalog load tries again.
        debugPrint('Home: could not read movies: $error');
        items = const <VodItem>[];
      }
      if (mounted && _fetchedFor == key) {
        setState(() => _items = items);
        widget.onLoaded(items.isNotEmpty);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vodCategoriesProvider);
    final dvrContentRevision = ref.watch(dvrContentRevisionProvider);
    if (_fetchKey(categories, dvrContentRevision) != _fetchedFor) {
      _fetch(
        categories,
        dvrContentRevision,
        ref.read(catalogRepositoryProvider),
      );
    }
    final items = _items;
    if (items != null && items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final spotlight = widget.spotlight;
    final custom = widget.custom;
    return MediaPreviewSection(
      title: custom?.title ?? l.navVod,
      titleIcon: Icons.movie,
      emptyLabel: l.homeNoMovies,
      posterStyle: true,
      isLoading: items == null,
      viewAll: _viewAllItem(
        l,
        target: StaticSpotlightTarget(
          id: _viewAllId('movies', custom),
          title: l.navVod,
          description: l.homeBrowseMovies,
        ),
        onTap: widget.onViewAll,
        spotlight: spotlight,
      ),
      items: (items ?? const [])
          .map(
            (item) => MediaPreviewItem(
              title: item.name,
              imageUrl: item.logoUrl,
              subtitle: item.year ?? l.homeMovie,
              ratingLabel: item.rating == null
                  ? null
                  : formatRating(item.rating!),
              fallbackIcon: Icons.movie,
              fallbackTitle: item.name,
              isFavorite: widget.favoriteVodIds.contains(item.id),
              onTap: () => widget.onVodSelect(item),
              onLongTap: () => widget.onToggleFavorite(item),
              onFocused: spotlight == null
                  ? null
                  : () => spotlight.select(VodSpotlightTarget(item)),
              onHoverChanged: spotlight?.hoverHandler(VodSpotlightTarget(item)),
            ),
          )
          .toList(growable: false),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

class _SeriesRow extends ConsumerStatefulWidget {
  const _SeriesRow({
    super.key,
    this.custom,
    required this.favoriteSeriesIds,
    required this.order,
    required this.onSeriesSelect,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.onViewAll,
    required this.onLoaded,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  /// A server row showing one category, or null for the built-in row.
  final HomeRowSpec? custom;
  final Set<int> favoriteSeriesIds;
  final MediaBrowseOrder order;
  final void Function(Series) onSeriesSelect;
  final Future<void> Function(Series) onToggleFavorite;
  final int rowItemLimit;
  final VoidCallback onViewAll;

  /// Whether the row found anything, after each load.
  final ValueChanged<bool> onLoaded;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_SeriesRow> createState() => _SeriesRowState();
}

class _SeriesRowState extends ConsumerState<_SeriesRow> {
  (List<Category>, MediaBrowseOrder, Set<int>, String?, int)? _fetchedFor;

  /// Null until the first page loads. A reload keeps these on screen.
  List<Series>? _items;

  (List<Category>, MediaBrowseOrder, Set<int>, String?, int) _fetchKey(
    List<Category> categories,
    int dvrContentRevision,
  ) => (
    categories,
    widget.order,
    // Only a change in the favorites the order leads with moves the row.
    widget.order.favoritesFirst ? widget.favoriteSeriesIds : const <int>{},
    widget.custom?.categoryId,
    // A DVR recording added or deleted rewrites the catalog under the row.
    dvrContentRevision,
  );

  void _fetch(
    List<Category> categories,
    int dvrContentRevision,
    CatalogRepository repo,
  ) {
    final key = _fetchKey(categories, dvrContentRevision);
    _fetchedFor = key;
    unawaited(() async {
      List<Series> items;
      try {
        items = await repo.pageActiveItems<Series>(
          kind: kCatalogKindSeries,
          categoryId: key.$4,
          sort: catalogSortFor(key.$2.sort),
          favoritesFirst: key.$3,
          offset: 0,
          limit: widget.rowItemLimit,
        );
      } on Object catch (error) {
        // Hide the row rather than leave its placeholder up; the next
        // catalog load tries again.
        debugPrint('Home: could not read series: $error');
        items = const <Series>[];
      }
      if (mounted && _fetchedFor == key) {
        setState(() => _items = items);
        widget.onLoaded(items.isNotEmpty);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(seriesCategoriesProvider);
    final dvrContentRevision = ref.watch(dvrContentRevisionProvider);
    if (_fetchKey(categories, dvrContentRevision) != _fetchedFor) {
      _fetch(
        categories,
        dvrContentRevision,
        ref.read(catalogRepositoryProvider),
      );
    }
    final items = _items;
    if (items != null && items.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final spotlight = widget.spotlight;
    final custom = widget.custom;
    return MediaPreviewSection(
      title: custom?.title ?? l.navSeries,
      titleIcon: Icons.tv,
      emptyLabel: l.homeNoSeries,
      posterStyle: true,
      isLoading: items == null,
      viewAll: _viewAllItem(
        l,
        target: StaticSpotlightTarget(
          id: _viewAllId('series', custom),
          title: l.navSeries,
          description: l.homeBrowseSeries,
        ),
        onTap: widget.onViewAll,
        spotlight: spotlight,
      ),
      items: (items ?? const [])
          .map(
            (series) => MediaPreviewItem(
              title: series.name,
              imageUrl: series.coverUrl,
              subtitle: series.year ?? l.navSeries,
              ratingLabel: series.rating == null
                  ? null
                  : formatRating(series.rating!),
              fallbackIcon: Icons.tv,
              fallbackTitle: series.name,
              isFavorite: widget.favoriteSeriesIds.contains(series.id),
              onTap: () => widget.onSeriesSelect(series),
              onLongTap: () => widget.onToggleFavorite(series),
              onFocused: spotlight == null
                  ? null
                  : () => spotlight.select(SeriesSpotlightTarget(series)),
              onHoverChanged: spotlight?.hoverHandler(
                SeriesSpotlightTarget(series),
              ),
            ),
          )
          .toList(growable: false),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

/// A one-card row that opens a whole section: DVR, the opt-in AIOStreams and
/// Requests rows, and Sports when it's hidden from the nav with no games to
/// list.
class _EntryPointRow extends StatelessWidget {
  const _EntryPointRow({
    required this.targetId,
    required this.title,
    required this.icon,
    required this.cardTitle,
    required this.subtitle,
    required this.onTap,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final String targetId;
  final String title;
  final IconData icon;
  final String cardTitle;
  final String subtitle;
  final VoidCallback onTap;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  Widget build(BuildContext context) {
    final spotlight = this.spotlight;
    final target = StaticSpotlightTarget(
      id: targetId,
      title: cardTitle,
      description: subtitle,
    );
    return MediaPreviewSection(
      title: title,
      titleIcon: icon,
      // Never shown: the row always has its one card.
      emptyLabel: subtitle,
      items: [
        MediaPreviewItem(
          title: cardTitle,
          subtitle: subtitle,
          fallbackIcon: icon,
          onTap: onTap,
          onFocused: spotlight == null ? null : () => spotlight.select(target),
          onHoverChanged: spotlight?.hoverHandler(target),
        ),
      ],
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
    );
  }
}

class _RecordingsRow extends ConsumerWidget {
  const _RecordingsRow({
    super.key,
    required this.onRecordingsSelect,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final VoidCallback onRecordingsSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDvrFeature = ref.watch(hasDvrFeatureProvider);
    if (!hasDvrFeature) return const SizedBox.shrink();
    final dvrRecordings = ref.watch(dvrRecordingsProvider);
    final l = AppLocalizations.of(context);
    return _EntryPointRow(
      targetId: 'dvr',
      title: l.navDvr,
      icon: Icons.video_library,
      cardTitle: l.homeDvrRecordings,
      subtitle: dvrRecordings.isEmpty
          ? l.homeDvrRecordingsBrowse
          : l.dvrStorageRecordingCount(dvrRecordings.length),
      onTap: onRecordingsSelect,
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
      spotlight: spotlight,
    );
  }
}

class _AioStreamsRow extends ConsumerWidget {
  const _AioStreamsRow({
    super.key,
    required this.onSelect,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final VoidCallback? onSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSelect = this.onSelect;
    if (onSelect == null || !ref.watch(hasAioStreamsProvider)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return _EntryPointRow(
      targetId: 'aiostreams',
      title: l.navAioStreams,
      icon: Icons.subscriptions_rounded,
      cardTitle: l.navAioStreams,
      subtitle: l.homeAioStreamsBrowse,
      onTap: onSelect,
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
      spotlight: spotlight,
    );
  }
}

class _RequestsRow extends ConsumerWidget {
  const _RequestsRow({
    super.key,
    required this.onSelect,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final VoidCallback? onSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onSelect = this.onSelect;
    if (onSelect == null || !ref.watch(hasRequestsFeatureProvider)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return _EntryPointRow(
      targetId: 'requests',
      title: l.navRequests,
      icon: Icons.playlist_add_rounded,
      cardTitle: l.navRequests,
      subtitle: l.homeRequestsBrowse,
      onTap: onSelect,
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
      spotlight: spotlight,
    );
  }
}
