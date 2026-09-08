import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gridFocusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _appliedQuery = '';
      return;
    }
    // Apply the first character of a fresh query immediately; only throttle
    // subsequent keystrokes while a filtered result is already on screen.
    if (_appliedQuery.isEmpty) {
      _appliedQuery = value;
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      if (mounted && value != _appliedQuery) {
        setState(() => _appliedQuery = value);
      }
    });
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

    final filtered = _filteredItems(vodItems);
    final l = AppLocalizations.of(context);
    final nav = MediaCategoryNav(
      key: _navKey,
      useSidebarLayout: widget.useSidebarLayout,
      query: _query,
      onQueryChanged: _onQueryChanged,
      searchHint: l.vodSearchHint,
      tabs: _tabs(categories),
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() => _selectedCategory = id),
      filterButtonLabel: l.mediaCategoryFilterButton,
      filterScreenTitle: l.mediaCategoryFilterScreenTitle,
      categoryCounts: _categoryCounts(vodItems),
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _gridFocusNode,
      memoryKeyPrefix: 'vod',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
    );
    final content = Expanded(
      // Only show the spinner when there is nothing to display yet. During a
      // background refresh the already-populated grid stays visible.
      child: isLoading && vodItems.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : filtered.isEmpty
          ? Center(
              child: Text(
                'No movies available',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : _buildGrid(filtered),
    );

    return Scaffold(
      body: widget.useSidebarLayout
          ? Row(children: [nav, content])
          : Column(children: [nav, content]),
    );
  }

  Widget _buildGrid(List<VodItem> items) {
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
            child: ScrollbarGridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                childAspectRatio: 0.6,
                mainAxisSpacing: MediaBrowsingMetrics.itemGap,
                crossAxisSpacing: MediaBrowsingMetrics.itemGap,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return MediaPreviewCard(
                  posterStyle: true,
                  keepAlive: false,
                  autofocus: index == 0,
                  item: MediaPreviewItem(
                    title: item.name,
                    imageUrl: item.logoUrl,
                    subtitle: item.year,
                    ratingLabel: item.rating == null
                        ? null
                        : '★ ${item.rating}',
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
              },
            ),
          ),
        );
      },
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
