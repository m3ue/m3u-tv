import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/catalog_text_filter.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/epg_show_results.dart';
import 'package:m3u_tv/shared/epg_show_search_controller.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/show_search_results_view.dart';

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
    this.onChannelContextChanged,
    required this.onVodSelect,
    required this.onSeriesSelect,
    this.onSidebarActivate,
    this.onSearchShows,
    this.onShowSelect,
  });

  final void Function(Channel) onChannelSelect;

  /// Called with the current search-result channel list right before
  /// [onChannelSelect], so the player's skip-previous/skip-next stays within
  /// these search results instead of the full unfiltered channel list.
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final VoidCallback? onSidebarActivate;

  /// When non-null, a ≥2-character query surfaces EPG show results in
  /// both the All tab (as On-Now/Upcoming sections above the existing
  /// channel-name section) and the Live TV tab (which fully replaces its
  /// content with the All/On-Now/Upcoming sub-tab view). The same
  /// nullable convention `LiveTvScreen` uses - hides the affordance
  /// entirely when the host app hasn't wired it.
  final Future<List<EpgShow>> Function(String)? onSearchShows;

  /// Tapping an Upcoming row in either tab calls this. On Now rows still
  /// go through [onChannelSelect] (today's player skip-previous/next
  /// semantics depend on that channel-first path).
  final void Function(EpgShow)? onShowSelect;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// The three catalog filters only re-run once typing pauses for this long.
