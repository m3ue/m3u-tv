import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';

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
    return widget.seriesList.where((s) => s.categoryId == _selectedCategory).toList();
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
      const _SeriesCategoryTab(id: '', name: 'All Series'),
      ...widget.categories.map((c) => _SeriesCategoryTab(id: c.id, name: c.name)),
    ];

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = (_selectedCategory ?? '') == tab.id;
                return _CategoryChip(
                  label: tab.name,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedCategory = tab.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<Series> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
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

class _SeriesCategoryTab {
  const _SeriesCategoryTab({required this.id, required this.name});
  final String id;
  final String name;
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: isSelected
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.item,
    required this.onTap,
  });

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
              // Cover image
              Expanded(
                child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                    ? Image.network(
                        item.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 48),
                      )
                    : const Icon(Icons.tv, size: 48),
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