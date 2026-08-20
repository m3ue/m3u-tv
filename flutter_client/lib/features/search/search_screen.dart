import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/epg_show_results.dart';
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

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _query = '';

  // EPG show-search state machine. Mirrors `live_tv_screen.dart:216-220`
  // minus the tab-reset side effect (which lives on the embedded
  // ShowSearchResultsView via its `resetTabsToken` prop instead). The
  // LiveTvScreen version's tab-reset side effect doesn't generalize
  // cleanly, so ~50 duplicated lines is the accepted trade.
  Timer? _showSearchDebounce;
  int _showSearchGeneration = 0;
  List<EpgShow> _showResults = const <EpgShow>[];
  bool _showIsLoading = false;
  String? _showError;
  bool _showSearchWasActive = false;
  int _searchSessionId = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _showSearchDebounce?.cancel();
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

  /// Mirrors `LiveTvScreen._onShowQueryChanged`. Kept independent of the
  /// synchronous `_query` setState that drives channel/VOD/series
  /// filtering so those lists narrow on every keystroke while the show
  /// search waits out the debounce + network roundtrip.
  void _onShowQueryChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      _showSearchWasActive = false;
      _showSearchDebounce?.cancel();
      _showSearchGeneration++;
      if (_showResults.isNotEmpty || _showIsLoading || _showError != null) {
        setState(() {
          _showResults = const <EpgShow>[];
          _showIsLoading = false;
          _showError = null;
        });
      }
      return;
    }
    if (!_showSearchWasActive) {
      _searchSessionId++;
    }
    _showSearchWasActive = true;
    _showSearchDebounce?.cancel();
    // Flip to loading synchronously so the show-results view renders
    // "Searching shows…" the same frame the qualifying query first
    // arrives. Without this, the empty view flashes "No shows match
    // your search" for the 350ms the debounce is waiting before the
    // network call fires.
    setState(() {
      _showIsLoading = true;
      _showResults = const <EpgShow>[];
      _showError = null;
    });
    _showSearchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _runShowSearch(trimmed),
    );
  }

  Future<void> _runShowSearch(String trimmed) async {
    final search = widget.onSearchShows;
    if (search == null) return;
    final generation = ++_showSearchGeneration;
    setState(() {
      _showIsLoading = true;
      _showError = null;
    });
    try {
      final results = await search(trimmed);
      if (!mounted || generation != _showSearchGeneration) return;
      setState(() {
        _showResults = results;
        _showIsLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _showSearchGeneration) return;
      setState(() {
        _showError = error.toString();
        _showIsLoading = false;
      });
    }
  }

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

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
            child: InlineMediaSearchField(
              query: _query,
              hintText: AppLocalizations.of(context).searchHint,
              onChanged: (value) {
                setState(() => _query = value);
                _onShowQueryChanged(value);
              },
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
                ),
                _buildLiveTvTab(filteredChannels, channelsById),
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
  ) {
    if (!_hasQuery) return _buildPromptState();
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    final showResult = buildShowResultEntries(_showResults, channelsById);
    final onNowEntries = showResult.onNow;
    final upcomingEntries = showResult.upcoming;
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
          if (onNowEntries.isNotEmpty) ...[
            _SectionHeader(title: AppLocalizations.of(context).liveTvOnNow),
            ...onNowEntries.map(
              (entry) => ShowResultRow(
                entry: entry,
                channel: channelsById[entry.channelId],
                onNowChannels: showResult.onNowChannels,
                onChannelSelect: widget.onChannelSelect,
                onChannelContextChanged: widget.onChannelContextChanged,
                onShowSelect: widget.onShowSelect,
                languageTag: languageTag,
              ),
            ),
          ],
          if (upcomingEntries.isNotEmpty) ...[
            _SectionHeader(
              title: AppLocalizations.of(context).liveTvUpcomingAirings,
            ),
            ...upcomingEntries.map(
              (entry) => ShowResultRow(
                entry: entry,
                channel: channelsById[entry.channelId],
                onNowChannels: showResult.onNowChannels,
                onChannelSelect: widget.onChannelSelect,
                onChannelContextChanged: widget.onChannelContextChanged,
                onShowSelect: widget.onShowSelect,
                languageTag: languageTag,
              ),
            ),
          ],
          if (channels.isNotEmpty) ...[
            _SectionHeader(
              title: AppLocalizations.of(context).searchSectionLiveTv,
            ),
            ...channels.map(
              (c) => _ChannelListTile(
                channel: c,
                onTap: () {
                  widget.onChannelContextChanged?.call(channels);
                  widget.onChannelSelect(c);
                },
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

  Widget _buildLiveTvTab(
    List<Channel> channels,
    Map<int, Channel> channelsById,
  ) {
    if (!_hasQuery) return _buildPromptState();
    // When the EPG show search is active, fully replace the channel-tile
    // list with the same All/On-Now/Upcoming sub-tab view LiveTvScreen
    // uses - mirrors LiveTvScreen exactly because (like Live TV) this tab
    // has nothing else to show once a show search fires.
    if (_showSearchActive) {
      return ShowSearchResultsView(
        shows: _showResults,
        isLoading: _showIsLoading,
        error: _showError,
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
        resetTabsToken: _searchSessionId,
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
