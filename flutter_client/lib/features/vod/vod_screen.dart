import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/catalog_window.dart';
import 'package:m3u_tv/shared/catalog_window_grid.dart';
import 'package:m3u_tv/shared/category_browse_filter.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';

/// VOD (Movies) screen with category filtering and poster grid.
///
/// Mirrors the RN HomeScreen Movies row and MovieDetailsScreen behavior:
/// - All Movies + category tabs
/// - Grid layout with poster thumbnails and ratings
/// - Category filtering
class VodScreen extends ConsumerStatefulWidget {
  const VodScreen({
    super.key,
    required this.onVodSelect,
    required this.useSidebarLayout,
    this.favoritesService,
    this.onSidebarActivate,
    this.onEntryFocusScopeReady,
  });

  final void Function(VodItem) onVodSelect;

  /// TV/desktop (`true`): search+category render as a vertical strip beside
  /// the grid. Mobile (`false`): stacked at the top with a Filter button.
  final bool useSidebarLayout;
  final FavoritesService? favoritesService;
  final VoidCallback? onSidebarActivate;

  /// TV/desktop only: forwarded to [MediaCategoryNav.onEntryFocusScopeReady]
  /// so AppShell can always re-enter this screen's strip first when the
  /// sidebar deactivates.
  final ValueChanged<FocusScopeNode>? onEntryFocusScopeReady;

  @override
  ConsumerState<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends ConsumerState<VodScreen> {
  static const double _minPosterCardWidth = 120;
  static const double _maxPosterCardWidth = 220;
  static const _kFavoritesCategoryId = '__FAVORITES__';

  static const _searchDebounce = Duration(milliseconds: 200);

  String? _selectedCategory;
  String _query = '';
  // Lags [_query] by up to one debounce; drives the actual filtering so fast
  // typing over a large catalog does not re-scan it on every keystroke.
  String _appliedQuery = '';
  Timer? _debounce;
  Set<int> _favoriteIds = {};
  final CategoryBrowseFilter<VodItem> _filter = CategoryBrowseFilter<VodItem>(
    primaryCategoryId: (item) => item.categoryId,
    extraCategoryIds: (item) => item.categoryIds,
    name: (item) => item.name,
    id: (item) => item.id,
  );
  final FocusScopeNode _gridFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();

  /// Set when the SQLite catalog is available: the grid pages movies out of
  /// the database instead of filtering the whole in-memory list. Null on the
  /// legacy path (tests, or a database that failed to open).
  CatalogWindow<VodItem>? _window;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
    final repo = _readCatalogRepository();
    if (repo != null) {
      _window = CatalogWindow<VodItem>(
        fetchPage: (offset, limit) => _pageMovies(repo, offset, limit),
        fetchCount: () => _countMovies(repo),
      );
      unawaited(_window!.load());
    }
  }

