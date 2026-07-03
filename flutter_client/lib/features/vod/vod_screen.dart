import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// VOD (Movies) screen with category filtering and poster grid.
///
/// Mirrors the RN HomeScreen Movies row and MovieDetailsScreen behavior:
/// - All Movies + category tabs
/// - Grid layout with poster thumbnails and ratings
/// - Category filtering
class VodScreen extends StatefulWidget {
  const VodScreen({
    super.key,
    required this.vodItems,
    required this.categories,
    required this.isLoading,
    required this.isConfigured,
    required this.onVodSelect,
    this.favoritesService,
    this.onSidebarActivate,
  });

  final List<VodItem> vodItems;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(VodItem) onVodSelect;
  final FavoritesService? favoritesService;
  final VoidCallback? onSidebarActivate;

  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  static const double _minPosterCardWidth = 120;
  static const double _maxPosterCardWidth = 220;
  static const _kFavoritesCategoryId = '__FAVORITES__';

  String? _selectedCategory;
  String _query = '';
  Set<int> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
  }

  Future<void> _loadFavorites() async {
    final service = widget.favoritesService;
    if (service == null) return;
    final ids = await service.all();
    if (mounted) setState(() => _favoriteIds = ids);
  }

  List<VodItem> get _filteredItems {
    final selectedCategory = _selectedCategory;
    final Iterable<VodItem> categoryFiltered;
    if (selectedCategory == _kFavoritesCategoryId) {
      categoryFiltered = widget.vodItems.where(
        (item) => _favoriteIds.contains(item.id),
      );
    } else if (selectedCategory == null || selectedCategory.isEmpty) {
      categoryFiltered = widget.vodItems;
    } else {
      categoryFiltered = widget.vodItems.where(
        (item) => item.categoryId == selectedCategory,
      );
    }
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return categoryFiltered.toList(growable: false);
    }
    return categoryFiltered
        .where((item) => item.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final filtered = _filteredItems;

    return Scaffold(
      body: Column(
        children: [
          _buildSearchField(),
          // Category bar
          _buildCategoryBar(),
          // Content area
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      'No movies available',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : _buildGrid(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        0,
      ),
      child: InlineMediaSearchField(
        query: _query,
        hintText: 'Search movies...',
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildCategoryBar() {
    final tabs = [
      const CategoryTabData(id: '', name: 'All Movies'),
      if (_favoriteIds.isNotEmpty)
        const CategoryTabData(id: _kFavoritesCategoryId, name: '★ Favorites'),
      ...widget.categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];

    return ScrollableCategoryBar(
      tabs: tabs,
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() => _selectedCategory = id),
    );
  }

  Widget _buildGrid(List<VodItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
        final columnCount = _posterColumnCount(availableWidth);

        return DpadRegion(
          memoryKey: 'vod/grid',
          horizontalEdge: DpadEdgeBehavior.stop,
          onEdge: (direction) {
            if (direction == TraversalDirection.left) {
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
              child: Icon(
                Icons.star,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }
}
