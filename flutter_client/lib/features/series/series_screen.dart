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
  });

  final List<Series> seriesList;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(Series) onSeriesSelect;

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  String? _selectedCategory;

  List<Series> get _filteredItems {
    if (_selectedCategory == null || _selectedCategory == '') {
      return widget.seriesList;
    }
    return widget.seriesList
        .where((s) => s.categoryId == _selectedCategory)
        .toList();
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
    return ScrollbarGridView(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.6,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _SeriesCard(
          item: item,
          onTap: () => widget.onSeriesSelect(item),
        );
      },
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.item, required this.onTap});

  final Series item;
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
