import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
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
  });

  final List<VodItem> vodItems;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(VodItem) onVodSelect;

  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  static const double _minPosterCardWidth = 120;
  static const int _desktopPosterColumns = 5;

  String? _selectedCategory;
  String _query = '';

  List<VodItem> get _filteredItems {
    final selectedCategory = _selectedCategory;
    final categoryFiltered =
        selectedCategory == null || selectedCategory.isEmpty
        ? widget.vodItems
        : widget.vodItems.where((item) => item.categoryId == selectedCategory);
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
        final columnCount =
            ((availableWidth + MediaBrowsingMetrics.itemGap) /
                    (_minPosterCardWidth + MediaBrowsingMetrics.itemGap))
                .floor()
                .clamp(1, _desktopPosterColumns);

        return ScrollbarGridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: 0.6,
            mainAxisSpacing: MediaBrowsingMetrics.itemGap,
            crossAxisSpacing: MediaBrowsingMetrics.itemGap,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _VodCard(item: item, onTap: () => widget.onVodSelect(item));
          },
        );
      },
    );
  }
}

class _VodCard extends StatelessWidget {
  const _VodCard({required this.item, required this.onTap});

  final VodItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
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
        ),
      ),
    );
  }
}