/// [_SearchScreenState._query] still tracks every keystroke (it drives the
/// text field and the EPG show search); [_SearchScreenState._appliedQuery]
/// lags behind it by up to one debounce and drives the catalog filtering.
const _searchDebounce = Duration(milliseconds: 200);

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';
  String _appliedQuery = '';
  Timer? _debounce;

  final _showSearchController = EpgShowSearchController();
  final CatalogTextFilter<Channel> _channelFilter = CatalogTextFilter(
    (c) => c.name,
  );
  final CatalogTextFilter<VodItem> _vodFilter = CatalogTextFilter(
    (v) => v.name,
  );
  final CatalogTextFilter<Series> _seriesFilter = CatalogTextFilter(
    (s) => s.name,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _showSearchController.addListener(_onShowSearchChanged);
  }

  void _onShowSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    _showSearchController
      ..removeListener(_onShowSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    // The EPG show search runs its own 350ms debounce, so feed it every
    // keystroke; only the synchronous catalog filter is debounced here.
    _showSearchController.onQueryChanged(value, widget.onSearchShows);
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      _appliedQuery = '';
      return;
    }
    // Apply the first character of a fresh query immediately so results show
    // without a debounce-length flash of the empty state; only throttle
    // subsequent keystrokes while results are already on screen.
    if (_appliedQuery.isEmpty) {
      _appliedQuery = value;
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      if (mounted && value != _appliedQuery) {
        setState(() => _appliedQuery = value);
      }
    });
  }

  String get _normalizedQuery => _query.trim().toLowerCase();
  bool get _hasQuery => _normalizedQuery.isNotEmpty;

  List<Channel> _filterChannels(List<Channel> channels) =>
      _channelFilter.filterWhole(channels, _appliedQuery);

  List<VodItem> _filterVodItems(List<VodItem> vodItems) =>
      _vodFilter.filterWhole(vodItems, _appliedQuery);

  List<Series> _filterSeriesList(List<Series> seriesList) =>
      _seriesFilter.filterWhole(seriesList, _appliedQuery);

  /// Active when the EPG show search should render in place of (Live TV
  /// tab) or alongside (All tab) the synchronous channel-name filter.
  /// Mirrors `live_tv_screen.dart:764`'s `showSearchActive` condition.
  bool get _showSearchActive =>
      widget.onSearchShows != null && _normalizedQuery.length >= 2;

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
    // Build from the FULL channel list (not the filtered one) - EPG
    // show-result channel lookups must work even when the show's
    // channel name doesn't match the current query.
    final channelsById = {for (final c in channels) c.id: c};
    // Computed once per build and threaded through to both the All tab and
    // the Live TV tab's ShowSearchResultsView - both are built eagerly by
    // TabBarView on every keystroke, so without sharing this the On-Now/
    // Upcoming grouping work ran twice per build.
    final showResult = _showSearchActive
        ? buildShowResultEntries(_showSearchController.results, channelsById)
        : null;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
            child: InlineMediaSearchField(
              query: _query,
              hintText: AppLocalizations.of(context).searchHint,
              onChanged: _onQueryChanged,
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
                  channelsById,
                  showResult,
                ),
                _buildLiveTvTab(filteredChannels, channelsById, showResult),
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
    Map<int, Channel> channelsById,
    ShowResultEntries? showResult,
  ) {
    if (!_hasQuery) return _buildPromptState();
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    final onNowEntries = showResult?.onNow ?? const <ShowResultEntry>[];
    final upcomingEntries = showResult?.upcoming ?? const <ShowResultEntry>[];
    final onNowChannels = showResult?.onNowChannels ?? const <Channel>[];
    // Empty-state-guard: a query can match a show name that doesn't match
    // any channel/VOD/series name (e.g. "Bear" matching no channel called
    // "Bear" but airing on some channel). Without this check, the EPG
    // results would never render.
    if (channels.isEmpty &&
        vodItems.isEmpty &&
        seriesList.isEmpty &&
        onNowEntries.isEmpty &&
        upcomingEntries.isEmpty) {
      return _buildEmptyState('No results found');
    }

    final l = AppLocalizations.of(context);
    // Flatten every section into one addressable row list so the whole tab
    // scrolls through a single lazy ListView.builder. The previous
    // `ListView(children: [...maps])` mounted every match at once - hundreds
    // of ListTiles, each firing a network image request - the instant a
    // broad query landed. Entries are either a section-title String or a
    // domain object; the builder switches on the runtime type.
    final rows = <Object>[
      if (onNowEntries.isNotEmpty) ...[l.liveTvOnNow, ...onNowEntries],
      if (upcomingEntries.isNotEmpty) ...[
        l.liveTvUpcomingAirings,
        ...upcomingEntries,
      ],
      if (channels.isNotEmpty) ...[l.searchSectionLiveTv, ...channels],
      if (vodItems.isNotEmpty) ...[l.searchSectionMovies, ...vodItems],
      if (seriesList.isNotEmpty) ...[l.searchSectionSeries, ...seriesList],
    ];

    return DpadRegion(
      memoryKey: 'search/all',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          if (row is String) return _SectionHeader(title: row);
          if (row is ShowResultEntry) {
            return ShowResultRow(
              entry: row,
              channel: channelsById[row.channelId],
              onNowChannels: onNowChannels,
              onChannelSelect: widget.onChannelSelect,
              onChannelContextChanged: widget.onChannelContextChanged,
              onShowSelect: widget.onShowSelect,
              languageTag: languageTag,
            );
          }
          if (row is Channel) {
            return _ChannelListTile(
              channel: row,
              onTap: () {
                widget.onChannelContextChanged?.call(channels);
                widget.onChannelSelect(row);
              },
            );
          }
          if (row is VodItem) {
            return _VodListTile(
              item: row,
              onTap: () => widget.onVodSelect(row),
            );
          }
          if (row is Series) {
            return _SeriesListTile(
              item: row,
              onTap: () => widget.onSeriesSelect(row),
            );
          }
          assert(false, 'Unhandled search row type: ${row.runtimeType}');
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildLiveTvTab(
    List<Channel> channels,
    Map<int, Channel> channelsById,
    ShowResultEntries? showResult,
  ) {
    if (!_hasQuery) return _buildPromptState();
    // When the EPG show search is active, fully replace the channel-tile
    // list with the same All/On-Now/Upcoming sub-tab view LiveTvScreen
    // uses - mirrors LiveTvScreen exactly because (like Live TV) this tab
    // has nothing else to show once a show search fires.
    if (_showSearchActive) {
      return ShowSearchResultsView(
        shows: _showSearchController.results,
        isLoading: _showSearchController.isLoading,
        error: _showSearchController.error,
        channelsById: channelsById,
        onChannelSelect: widget.onChannelSelect,
        onChannelContextChanged: widget.onChannelContextChanged,
        onShowSelect: widget.onShowSelect,
        memoryKeyPrefix: 'search/live-tv/search-results',
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            widget.onSidebarActivate?.call();
          }
        },
        resetTabsToken: _showSearchController.searchSessionId,
        precomputedResult: showResult,
      );
    }
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
          onTap: () {
            widget.onChannelContextChanged?.call(channels);
            widget.onChannelSelect(channels[index]);
          },
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
          oversample: 2,
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
          oversample: 2,
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
          oversample: 2,
        ),
        title: Text(item.name),
        subtitle: item.rating != null ? Text('★ ${item.rating}') : null,
        onTap: onTap,
      ),
    );
  }
}
