import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';

/// Live TV screen with category filtering, EPG info, and favorites.
///
/// Mirrors the RN LiveTVScreen behavior:
/// - All Channels + ★ Favorites pseudo-category + real categories
/// - List view with EPG current/next info and progress bars
/// - Toggle between list and grid view modes
/// - Long-press to toggle favorites
/// - Lazy EPG loading for visible channels
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({
    super.key,
    required this.channels,
    required this.categories,
    required this.isLoading,
    required this.isConfigured,
    required this.favoritesService,
    required this.epgService,
    required this.onChannelSelect,
  });

  final List<Channel> channels;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final FavoritesService favoritesService;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  static const _favoritesCategoryId = '__FAVORITES__';
  String? _selectedCategory;
  Set<int> _favoriteIds = {};
  final Map<int, EpgCurrentNext?> _epgMap = {};
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _initCategory();
  }

  Future<void> _initCategory() async {
    final lastCat = await widget.favoritesService.getLastCategory();
    if (mounted) {
      setState(() {
        _selectedCategory = lastCat;
      });
    }
    await _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final ids = await widget.favoritesService.all();
    if (mounted) {
      setState(() {
        _favoriteIds = ids;
      });
    }
  }

  List<Channel> get _filteredChannels {
    if (_selectedCategory == null || _selectedCategory == '') {
      return widget.channels;
    }
    if (_selectedCategory == _favoritesCategoryId) {
      return widget.channels.where((c) => _favoriteIds.contains(c.id)).toList();
    }
    return widget.channels.where((c) => c.categoryId == _selectedCategory).toList();
  }

  List<_CategoryTab> get _categoryTabs {
    return [
      const _CategoryTab(id: '', name: 'All Channels'),
      const _CategoryTab(id: _favoritesCategoryId, name: '★ Favorites'),
      ...widget.categories.map((c) => _CategoryTab(id: c.id, name: c.name)),
    ];
  }

  void _loadEpgForChannels(List<Channel> channels) {
    for (final channel in channels.take(20)) {
      final result = widget.epgService.lookupForChannel(channel);
      if (result != null) {
        _epgMap[channel.id] = result;
      }
    }
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

    final filtered = _filteredChannels;
    _loadEpgForChannels(filtered);

    return Scaffold(
      body: Column(
        children: [
          // Category bar + view mode toggle
          _buildCategoryBar(),
          // Content area
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No channels available',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      )
                    : _isGridView
                        ? _buildGridView(filtered)
                        : _buildListView(filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar() {
    final tabs = _categoryTabs;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // View mode toggle
          IconButton(
            icon: Icon(_isGridView ? Icons.list : Icons.grid_view),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            tooltip: _isGridView ? 'List view' : 'Grid view',
          ),
          const SizedBox(width: 8),
          // Category tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: tabs.map((tab) {
                  final isSelected = (_selectedCategory ?? '') == tab.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: tab.name,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedCategory = tab.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<Channel> channels) {
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final epg = _epgMap[channel.id];
        final isFav = _favoriteIds.contains(channel.id);
        return _ChannelRow(
          channel: channel,
          epg: epg,
          isFavorite: isFav,
          onTap: () => widget.onChannelSelect(channel),
          onLongPress: () async {
            await widget.favoritesService.toggle(channel.id);
            await _loadFavorites();
          },
        );
      },
    );
  }

  Widget _buildGridView(List<Channel> channels) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        final isFav = _favoriteIds.contains(channel.id);
        return _ChannelGridItem(
          channel: channel,
          isFavorite: isFav,
          onTap: () => widget.onChannelSelect(channel),
          onLongPress: () async {
            await widget.favoritesService.toggle(channel.id);
            await _loadFavorites();
          },
        );
      },
    );
  }
}

class _CategoryTab {
  const _CategoryTab({required this.id, required this.name});
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
    return Focus(
      child: Material(
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
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    this.epg,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final EpgCurrentNext? epg;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.transparent),
            ),
            child: Row(
              children: [
                // Channel logo
                if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      channel.logoUrl!,
                      width: 48,
                      height: 48,
                      errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 48),
                    ),
                  )
                else
                  const Icon(Icons.tv, size: 48),
                const SizedBox(width: 14),
                // Channel info
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (epg != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          epg!.current.title,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        LinearProgressIndicator(
                          value: epg!.progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                        ),
                      ] else
                        Text(
                          'No program info',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                    ],
                  ),
                ),
                // Favorite star
                if (isFavorite)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.star, color: colorScheme.tertiary, size: 20),
                  ),
                // Next program
                if (epg?.next != null)
                  SizedBox(
                    width: 160,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'NEXT',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          epg!.next!.title,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelGridItem extends StatelessWidget {
  const _ChannelGridItem({
    required this.channel,
    required this.isFavorite,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    channel.logoUrl!,
                    width: 48,
                    height: 48,
                    errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 48),
                  ),
                )
              else
                const Icon(Icons.tv, size: 48),
              const SizedBox(height: 4),
              Text(
                channel.name,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (isFavorite)
                Icon(Icons.star, color: colorScheme.tertiary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
