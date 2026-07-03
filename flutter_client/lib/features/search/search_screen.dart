import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Search screen with client-side filtering across Live TV, Movies, and Series.
///
/// Mirrors the RN SearchScreen behavior:
/// - Case-insensitive name.includes(query) filtering
/// - All / Live TV / Movies / Series tabs
/// - Real-time filtering as user types
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.channels,
    required this.vodItems,
    required this.seriesList,
    required this.isConfigured,
    required this.onChannelSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    this.onSidebarActivate,
  });

  final List<Channel> channels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';

  static const _tabs = ['All', 'Live TV', 'Movies', 'Series'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _normalizedQuery => _query.trim().toLowerCase();

  bool get _hasQuery => _normalizedQuery.isNotEmpty;

  List<Channel> get _filteredChannels => _hasQuery
      ? widget.channels
            .where(
              (channel) =>
                  channel.name.toLowerCase().contains(_normalizedQuery),
            )
            .toList(growable: false)
      : const [];

  List<VodItem> get _filteredVodItems => _hasQuery
      ? widget.vodItems
            .where((item) => item.name.toLowerCase().contains(_normalizedQuery))
            .toList(growable: false)
      : const [];

  List<Series> get _filteredSeriesList => _hasQuery
      ? widget.seriesList
            .where(
              (series) => series.name.toLowerCase().contains(_normalizedQuery),
            )
            .toList(growable: false)
      : const [];

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

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
            child: InlineMediaSearchField(
              query: _query,
              hintText: 'Search live TV, movies, and series...',
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          DpadTabBar(controller: _tabController, tabs: _tabs),
          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(),
                _buildLiveTvTab(),
                _buildMoviesTab(),
                _buildSeriesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTab() {
    if (!_hasQuery) return _buildPromptState();

    final channels = _filteredChannels;
    final vodItems = _filteredVodItems;
    final seriesList = _filteredSeriesList;

    if (channels.isEmpty && vodItems.isEmpty && seriesList.isEmpty) {
      return _buildEmptyState('No results found');
    }

    return DpadRegion(
      memoryKey: 'search/all',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ListView(
        children: [
          if (channels.isNotEmpty) ...[
            const _SectionHeader(title: 'Live TV'),
            ...channels.map(
              (c) => _ChannelListTile(
                channel: c,
                onTap: () => widget.onChannelSelect(c),
              ),
            ),
          ],
          if (vodItems.isNotEmpty) ...[
            const _SectionHeader(title: 'Movies'),
            ...vodItems.map(
              (v) => _VodListTile(item: v, onTap: () => widget.onVodSelect(v)),
            ),
          ],
          if (seriesList.isNotEmpty) ...[
            const _SectionHeader(title: 'Series'),
            ...seriesList.map(
              (s) => _SeriesListTile(
                item: s,
                onTap: () => widget.onSeriesSelect(s),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveTvTab() {
    if (!_hasQuery) return _buildPromptState();

    final channels = _filteredChannels;
    if (channels.isEmpty) {
      return _buildEmptyState('No results found');
    }
    return DpadRegion(
      memoryKey: 'search/live-tv',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ListView.builder(
        itemCount: channels.length,
        itemBuilder: (context, index) => _ChannelListTile(
          channel: channels[index],
          autofocus: index == 0,
          onTap: () => widget.onChannelSelect(channels[index]),
        ),
      ),
    );
  }

  Widget _buildMoviesTab() {
    if (!_hasQuery) return _buildPromptState();

    final vodItems = _filteredVodItems;
    if (vodItems.isEmpty) {
      return _buildEmptyState('No results found');
    }
    return DpadRegion(
      memoryKey: 'search/movies',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ListView.builder(
        itemCount: vodItems.length,
        itemBuilder: (context, index) => _VodListTile(
          item: vodItems[index],
          autofocus: index == 0,
          onTap: () => widget.onVodSelect(vodItems[index]),
        ),
      ),
    );
  }

  Widget _buildSeriesTab() {
    if (!_hasQuery) return _buildPromptState();

    final seriesList = _filteredSeriesList;
    if (seriesList.isEmpty) {
      return _buildEmptyState('No results found');
    }
    return DpadRegion(
      memoryKey: 'search/series',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ListView.builder(
        itemCount: seriesList.length,
        itemBuilder: (context, index) => _SeriesListTile(
          item: seriesList[index],
          autofocus: index == 0,
          onTap: () => widget.onSeriesSelect(seriesList[index]),
        ),
      ),
    );
  }

  Widget _buildPromptState() => _buildEmptyState('Type to search');

  Widget _buildEmptyState(String label) {
    return Center(
      child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ChannelListTile extends StatelessWidget {
  const _ChannelListTile({
    required this.channel,
    required this.onTap,
    this.autofocus = false,
  });
  final Channel channel;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onTap,
      child: ListTile(
        leading: ResilientMediaImage(
          imageUrl: channel.logoUrl,
          fallbackIcon: Icons.tv,
          width: MediaBrowsingMetrics.logoSize,
          height: MediaBrowsingMetrics.logoSize,
          fit: BoxFit.contain,
        ),
        title: Text(channel.name),
        onTap: onTap,
      ),
    );
  }
}

class _VodListTile extends StatelessWidget {
  const _VodListTile({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });
  final VodItem item;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onTap,
      child: ListTile(
        leading: ResilientMediaImage(
          imageUrl: item.logoUrl,
          fallbackIcon: Icons.movie,
          width: MediaBrowsingMetrics.logoSize,
          height: MediaBrowsingMetrics.logoSize,
          fit: BoxFit.contain,
        ),
        title: Text(item.name),
        subtitle: item.rating != null ? Text('★ ${item.rating}') : null,
        onTap: onTap,
      ),
    );
  }
}

class _SeriesListTile extends StatelessWidget {
  const _SeriesListTile({
    required this.item,
    required this.onTap,
    this.autofocus = false,
  });
  final Series item;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return DpadFocusable(
      autofocus: autofocus,
      onSelect: onTap,
      child: ListTile(
        leading: ResilientMediaImage(
          imageUrl: item.coverUrl,
          fallbackIcon: Icons.tv,
          width: MediaBrowsingMetrics.logoSize,
          height: MediaBrowsingMetrics.logoSize,
          fit: BoxFit.contain,
        ),
        title: Text(item.name),
        subtitle: item.rating != null ? Text('★ ${item.rating}') : null,
        onTap: onTap,
      ),
    );
  }
}
