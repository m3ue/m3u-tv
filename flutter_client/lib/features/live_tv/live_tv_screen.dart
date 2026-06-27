import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

enum _ViewMode { list, logoGrid, epgGrid }

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
    this.onSidebarActivate,
  });

  final List<Channel> channels;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final FavoritesService favoritesService;
  final EpgService epgService;
  final void Function(Channel) onChannelSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  static const _favoritesCategoryId = '__FAVORITES__';
  String? _selectedCategory;
  String _query = '';
  Set<int> _favoriteIds = {};
  final Map<int, EpgCurrentNext?> _epgMap = {};
  _ViewMode _viewMode = _ViewMode.list;

  @override
  void initState() {
    super.initState();
    unawaited(_initCategory());
  }

  Future<void> _initCategory() async {
    final lastCat = await widget.favoritesService.getLastCategory();
    final lastMode = await widget.favoritesService.getLastViewMode();
    if (mounted) {
      setState(() {
        _selectedCategory = lastCat;
        if (lastMode != null) {
          _viewMode = _ViewMode.values.firstWhere(
            (m) => m.name == lastMode,
            orElse: () => _ViewMode.list,
          );
        }
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
    final selectedCategory = _selectedCategory;
    final categoryFiltered =
        selectedCategory == null || selectedCategory.isEmpty
        ? widget.channels
        : selectedCategory == _favoritesCategoryId
        ? widget.channels.where((channel) => _favoriteIds.contains(channel.id))
        : widget.channels.where(
            (channel) => channel.categoryId == selectedCategory,
          );
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return categoryFiltered.toList(growable: false);
    }
    return categoryFiltered
        .where(
          (channel) => channel.name.toLowerCase().contains(normalizedQuery),
        )
        .toList(growable: false);
  }

  List<CategoryTabData> get _categoryTabs {
    return [
      const CategoryTabData(id: '', name: 'All Channels'),
      const CategoryTabData(id: _favoritesCategoryId, name: '★ Favorites'),
      ...widget.categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  void _loadEpgForChannels(List<Channel> channels) {
    for (final channel in channels) {
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
          _buildSearchField(),
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
                : switch (_viewMode) {
                    _ViewMode.epgGrid => _buildEpgGrid(filtered),
                    _ViewMode.logoGrid => _buildGridView(filtered),
                    _ViewMode.list => _buildListView(filtered),
                  },
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
        hintText: 'Search live TV...',
        onChanged: (value) => setState(() => _query = value),
      ),
    );
  }

  Widget _buildCategoryBar() {
    return ScrollableCategoryBar(
      tabs: _categoryTabs,
      selectedId: _selectedCategory ?? '',
      onSelected: (id) => setState(() => _selectedCategory = id),
      leading: IconButton(
        icon: Icon(switch (_viewMode) {
          _ViewMode.list => Icons.grid_view,
          _ViewMode.logoGrid => Icons.view_list,
          _ViewMode.epgGrid => Icons.list,
        }),
        onPressed: () {
          final next = switch (_viewMode) {
            _ViewMode.list => _ViewMode.logoGrid,
            _ViewMode.logoGrid => _ViewMode.epgGrid,
            _ViewMode.epgGrid => _ViewMode.list,
          };
          setState(() => _viewMode = next);
          unawaited(widget.favoritesService.setLastViewMode(next.name));
        },
        tooltip: switch (_viewMode) {
          _ViewMode.list => 'Logo grid',
          _ViewMode.logoGrid => 'EPG grid',
          _ViewMode.epgGrid => 'List view',
        },
      ),
    );
  }

  Widget _buildListView(List<Channel> channels) {
    return DpadRegion(
      memoryKey: 'live-tv/list',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ScrollbarListView(
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          final epg = _epgMap[channel.id];
          final isFav = _favoriteIds.contains(channel.id);
          return _ChannelRow(
            channel: channel,
            epg: epg,
            isFavorite: isFav,
            autofocus: index == 0,
            onTap: () => widget.onChannelSelect(channel),
            onLongPress: () async {
              await widget.favoritesService.toggle(channel.id);
              await _loadFavorites();
            },
          );
        },
      ),
    );
  }

  Widget _buildEpgGrid(List<Channel> channels) {
    return DpadRegion(
      memoryKey: 'live-tv/epg',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: TimelineEpgView(
        channels: channels,
        epgService: widget.epgService,
        onChannelSelect: widget.onChannelSelect,
      ),
    );
  }

  Widget _buildGridView(List<Channel> channels) {
    return DpadRegion(
      memoryKey: 'live-tv/grid',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ScrollbarGridView(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisExtent: 120,
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
            autofocus: index == 0,
            onTap: () => widget.onChannelSelect(channel),
            onLongPress: () async {
              await widget.favoritesService.toggle(channel.id);
              await _loadFavorites();
            },
          );
        },
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    this.epg,
    required this.isFavorite,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final EpgCurrentNext? epg;
  final bool isFavorite;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DpadInkWell(
        autofocus: autofocus,
        onTap: onTap,
        onLongTap: onLongPress,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Channel logo
                ResilientMediaImage(
                  imageUrl: channel.logoUrl,
                  fallbackIcon: Icons.tv,
                  width: MediaBrowsingMetrics.logoSize,
                  height: MediaBrowsingMetrics.logoSize,
                  fit: BoxFit.contain,
                ),
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
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        LinearProgressIndicator(
                          value: epg!.progress,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(
                            colorScheme.primary,
                          ),
                        ),
                      ] else
                        Text(
                          'No program info',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
                    child: Icon(
                      Icons.star,
                      color: colorScheme.tertiary,
                      size: 20,
                    ),
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
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                        ),
                        Text(
                          epg!.next!.title,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
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
            ), // Row
          ), // inner Padding
        ), // SizedBox
      ), // DpadInkWell
    ); // outer Padding
  }
}

class _ChannelGridItem extends StatelessWidget {
  const _ChannelGridItem({
    required this.channel,
    required this.isFavorite,
    required this.autofocus,
    required this.onTap,
    required this.onLongPress,
  });

  final Channel channel;
  final bool isFavorite;
  final bool autofocus;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      onLongTap: onLongPress,
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ResilientMediaImage(
            imageUrl: channel.logoUrl,
            fallbackIcon: Icons.tv,
            width: MediaBrowsingMetrics.logoSize,
            height: MediaBrowsingMetrics.logoSize,
            fit: BoxFit.contain,
          ),
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
    );
  }
}
