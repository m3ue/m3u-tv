import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
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

  String? _selectedCategory;
  String _query = '';
  Set<int> _favoriteIds = {};
  VodSortOption _sortOption = VodSortOption.defaultOrder;

  /// Cached copy of [ViewSettingsService.rememberVodSort] so we only read it
  /// when opening the sort dialog (not per sort change). Refreshed every
  /// time the dialog opens so flipping the Settings toggle in another tab
  /// is honored on next open.
  bool _rememberVodSort = false;
  final FocusScopeNode _gridFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
    unawaited(_loadSortPreference());
  }

  @override
  void dispose() {
    _gridFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final service = widget.favoritesService;
    if (service == null) return;
    final ids = await service.all();
    if (mounted) setState(() => _favoriteIds = ids);
  }

  /// Restores the persisted VOD sort only when the user has opted in via
  /// Settings → View → Filter Persistence. Otherwise we leave
  /// [VodSortOption.defaultOrder] in place — matching the no-key-set case
  /// for users who have never opened the dialog or don't want their choice
  /// to survive a relaunch.
  Future<void> _loadSortPreference() async {
    final service = ref.read(viewSettingsServiceProvider);
    final remember = await service.rememberVodSort();
    if (!mounted) return;
    setState(() => _rememberVodSort = remember);
    if (!remember) return;
    final option = await service.vodSortOption();
    if (!mounted) return;
    setState(() => _sortOption = option);
  }

  List<VodItem> _filteredItems(List<VodItem> vodItems) {
    final selectedCategory = _selectedCategory;
    final Iterable<VodItem> categoryFiltered;
    if (selectedCategory == _kFavoritesCategoryId) {
      categoryFiltered = vodItems.where(
        (item) => _favoriteIds.contains(item.id),
      );
    } else if (selectedCategory == null || selectedCategory.isEmpty) {
      categoryFiltered = vodItems;
    } else {
      categoryFiltered = vodItems.where(
        (item) => item.categoryId == selectedCategory,
      );
    }
    final normalizedQuery = _query.trim().toLowerCase();
    final Iterable<VodItem> queryFiltered;
    if (normalizedQuery.isEmpty) {
      queryFiltered = categoryFiltered;
    } else {
      queryFiltered = categoryFiltered.where(
        (item) => item.name.toLowerCase().contains(normalizedQuery),
      );
    }
    // Append the sort step rather than mutating the existing
    // category/query branches - keeps those regression-tested paths byte
    // identical to pre-#235 and makes a future sort dimension purely
    // additive.
    final list = queryFiltered.toList(growable: false);
    switch (_sortOption) {
      case VodSortOption.defaultOrder:
        return list;
      case VodSortOption.ratingDesc:
        // Unrated items sink below every rated one - keeps the grid
        // visually anchored on the best-rated movies and treats missing
        // data as "less informative" rather than "zero stars".
        list.sort(
          (a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1),
        );
        return list;
    }
  }

  List<CategoryTabData> _tabs(List<Category> categories) {
    final l = AppLocalizations.of(context);
    return [
      CategoryTabData(id: '', name: l.vodAllMovies),
      if (_favoriteIds.isNotEmpty)
        CategoryTabData(id: _kFavoritesCategoryId, name: l.liveTvFavorites),
      ...categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  Map<String, int> _categoryCounts(List<VodItem> vodItems) {
    final counts = <String, int>{'': vodItems.length};
    if (_favoriteIds.isNotEmpty) {
      counts[_kFavoritesCategoryId] = _favoriteIds.length;
    }
    for (final item in vodItems) {
      final categoryId = item.categoryId;
      if (categoryId == null) continue;
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }
    return counts;
  }

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
      onQueryChanged: (value) => setState(() => _query = value),
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
      onCategoryLongPress: () => _showSortMenu(context),
    );
    final content = Expanded(
      child: isLoading
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
                return _VodCard(
                  item: item,
                  autofocus: index == 0,
                  isFavorite: _favoriteIds.contains(item.id),
                  onTap: () => widget.onVodSelect(item),
                  onLongTap: widget.favoritesService == null
                      ? null
                      : () async {
                          await widget.favoritesService!.toggle(item.id);
                          await _loadFavorites();
                        },
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

  /// Opens the "Sort Movies By" modal. Refreshes the cached
  /// [ViewSettingsService.rememberVodSort] value up front so the
  /// post-dialog persistence decision uses the latest setting, then applies
  /// the user's selection (or no-op on dismiss). On selecting a new
  /// option: always updates the local [_sortOption]; only writes back to
  /// the service when persistence is currently on — exactly per the
  /// plan's "read once at dialog open" discipline.
  Future<void> _showSortMenu(BuildContext context) async {
    final service = ref.read(viewSettingsServiceProvider);
    final remember = await service.rememberVodSort();
    if (!mounted) return;
    setState(() => _rememberVodSort = remember);
    if (!context.mounted) return;

    final selected = await showDialog<VodSortOption>(
      context: context,
      builder: (dialogContext) {
        final l = AppLocalizations.of(dialogContext);
        return SimpleDialog(
          title: Row(
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(l.vodSortDialogTitle)),
            ],
          ),
          children: [
            DpadRegion(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VodSortOption(
                    icon: Icons.list_alt,
                    label: l.vodSortDefault,
                    isActive: _sortOption == VodSortOption.defaultOrder,
                    autofocus: _sortOption == VodSortOption.defaultOrder,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(VodSortOption.defaultOrder),
                  ),
                  _VodSortOption(
                    icon: Icons.star_rate,
                    label: l.vodSortRating,
                    isActive: _sortOption == VodSortOption.ratingDesc,
                    autofocus: _sortOption == VodSortOption.ratingDesc,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(VodSortOption.ratingDesc),
                  ),
                  _VodSortOption(
                    icon: Icons.close,
                    label: l.cancel,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() => _sortOption = selected);
    if (!_rememberVodSort) return;
    unawaited(
      ref.read(viewSettingsServiceProvider).setVodSortOption(selected),
    );
  }
}

class _VodSortOption extends StatelessWidget {
  const _VodSortOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  /// First option in the dialog gets autofocus; subsequent ones don't, so
  /// d-pad down naturally walks through the list.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
            if (isActive) Icon(Icons.check, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({
    required this.item,
    required this.onTap,
    this.onLongTap,
    this.isFavorite = false,
    this.autofocus = false,
  });

  final VodItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;
  final bool isFavorite;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongTap,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ResilientMediaImage(
                  imageUrl: item.logoUrl,
                  fallbackIcon: Icons.movie,
                  borderRadius: 0,
                ),
              ),
              // Title + rating
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.rating != null)
                      Text(
                        '★ ${item.rating}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFFFCC00),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (isFavorite)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
