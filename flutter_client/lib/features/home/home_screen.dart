import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/features/home/home_spotlight_hero.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/channel_grid_tile.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

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
    required this.onRecordingsSelect,
    required this.onAioStreamsItemSelect,
    this.useSidebarLayout = false,
    this.onSidebarActivate,
    this.fetchVodInfo,
  });

  final void Function(Channel) onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;
  final VoidCallback onContinueWatchingMore;
  final VoidCallback onRecordingsSelect;
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

  Set<int> _favoriteChannelIds = {};
  Set<int> _favoriteVodIds = {};
  Set<int> _favoriteSeriesIds = {};

  late final FavoritesService _liveFavoritesService;
  late final FavoritesService _vodFavoritesService;
  late final FavoritesService _seriesFavoritesService;
  late final ViewSettingsService _viewSettings;

  /// Seeded from the cache `main.dart` fills before the first frame, so the
  /// right layout builds immediately (a Simplified-then-Rich swap flashed and
  /// remounted every row). Falls back to Simplified if nothing was cached.
  late HomeScreenStyle _style;
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

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
    _viewSettings = ref.read(viewSettingsServiceProvider);
    _style = _viewSettings.homeScreenStyleCached ?? HomeScreenStyle.simplified;
    _viewSettings.addListener(_onViewSettingsChanged);
    unawaited(_loadStyle());
    _liveFavoritesService = ref.read(liveFavoritesServiceProvider);
    _vodFavoritesService = ref.read(vodFavoritesServiceProvider);
    _seriesFavoritesService = ref.read(seriesFavoritesServiceProvider);
    _liveFavoritesService.addListener(_onChannelFavoritesChanged);
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
    _spotlight.dispose();
    super.dispose();
  }

  void _onViewSettingsChanged() => unawaited(_loadStyle());

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
    final ids = await _liveFavoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = ids);
  }

  Future<void> _loadFavorites() async {
    final live = await _liveFavoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = live);
    final vod = await _vodFavoritesService.all();
    if (mounted) setState(() => _favoriteVodIds = vod);
    final series = await _seriesFavoritesService.all();
    if (mounted) setState(() => _favoriteSeriesIds = series);
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final sourceError = ref.watch(sourceErrorProvider);

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    final rows = <Widget>[
      Focus(
        focusNode: _continueWatchingNode,
        child: _ContinueWatchingRow(
          onProgressSelect: widget.onProgressSelect,
          onContinueWatchingMore: widget.onContinueWatchingMore,
          useSidebarLayout: widget.useSidebarLayout,
          onSidebarActivate: widget.onSidebarActivate,
          spotlight: spotlight,
          onItemsShown: _onContinueWatchingShown,
          onItemsChanged: _onContinueWatchingChanged,
        ),
      ),
      _LiveRow(
        favoriteChannelIds: _favoriteChannelIds,
        onChannelSelect: widget.onChannelSelect,
        onChannelContextChanged: widget.onChannelContextChanged,
        onToggleFavorite: (channel) async {
          await _liveFavoritesService.toggle(channel.id);
          await _loadFavorites();
        },
        rowItemLimit: _rowItemLimit,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      _MoviesRow(
        favoriteVodIds: _favoriteVodIds,
        onVodSelect: widget.onVodSelect,
        onToggleFavorite: (item) async {
          await _vodFavoritesService.toggle(item.id);
          await _loadFavorites();
        },
        rowItemLimit: _rowItemLimit,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      _SeriesRow(
        favoriteSeriesIds: _favoriteSeriesIds,
        onSeriesSelect: widget.onSeriesSelect,
        onToggleFavorite: (series) async {
          await _seriesFavoritesService.toggle(series.id);
          await _loadFavorites();
        },
        rowItemLimit: _rowItemLimit,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
      ),
      _RecordingsRow(
        onRecordingsSelect: widget.onRecordingsSelect,
        useSidebarLayout: widget.useSidebarLayout,
        onSidebarActivate: widget.onSidebarActivate,
        spotlight: spotlight,
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

class _ContinueWatchingRow extends ConsumerStatefulWidget {
  const _ContinueWatchingRow({
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
    final continueWatchingRowItems = [
      ..._items.take(continueWatchingRowLimit),
      if (continueWatchingOverflow > 0)
        MediaPreviewItem(
          title: l.homeContinueWatchingSeeAll,
          subtitle: l.homeContinueWatchingMoreCount(continueWatchingOverflow),
          fallbackIcon: Icons.history,
          onTap: widget.onContinueWatchingMore,
          onFocused: spotlight == null
              ? null
              : () => spotlight.select(seeAllTarget),
          onHoverChanged: spotlight?.hoverHandler(seeAllTarget),
        ),
    ];
    return MediaPreviewSection(
      title: l.homeContinueWatching,
      titleIcon: Icons.history,
      emptyLabel: l.homeNoContinueWatching,
      items: continueWatchingRowItems,
      landscapeStyle: true,
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
  }
}

class _LiveRow extends ConsumerWidget {
  const _LiveRow({
    required this.favoriteChannelIds,
    required this.onChannelSelect,
    required this.onChannelContextChanged,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final Set<int> favoriteChannelIds;
  final void Function(Channel) onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final Future<void> Function(Channel) onToggleFavorite;
  final int rowItemLimit;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(liveChannelsProvider);
    final spotlight = this.spotlight;
    final epgService = ref.watch(epgServiceProvider);
    final l = AppLocalizations.of(context);
    final favoriteChannels = channels
        .where((channel) => favoriteChannelIds.contains(channel.id))
        .toList(growable: false);
    final liveSectionChannels = favoriteChannels.isEmpty
        ? channels
        : favoriteChannels;
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);
    final rowChannels = liveSectionChannels
        .take(rowItemLimit)
        .toList(growable: false);

    // Same card as Live TV's Grid view (logo, progress, current program and
    // its start/end), so the Home row matches that view.
    return MediaPreviewSection.builder(
      title: favoriteChannels.isEmpty ? l.navLiveTv : l.homeFavoriteChannels,
      titleIcon: favoriteChannels.isEmpty ? Icons.live_tv : Icons.star,
      emptyLabel: l.homeNoLiveTv,
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
            isFavorite: favoriteChannelIds.contains(channel.id),
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: autofocus,
            onTap: () {
              onChannelContextChanged?.call(liveSectionChannels);
              onChannelSelect(channel);
            },
            onLongPress: () => onToggleFavorite(channel),
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
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
    );
  }
}

class _MoviesRow extends ConsumerStatefulWidget {
  const _MoviesRow({
    required this.favoriteVodIds,
    required this.onVodSelect,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final Set<int> favoriteVodIds;
  final void Function(VodItem) onVodSelect;
  final Future<void> Function(VodItem) onToggleFavorite;
  final int rowItemLimit;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_MoviesRow> createState() => _MoviesRowState();
}

class _MoviesRowState extends ConsumerState<_MoviesRow> {
  List<Category>? _fetchedFor;
  List<VodItem> _items = const [];

  void _fetch(List<Category> categories, CatalogRepository repo) {
    _fetchedFor = categories;
    unawaited(
      repo
          .pageActiveItems<VodItem>(
            kind: kCatalogKindVod,
            offset: 0,
            limit: widget.rowItemLimit,
          )
          .then((items) {
            if (mounted && identical(_fetchedFor, categories)) {
              setState(() => _items = items);
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(vodCategoriesProvider);
    if (!identical(categories, _fetchedFor)) {
      _fetch(categories, ref.read(catalogRepositoryProvider));
    }
    final l = AppLocalizations.of(context);
    final spotlight = widget.spotlight;
    return MediaPreviewSection(
      title: l.navVod,
      titleIcon: Icons.movie,
      emptyLabel: l.homeNoMovies,
      posterStyle: true,
      items: _items
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
    required this.favoriteSeriesIds,
    required this.onSeriesSelect,
    required this.onToggleFavorite,
    required this.rowItemLimit,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.spotlight,
  });

  final Set<int> favoriteSeriesIds;
  final void Function(Series) onSeriesSelect;
  final Future<void> Function(Series) onToggleFavorite;
  final int rowItemLimit;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final HomeSpotlightController? spotlight;

  @override
  ConsumerState<_SeriesRow> createState() => _SeriesRowState();
}

class _SeriesRowState extends ConsumerState<_SeriesRow> {
  List<Category>? _fetchedFor;
  List<Series> _items = const [];

  void _fetch(List<Category> categories, CatalogRepository repo) {
    _fetchedFor = categories;
    unawaited(
      repo
          .pageActiveItems<Series>(
            kind: kCatalogKindSeries,
            offset: 0,
            limit: widget.rowItemLimit,
          )
          .then((items) {
            if (mounted && identical(_fetchedFor, categories)) {
              setState(() => _items = items);
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(seriesCategoriesProvider);
    if (!identical(categories, _fetchedFor)) {
      _fetch(categories, ref.read(catalogRepositoryProvider));
    }
    final l = AppLocalizations.of(context);
    final spotlight = widget.spotlight;
    return MediaPreviewSection(
      title: l.navSeries,
      titleIcon: Icons.tv,
      emptyLabel: l.homeNoSeries,
      posterStyle: true,
      items: _items
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

class _RecordingsRow extends ConsumerWidget {
  const _RecordingsRow({
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
    final spotlight = this.spotlight;
    final l = AppLocalizations.of(context);
    final subtitle = dvrRecordings.isEmpty
        ? l.homeDvrRecordingsBrowse
        : l.dvrStorageRecordingCount(dvrRecordings.length);
    final dvrTarget = StaticSpotlightTarget(
      id: 'dvr',
      title: l.homeDvrRecordings,
      description: subtitle,
    );
    return MediaPreviewSection(
      title: l.navDvr,
      titleIcon: Icons.video_library,
      emptyLabel: l.dvrNoRecordings,
      items: [
        MediaPreviewItem(
          title: l.homeDvrRecordings,
          subtitle: subtitle,
          fallbackIcon: Icons.video_library,
          onTap: onRecordingsSelect,
          onFocused: spotlight == null
              ? null
              : () => spotlight.select(dvrTarget),
          onHoverChanged: spotlight?.hoverHandler(dvrTarget),
        ),
      ],
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
    );
  }
}