  /// The catalog repo, or null when it (or its host provider) isn't available -
  /// e.g. a widget test that only overrides the data providers, or a database
  /// that failed to open. Either way the screen falls back to the in-memory
  /// list path.
  CatalogRepository? _readCatalogRepository() {
    try {
      return ref.read(catalogRepositoryProvider);
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gridFocusNode.dispose();
    _window?.dispose();
    super.dispose();
  }

  /// The category id passed to the repository: null for the "all movies" tab
  /// and the (in-memory-only) favorites tab, otherwise the selected category.
  String? get _repoCategoryId =>
      (_selectedCategory == null ||
          _selectedCategory!.isEmpty ||
          _selectedCategory == _kFavoritesCategoryId)
      ? null
      : _selectedCategory;

  /// Whether the current view can be served from the windowed grid. The
  /// favorites tab filters against an id set that only lives in memory, so it
  /// stays on the legacy path.
  bool get _useWindow =>
      _window != null && _selectedCategory != _kFavoritesCategoryId;

  Future<List<VodItem>> _pageMovies(
    CatalogRepository repo,
    int offset,
    int limit,
  ) => repo.pageActiveItems<VodItem>(
    kind: kCatalogKindVod,
    categoryId: _repoCategoryId,
    search: _appliedQuery.isEmpty ? null : _appliedQuery,
    offset: offset,
    limit: limit,
  );

  Future<int> _countMovies(CatalogRepository repo) => repo.countActiveItems(
    kind: kCatalogKindVod,
    categoryId: _repoCategoryId,
    search: _appliedQuery.isEmpty ? null : _appliedQuery,
  );

  void _reconfigureWindow() {
    final window = _window;
    if (window == null) return;
    final repo = _readCatalogRepository();
    if (repo == null) return;
    unawaited(
      window.configure(
        fetchPage: (offset, limit) => _pageMovies(repo, offset, limit),
        fetchCount: () => _countMovies(repo),
      ),
    );
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _applyQuery('');
      return;
    }
    // Apply the first character of a fresh query immediately; only throttle
    // subsequent keystrokes while a filtered result is already on screen.
    if (_appliedQuery.isEmpty) {
      _applyQuery(value);
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      if (mounted && value != _appliedQuery) {
        setState(() => _applyQuery(value));
      }
    });
  }

  void _applyQuery(String value) {
    _appliedQuery = value;
    _reconfigureWindow();
  }

  Future<void> _loadFavorites() async {
    final service = widget.favoritesService;
    if (service == null) return;
    final ids = await service.all();
    if (mounted) setState(() => _favoriteIds = ids);
  }

  List<VodItem> _filteredItems(List<VodItem> vodItems) => _filter.members(
    list: vodItems,
    selectedCategory: _selectedCategory,
    query: _appliedQuery,
    favoriteIds: _favoriteIds,
    favoritesCategoryId: _kFavoritesCategoryId,
  );

  List<CategoryTabData> _tabs(List<Category> categories) {
    final l = AppLocalizations.of(context);
    return [
      CategoryTabData(id: '', name: l.vodAllMovies),
      if (_favoriteIds.isNotEmpty)
        CategoryTabData(id: _kFavoritesCategoryId, name: l.liveTvFavorites),
      ...categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  Map<String, int> _categoryCounts(List<VodItem> vodItems) => {
    '': vodItems.length,
    if (_favoriteIds.isNotEmpty) _kFavoritesCategoryId: _favoriteIds.length,
    ..._filter.categoryCounts(vodItems),
  };

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final isLoading = ref.watch(isLoadingContentProvider);
    final vodItems = ref.watch(vodItemsProvider);
    final categories = ref.watch(vodCategoriesProvider);

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final l = AppLocalizations.of(context);
    final nav = MediaCategoryNav(
      key: _navKey,
      useSidebarLayout: widget.useSidebarLayout,
      query: _query,
      onQueryChanged: _onQueryChanged,
      searchHint: l.vodSearchHint,
      tabs: _tabs(categories),
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() {
        _selectedCategory = id;
        _reconfigureWindow();
      }),
      filterButtonLabel: l.mediaCategoryFilterButton,
      filterScreenTitle: l.mediaCategoryFilterScreenTitle,
      categoryCounts: _categoryCounts(vodItems),
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _gridFocusNode,
      memoryKeyPrefix: 'vod',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
    );
    final content = Expanded(
      child: _useWindow
          ? _buildWindowContent(_window!)
          : _buildListContent(vodItems, isLoading: isLoading),
    );

    return Scaffold(
      body: widget.useSidebarLayout
          ? Row(children: [nav, content])
          : Column(children: [nav, content]),
    );
  }

  Widget _buildListContent(List<VodItem> vodItems, {required bool isLoading}) {
    final filtered = _filteredItems(vodItems);
    // Only show the spinner when there is nothing to display yet. During a
    // background refresh the already-populated grid stays visible.
    if (isLoading && vodItems.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No movies available',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return _gridShell(
      builder: (columnCount) => ScrollbarGridView(
        gridDelegate: _gridDelegate(columnCount),
        itemCount: filtered.length,
        itemBuilder: (context, index) =>
            _movieCard(filtered[index], autofocus: index == 0),
      ),
    );
  }

  Widget _buildWindowContent(CatalogWindow<VodItem> window) {
    final waitingForFirstPage =
        window.isLoadingCount ||
        (window.totalCount > 0 && window.itemAt(0) == null);
    if (waitingForFirstPage) {
      return const Center(child: CircularProgressIndicator());
    }
    if (window.totalCount == 0) {
      return Center(
        child: Text(
          'No movies available',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return _gridShell(
      builder: (columnCount) => CatalogWindowGrid<VodItem>(
        window: window,
        crossAxisCount: columnCount,
        gridDelegate: _gridDelegate(columnCount),
        itemBuilder: (context, index, item) =>
            _movieCard(item, autofocus: index == 0),
        placeholderBuilder: (context, index) => const _MoviePlaceholder(),
      ),
    );
  }

  /// The `FocusScope` + `DpadRegion` wrapper both grid variants share, with the
  /// resolved column count handed to [builder].
  Widget _gridShell({required Widget Function(int columnCount) builder}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
        final columnCount = _posterColumnCount(availableWidth);
        return FocusScope(
          node: _gridFocusNode,
          child: DpadRegion(
            memoryKey: 'vod/grid',
            horizontalEdge: DpadEdgeBehavior.stop,
            onEdge: (direction) {
              if (direction != TraversalDirection.left) return;
              if (widget.useSidebarLayout) {
                _navKey.currentState?.requestFocus();
              } else {
                widget.onSidebarActivate?.call();
              }
            },
            child: builder(columnCount),
          ),
        );
      },
    );
  }

  SliverGridDelegate _gridDelegate(int columnCount) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        childAspectRatio: 0.6,
        mainAxisSpacing: MediaBrowsingMetrics.itemGap,
        crossAxisSpacing: MediaBrowsingMetrics.itemGap,
      );

  Widget _movieCard(VodItem item, {required bool autofocus}) {
    return MediaPreviewCard(
      posterStyle: true,
      keepAlive: false,
      autofocus: autofocus,
      item: MediaPreviewItem(
        title: item.name,
        imageUrl: item.logoUrl,
        subtitle: item.year,
        ratingLabel: item.rating == null ? null : '★ ${item.rating}',
        fallbackIcon: Icons.movie,
        isFavorite: _favoriteIds.contains(item.id),
        onTap: () => widget.onVodSelect(item),
        onLongTap: widget.favoritesService == null
            ? null
            : () async {
                await widget.favoritesService!.toggle(item.id);
                await _loadFavorites();
              },
      ),
    );
  }

  int _posterColumnCount(double availableWidth) {
    final minimumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (_maxPosterCardWidth + MediaBrowsingMetrics.itemGap))
            .ceil();
    final maximumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (_minPosterCardWidth + MediaBrowsingMetrics.itemGap))
            .floor();
    return minimumColumns.clamp(1, maximumColumns.clamp(1, 100));
  }
}

/// Poster-shaped skeleton for a grid slot whose row is still loading from the
/// database. Fills the cell so focus geometry and scroll extent match a real
/// [MediaPreviewCard], which lands a frame or two later.
class _MoviePlaceholder extends StatelessWidget {
  const _MoviePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
