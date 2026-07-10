import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Search screen with client-side filtering across Live TV, Movies, and Series.
///
/// Mirrors the RN SearchScreen behavior:
/// - Case-insensitive name.includes(query) filtering
/// - All / Live TV / Movies / Series tabs
/// - Real-time filtering as user types
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    required this.onChannelSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    this.onSidebarActivate,
  });

  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final VoidCallback? onSidebarActivate;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _normalizedQuery => _query.trim().toLowerCase();
  bool get _hasQuery => _normalizedQuery.isNotEmpty;

  List<Channel> _filterChannels(List<Channel> channels) => _hasQuery
      ? channels
            .where(
              (c) => c.name.toLowerCase().contains(_normalizedQuery),
            )
            .toList(growable: false)
      : const [];

  List<VodItem> _filterVodItems(List<VodItem> vodItems) => _hasQuery
      ? vodItems
            .where(
              (v) => v.name.toLowerCase().contains(_normalizedQuery),
            )
            .toList(growable: false)
      : const [];

  List<Series> _filterSeriesList(List<Series> seriesList) => _hasQuery
      ? seriesList
            .where(
              (s) => s.name.toLowerCase().contains(_normalizedQuery),
            )
            .toList(growable: false)
      : const [];

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final channels = ref.watch(liveChannelsProvider);
    final vodItems = ref.watch(vodItemsProvider);
    final seriesList = ref.watch(seriesListProvider);

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

    final filteredChannels = _filterChannels(channels);
    final filteredVodItems = _filterVodItems(vodItems);
    final filteredSeries = _filterSeriesList(seriesList);

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
            child: InlineMediaSearchField(
              query: _query,
              hintText: AppLocalizations.of(context).searchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          DpadTabBar(
            controller: _tabController,
            tabs: [
              'All',
              AppLocalizations.of(context).searchSectionLiveTv,
              AppLocalizations.of(context).searchSectionMovies,
              AppLocalizations.of(context).searchSectionSeries,
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllTab(
                  filteredChannels,
                  filteredVodItems,
                  filteredSeries,
                ),
                _buildLiveTvTab(filteredChannels),
                _buildMoviesTab(filteredVodItems),
                _buildSeriesTab(filteredSeries),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTab(
    List<Channel> channels,
    List<VodItem> vodItems,
    List<Series> seriesList,
  ) {
    if (!_hasQuery) return _buildPromptState();
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
            _SectionHeader(
              title: AppLocalizations.of(context).searchSectionLiveTv,
            ),
            ...channels.map(
              (c) => _ChannelListTile(
                channel: c,
                onTap: () => widget.onChannelSelect(c),
              ),
            ),
          ],
          if (vodItems.isNotEmpty) ...[
            _SectionHeader(
              title: AppLocalizations.of(context).searchSectionMovies,
            ),
            ...vodItems.map(
              (v) => _VodListTile(item: v, onTap: () => widget.onVodSelect(v)),
            ),
          ],
          if (seriesList.isNotEmpty) ...[
            _SectionHeader(
              title: AppLocalizations.of(context).searchSectionSeries,
            ),
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

  Widget _buildLiveTvTab(List<Channel> channels) {
    if (!_hasQuery) return _buildPromptState();
    if (channels.isEmpty) return _buildEmptyState('No results found');
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

  Widget _buildMoviesTab(List<VodItem> vodItems) {
    if (!_hasQuery) return _buildPromptState();
    if (vodItems.isEmpty) return _buildEmptyState('No results found');
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

  Widget _buildSeriesTab(List<Series> seriesList) {
    if (!_hasQuery) return _buildPromptState();
    if (seriesList.isEmpty) return _buildEmptyState('No results found');
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

  Widget _buildPromptState() =>
      _buildEmptyState(AppLocalizations.of(context).searchTypeToSearch);

  Widget _buildEmptyState(String label) =>
      Center(child: Text(label, style: Theme.of(context).textTheme.bodyLarge));
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
