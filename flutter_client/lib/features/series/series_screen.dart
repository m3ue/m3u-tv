import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Series screen with category filtering and poster grid.
///
/// Mirrors the RN SeriesDetailsScreen behavior:
/// - All Series + category tabs
/// - Grid layout with cover thumbnails and ratings
/// - Category filtering
/// - Season/episode navigation happens in SeriesDetailsScreen (separate route)
class SeriesScreen extends StatefulWidget {
  const SeriesScreen({
    super.key,
    required this.seriesList,
    required this.categories,
    required this.isLoading,
    required this.isConfigured,
    required this.onSeriesSelect,
    this.onSidebarActivate,
  });

  final List<Series> seriesList;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(Series) onSeriesSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  static const double _minPosterCardWidth = 120;
  static const int _desktopPosterColumns = 5;

  String? _selectedCategory;
  String _query = '';

  List<Series> get _filteredItems {
    final selectedCategory = _selectedCategory;
    final categoryFiltered =
        selectedCategory == null || selectedCategory.isEmpty
        ? widget.seriesList
        : widget.seriesList.where(
            (item) => item.categoryId == selectedCategory,
          );
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
                      'No series available',
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
        hintText: 'Search series...',
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildCategoryBar() {
    final tabs = [
      const CategoryTabData(id: '', name: 'All Series'),
      ...widget.categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];

    return ScrollableCategoryBar(
      tabs: tabs,
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() => _selectedCategory = id),
    );
  }

  Widget _buildGrid(List<Series> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
        final columnCount =
            ((availableWidth + MediaBrowsingMetrics.itemGap) /
                    (_minPosterCardWidth + MediaBrowsingMetrics.itemGap))
                .floor()
                .clamp(1, _desktopPosterColumns);

        return DpadRegion(
          memoryKey: 'series/grid',
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
              return _SeriesCard(
                item: item,
                autofocus: index == 0,
                onTap: () => widget.onSeriesSelect(item),
              );
            },
          ),
        );
      },
    );
  }
}

class _SeriesCard extends StatefulWidget {
  const _SeriesCard({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });

  final Series item;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    return DpadFocusable(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onSelect: widget.onTap,
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _focusNode.requestFocus();
            widget.onTap();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ResilientMediaImage(
                  imageUrl: item.coverUrl,
                  fallbackIcon: Icons.tv,
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
        ),
      ),
    );
  }
}
