import 'package:flutter/material.dart';
import 'package:m3u_tv/services/domain_models.dart';

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
  });

  final List<Channel> channels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';

  static const _tabs = [
    Tab(text: 'All'),
    Tab(text: 'Live TV'),
    Tab(text: 'Movies'),
    Tab(text: 'Series'),
  ];

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

  List<Channel> get _filteredChannels =>
      _query.isEmpty ? widget.channels : widget.channels.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();

  List<VodItem> get _filteredVodItems =>
      _query.isEmpty ? widget.vodItems : widget.vodItems.where((v) => v.name.toLowerCase().contains(_query.toLowerCase())).toList();

  List<Series> get _filteredSeriesList =>
      _query.isEmpty ? widget.seriesList : widget.seriesList.where((s) => s.name.toLowerCase().contains(_query.toLowerCase())).toList();

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
          // Search field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: _tabs,
          ),
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
    final channels = _filteredChannels;
    final vodItems = _filteredVodItems;
    final seriesList = _filteredSeriesList;

    if (channels.isEmpty && vodItems.isEmpty && seriesList.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'Type to search' : 'No results found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return ListView(
      children: [
        if (channels.isNotEmpty) ...[
          const _SectionHeader(title: 'Live TV'),
          ...channels.map((c) => _ChannelListTile(
                channel: c,
                onTap: () => widget.onChannelSelect(c),
              )),
        ],
        if (vodItems.isNotEmpty) ...[
          const _SectionHeader(title: 'Movies'),
          ...vodItems.map((v) => _VodListTile(
                item: v,
                onTap: () => widget.onVodSelect(v),
              )),
        ],
        if (seriesList.isNotEmpty) ...[
          const _SectionHeader(title: 'Series'),
          ...seriesList.map((s) => _SeriesListTile(
                item: s,
                onTap: () => widget.onSeriesSelect(s),
              )),
        ],
      ],
    );
  }

  Widget _buildLiveTvTab() {
    final channels = _filteredChannels;
    if (channels.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No channels available' : 'No results found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, index) => _ChannelListTile(
        channel: channels[index],
        onTap: () => widget.onChannelSelect(channels[index]),
      ),
    );
  }

  Widget _buildMoviesTab() {
    final vodItems = _filteredVodItems;
    if (vodItems.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No movies available' : 'No results found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      itemCount: vodItems.length,
      itemBuilder: (context, index) => _VodListTile(
        item: vodItems[index],
        onTap: () => widget.onVodSelect(vodItems[index]),
      ),
    );
  }

  Widget _buildSeriesTab() {
    final seriesList = _filteredSeriesList;
    if (seriesList.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No series available' : 'No results found',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ListView.builder(
      itemCount: seriesList.length,
      itemBuilder: (context, index) => _SeriesListTile(
        item: seriesList[index],
        onTap: () => widget.onSeriesSelect(seriesList[index]),
      ),
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
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ChannelListTile extends StatelessWidget {
  const _ChannelListTile({required this.channel, required this.onTap});
  final Channel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
          ? CircleAvatar(
              backgroundImage: NetworkImage(channel.logoUrl!),
              onBackgroundImageError: (_, __) {},
              child: const Icon(Icons.tv),
            )
          : const CircleAvatar(child: Icon(Icons.tv)),
      title: Text(channel.name),
      onTap: onTap,
    );
  }
}

class _VodListTile extends StatelessWidget {
  const _VodListTile({required this.item, required this.onTap});
  final VodItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: item.logoUrl != null && item.logoUrl!.isNotEmpty
          ? CircleAvatar(
              backgroundImage: NetworkImage(item.logoUrl!),
              onBackgroundImageError: (_, __) {},
              child: const Icon(Icons.movie),
            )
          : const CircleAvatar(child: Icon(Icons.movie)),
      title: Text(item.name),
      subtitle: item.rating != null ? Text('★ ${item.rating}') : null,
      onTap: onTap,
    );
  }
}

class _SeriesListTile extends StatelessWidget {
  const _SeriesListTile({required this.item, required this.onTap});
  final Series item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: item.coverUrl != null && item.coverUrl!.isNotEmpty
          ? CircleAvatar(
              backgroundImage: NetworkImage(item.coverUrl!),
              onBackgroundImageError: (_, __) {},
              child: const Icon(Icons.tv),
            )
          : const CircleAvatar(child: Icon(Icons.tv)),
      title: Text(item.name),
      subtitle: item.rating != null ? Text('★ ${item.rating}') : null,
      onTap: onTap,
    );
  }
}