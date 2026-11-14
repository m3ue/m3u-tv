import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart' show EnsureEpg;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindLive, kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/channel_grid_tile.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/epg_show_results.dart';
import 'package:m3u_tv/shared/epg_show_search_controller.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Hard cap on VOD/series search matches fetched from the catalog. A real
/// query already narrows results at the SQL layer (unlike the old in-memory
/// scan, which held the whole catalog just to filter it down) - this is a
/// safety net against a single broad character matching a huge fraction of
/// a 100k-item library, not the expected case.
const _searchResultLimit = 500;

/// Search across Live TV, Movies, Series and DVR recordings.
///
/// - Case-insensitive name matching, re-run as the user types
/// - All tab: Home-style rows of each kind's first matches
/// - Live TV / Movies / Series / Recordings tabs: the same grids those
///   screens use
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
    this.onRecordingPlay,
    this.onEnsureEpg,
    this.useSidebarLayout = false,
  });

  final void Function(Channel) onChannelSelect;

  /// Called with the current search-result channel list right before
  /// [onChannelSelect], so the player's skip-previous/skip-next stays within
  /// these search results instead of the full unfiltered channel list.
  final void Function(ChannelContext)? onChannelContextChanged;
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

  /// Plays a matching DVR recording. When non-null and the DVR feature is
  /// enabled, playable recordings matching the query show as a Recordings
  /// section in the All tab and in their own Recordings tab.
  final void Function(PlayerArgs)? onRecordingPlay;

  /// Asks for EPG for channel results as their cards build, so the Live TV
  /// cards can show what's on.
  final EnsureEpg? onEnsureEpg;

  /// Whether the screen sits beside `AppShell`'s sidebar rail, which the
  /// All tab's rows size their cards around.
  final bool useSidebarLayout;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

/// The three catalog filters only re-run once typing pauses for this long.
/// [_SearchScreenState._query] still tracks every keystroke (it drives the
/// text field and the EPG show search); [_SearchScreenState._appliedQuery]
/// lags behind it by up to one debounce and drives the catalog filtering.
const _searchDebounce = Duration(milliseconds: 200);

class _SearchScreenState extends ConsumerState<SearchScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final _tabBarKey = GlobalKey<DpadTabBarState>();
  String _query = '';
  String _appliedQuery = '';
  Timer? _debounce;

  final _showSearchController = EpgShowSearchController();

  /// The query these results were fetched for - re-fetch only when
  /// [_appliedQuery] moves past this, not on every unrelated rebuild.
  String? _catalogResultsFor;
  List<Channel> _channelResults = const [];
  List<VodItem> _vodResults = const [];
  List<Series> _seriesResults = const [];

  /// Memo keys for [_recordingResults]: re-filtered only when the recordings
  /// list or [_appliedQuery] changes, not on every keystroke-driven rebuild.
  List<DvrRecording>? _recordingResultsSource;
  String? _recordingResultsFor;
  List<DvrRecording> _recordingResults = const [];

  /// The On Now rows' channels, read from the catalog.
  final ShowResultChannelLookup _showResultChannels = ShowResultChannelLookup();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _baseTabCount, vsync: this);
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
    // keystroke; only the catalog query is debounced here.
    _showSearchController.onQueryChanged(value, widget.onSearchShows);
    _debounce?.cancel();
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() => _appliedQuery = '');
      return;
    }
    // Apply the first character of a fresh query immediately so results show
    // without a debounce-length flash of the empty state; only throttle
    // subsequent keystrokes while results are already on screen.
    if (_appliedQuery.isEmpty) {
      setState(() => _appliedQuery = value);
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

  /// Kicks off (or skips, if already resolved for [_appliedQuery]) the VOD/
  /// series catalog search. Called from [build] - `setState` inside is safe
  /// because it only fires from the async completion callback, never
  /// synchronously during the build that triggered it.
  void _ensureCatalogResults(CatalogRepository repo) {
    if (_catalogResultsFor == _appliedQuery) return;
    _catalogResultsFor = _appliedQuery;
    final query = _appliedQuery;
    if (query.trim().isEmpty) {
      _channelResults = const [];
      _vodResults = const [];
      _seriesResults = const [];
      return;
    }
    unawaited(
      Future.wait([
        repo.pageActiveItems<Channel>(
          kind: kCatalogKindLive,
          search: query,
          offset: 0,
          limit: _searchResultLimit,
        ),
        repo.pageActiveItems<VodItem>(
          kind: kCatalogKindVod,
          search: query,
          offset: 0,
          limit: _searchResultLimit,
        ),
        repo.pageActiveItems<Series>(
          kind: kCatalogKindSeries,
          search: query,
          offset: 0,
          limit: _searchResultLimit,
        ),
      ]).then((results) {
        if (mounted && _catalogResultsFor == query) {
          setState(() {
            _channelResults = results[0] as List<Channel>;
            _vodResults = results[1] as List<VodItem>;
            _seriesResults = results[2] as List<Series>;
          });
        }
      }),
    );
  }

  /// Swaps in a controller with one more (or one fewer) tab when the
  /// Recordings tab appears or disappears with the DVR feature. The old
  /// controller is disposed after the frame, once the tab bar has let go of it.
  void _syncTabCount(int length) {
    if (_tabController.length == length) return;
    final previous = _tabController;
    _tabController = TabController(
      length: length,
      vsync: this,
      initialIndex: previous.index.clamp(0, length - 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
  }

  /// Playable recordings whose title, episode title or channel name contains
  /// the query: in-progress ones first, then the newest.
  List<DvrRecording> _matchingRecordings(List<DvrRecording> recordings) {
    if (identical(recordings, _recordingResultsSource) &&
        _recordingResultsFor == _appliedQuery) {
      return _recordingResults;
    }
    _recordingResultsSource = recordings;
    _recordingResultsFor = _appliedQuery;
    final query = _appliedQuery.trim().toLowerCase();
    if (query.isEmpty) return _recordingResults = const [];
    bool matches(String? value) =>
        value != null && value.toLowerCase().contains(query);
    final matching = recordings
        .where(
          (recording) =>
              recording.isPlayable &&
              (matches(recording.title) ||
                  matches(recording.subtitle) ||
                  matches(recording.channelName)),
        )
        .toList();
    DateTime? airedAt(DvrRecording recording) =>
        recording.actualStart ?? recording.scheduledStart;
    matching.sort((a, b) {
      if (a.isInProgress != b.isInProgress) return a.isInProgress ? -1 : 1;
      final aStart = airedAt(a);
      final bStart = airedAt(b);
      if (aStart == null || bStart == null) {
        return aStart == null ? (bStart == null ? 0 : 1) : -1;
      }
      return bStart.compareTo(aStart);
    });
    return _recordingResults = matching;
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
    // A catalog load (a refresh, or a switch to another playlist) replaces
    // the rows the results came from: run the search again.
    ref.listen<List<Category>>(liveCategoriesProvider, (previous, next) {
      if (!identical(previous, next)) setState(() => _catalogResultsFor = null);
    });
    // A switch is caught even when both playlists' lists look the same.
    ref.listen<String?>(shownPlaylistKeyProvider, (previous, next) {
      if (previous != next) setState(() => _catalogResultsFor = null);
    });

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).appNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final showRecordings =
        widget.onRecordingPlay != null && ref.watch(hasDvrFeatureProvider);
    _syncTabCount(_baseTabCount + (showRecordings ? 1 : 0));
    final recordingResults = showRecordings
        ? _matchingRecordings(ref.watch(dvrRecordingsProvider))
        : const <DvrRecording>[];

    final repo = ref.watch(catalogRepositoryProvider);
    _ensureCatalogResults(repo);
    final filteredChannels = _channelResults;
    final filteredVodItems = _vodResults;
    final filteredSeries = _seriesResults;
    // Resolved by id from the whole catalog, not the name-filtered results:
    // a show's channel needn't match the query.
    final channelsById = _showResultChannels.channelsFor(
      _showSearchController.results,
      repo,
      onResolved: () {
        if (mounted) setState(() {});
      },
    );
    // Shared by the All and Live TV tabs, so the On Now/Upcoming grouping
    // runs once per build whichever is showing.
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
            key: _tabBarKey,
            controller: _tabController,
            tabs: [
              AppLocalizations.of(context).liveTvSearchFilterAll,
              AppLocalizations.of(context).searchSectionLiveTv,
              AppLocalizations.of(context).searchSectionMovies,
              AppLocalizations.of(context).searchSectionSeries,
              if (showRecordings)
                AppLocalizations.of(context).searchSectionRecordings,
            ],
          ),
          // Only the selected tab, not a TabBarView: D-pad focus reveals a
          // card in every scrollable above it, so a card near the side edge
          // nudged TabBarView's PageView toward the next tab and it bounced
          // back. Tabs switch from the tab bar alone.
          Expanded(
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => KeyedSubtree(
                key: ValueKey(_tabController.index),
                child: switch (_tabController.index) {
                  0 => _buildAllTab(
                    filteredChannels,
                    filteredVodItems,
                    filteredSeries,
                    recordingResults,
                    channelsById,
                    showResult,
                  ),
                  _liveTvTabIndex => _buildLiveTvTab(
                    filteredChannels,
                    channelsById,
                    showResult,
                  ),
                  _moviesTabIndex => _buildMoviesTab(filteredVodItems),
                  _seriesTabIndex => _buildSeriesTab(filteredSeries),
                  _ => _buildRecordingsTab(recordingResults),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Left opens the sidebar; Up from the top of a tab's content goes to the
  /// selected tab, which sits outside the content's D-pad regions.
  void _handleContentEdge(TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      widget.onSidebarActivate?.call();
    } else if (direction == TraversalDirection.up) {
      _tabBarKey.currentState?.requestFocusFromContent();
    }
  }

  /// Up from the All tab's first row. Not [_handleContentEdge]: that pages
  /// the focused card's scrollable up first, which for a row is the row's
  /// own horizontal list.
  void _focusSelectedTab() => _tabBarKey.currentState?.requestFocus();

  void _selectChannel(List<Channel> channels, Channel channel) {
    widget.onChannelContextChanged?.call(ListChannelContext(channels));
    widget.onChannelSelect(channel);
  }

  /// A row's last card, opening its tab, when the row can't show every
  /// match.
  MediaPreviewItem? _viewAllItem(int matchCount, int tabIndex) {
    if (matchCount <= MediaPreviewSection.maxVisibleItems) return null;
    return MediaPreviewItem(
      title: AppLocalizations.of(context).homeViewAll,
      fallbackIcon: Icons.arrow_forward,
      onTap: () => _tabController.animateTo(tabIndex),
    );
  }

  /// The All tab: one Home-style row per kind of match, each showing its
  /// first [MediaPreviewSection.maxVisibleItems] and ending in a View All
  /// card that opens that kind's tab.
  Widget _buildAllTab(
    List<Channel> channels,
    List<VodItem> vodItems,
    List<Series> seriesList,
    List<DvrRecording> recordings,
    Map<int, Channel> channelsById,
    ShowResultEntries? showResult,
  ) {
    if (!_hasQuery) return _buildPromptState();
    final liveChannels = _liveTvChannels(channels, showResult);
    final upcomingEntries = showResult?.upcoming ?? const <ShowResultEntry>[];
    // Empty-state-guard: a query can match a show name that doesn't match
    // any channel/VOD/series name (e.g. "Bear" matching no channel called
    // "Bear" but airing on some channel). Without this check, the EPG
    // results would never render.
    if (liveChannels.isEmpty &&
        vodItems.isEmpty &&
        seriesList.isEmpty &&
        recordings.isEmpty &&
        upcomingEntries.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context).searchNoResults);
    }

    final l = AppLocalizations.of(context);
    final useSidebarLayout = widget.useSidebarLayout;
    final onSidebarActivate = widget.onSidebarActivate;
    const visible = MediaPreviewSection.maxVisibleItems;

    // Live TV and Upcoming lead, in the Live TV tab's order. The first row
    // takes Up to the selected tab; later rows move focus to the row above.
    final rows = <Widget Function(VoidCallback? onTopEdge)>[
      ?_channelRow(liveChannels, showResult, preview: true),
      ?_upcomingRow(channelsById, upcomingEntries, preview: true),
      if (recordings.isNotEmpty)
        (onTopEdge) => MediaPreviewSection(
          autofocusFirst: false,
          title: l.searchSectionRecordings,
          titleIcon: Icons.video_library,
          emptyLabel: l.searchNoResults,
          posterStyle: true,
          items: [
            for (final recording in recordings.take(visible))
              _recordingItem(recording),
          ],
          viewAll: _viewAllItem(recordings.length, _recordingsTabIndex),
          useSidebarLayout: useSidebarLayout,
          onSidebarActivate: onSidebarActivate,
          onTopEdge: onTopEdge,
        ),
      if (vodItems.isNotEmpty)
        (onTopEdge) => MediaPreviewSection(
          autofocusFirst: false,
          title: l.searchSectionMovies,
          titleIcon: Icons.movie,
          emptyLabel: l.searchNoResults,
          posterStyle: true,
          items: [
            for (final item in vodItems.take(visible)) _vodItem(item),
          ],
          viewAll: _viewAllItem(vodItems.length, _moviesTabIndex),
          useSidebarLayout: useSidebarLayout,
          onSidebarActivate: onSidebarActivate,
          onTopEdge: onTopEdge,
        ),
      if (seriesList.isNotEmpty)
        (onTopEdge) => MediaPreviewSection(
          autofocusFirst: false,
          title: l.searchSectionSeries,
          titleIcon: Icons.tv,
          emptyLabel: l.searchNoResults,
          posterStyle: true,
          items: [
            for (final series in seriesList.take(visible)) _seriesItem(series),
          ],
          viewAll: _viewAllItem(seriesList.length, _seriesTabIndex),
          useSidebarLayout: useSidebarLayout,
          onSidebarActivate: onSidebarActivate,
          onTopEdge: onTopEdge,
        ),
    ];
    return _buildRows(rows);
  }

  /// A tab's rows, stacked. Its own focus scope keeps the tab bar out of
  /// reach of Up between rows: with the row above scrolled out of the list's
  /// cache, the tabs were the nearest thing above, so Up jumped there
  /// instead of scrolling the row back in. Inside the scope dpad scrolls up
  /// and retries instead. The first row takes Up to the selected tab. Rows
  /// set `autofocusFirst: false`: with nothing focused in this scope, a
  /// first card's autofocus would take focus from the search field as
  /// results arrive.
  Widget _buildRows(List<Widget Function(VoidCallback? onTopEdge)> rows) {
    return FocusScope(
      child: ListView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        children: [
          for (var index = 0; index < rows.length; index++)
            rows[index](index == 0 ? _focusSelectedTab : null),
        ],
      ),
    );
  }

  /// The channels for the Live TV row: those whose name matches, then
  /// those airing a matching show right now (their tile shows it as the
  /// current programme). Remembered between builds, as the name matches can
  /// run long.
  List<Channel> _liveTvChannels(
    List<Channel> channels,
    ShowResultEntries? showResult,
  ) {
    final airing = showResult?.onNowChannels ?? const <Channel>[];
    if (airing.isEmpty) return channels;
    final airingIds = [for (final channel in airing) channel.id];
    final cached = _liveTvChannelsCache;
    if (cached != null &&
        identical(cached.channels, channels) &&
        listEquals(cached.airingIds, airingIds)) {
      return cached.result;
    }
    final seen = {for (final channel in channels) channel.id};
    final result = [
      ...channels,
      for (final channel in airing)
        if (seen.add(channel.id)) channel,
    ];
    _liveTvChannelsCache = (
      channels: channels,
      airingIds: airingIds,
      result: result,
    );
    return result;
  }

  ({List<Channel> channels, List<int> airingIds, List<Channel> result})?
  _liveTvChannelsCache;

  /// Shows airing later that match, on Live TV's channel tiles. As a
  /// [preview] (the All tab) it shows its first
  /// [MediaPreviewSection.maxVisibleItems] and ends in a View All card
  /// opening the Live TV tab; on the Live TV tab it is the full list. Null
  /// with no matches.
  Widget Function(VoidCallback? onTopEdge)? _upcomingRow(
    Map<int, Channel> channelsById,
    List<ShowResultEntry> entries, {
    required bool preview,
  }) {
    if (entries.isEmpty) return null;
    return (onTopEdge) => _ShowResultsRow(
      title: AppLocalizations.of(context).liveTvUpcomingAirings,
      titleIcon: Icons.schedule,
      entries: entries,
      channelsById: channelsById,
      maxItems: _rowMaxItems(entries.length, preview: preview),
      viewAll: _rowViewAll(entries.length, preview: preview),
      onEntryTap: (entry) => widget.onShowSelect?.call(entry.show),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
      onTopEdge: onTopEdge,
    );
  }

  /// The Live TV row, like [_upcomingRow]. Null with no channels.
  Widget Function(VoidCallback? onTopEdge)? _channelRow(
    List<Channel> channels,
    ShowResultEntries? showResult, {
    required bool preview,
  }) {
    if (channels.isEmpty) return null;
    // A channel airing a matching show shows that airing, which needn't be
    // in the local guide yet.
    final airingByChannel = <int, ShowResultEntry>{
      for (final entry in showResult?.onNow ?? const <ShowResultEntry>[])
        entry.channelId: entry,
    };
    return (onTopEdge) => _ChannelResultsRow(
      title: AppLocalizations.of(context).searchSectionLiveTv,
      channels: channels,
      airingByChannel: airingByChannel,
      maxItems: _rowMaxItems(channels.length, preview: preview),
      viewAll: _rowViewAll(channels.length, preview: preview),
      onChannelTap: (channel) => _selectChannel(channels, channel),
      onEnsureEpg: widget.onEnsureEpg,
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
      onTopEdge: onTopEdge,
    );
  }

  int _rowMaxItems(int count, {required bool preview}) =>
      preview ? MediaPreviewSection.maxVisibleItems : count;

  MediaPreviewItem? _rowViewAll(int count, {required bool preview}) =>
      preview ? _viewAllItem(count, _liveTvTabIndex) : null;

  Widget _buildLiveTvTab(
    List<Channel> channels,
    Map<int, Channel> channelsById,
    ShowResultEntries? showResult,
  ) {
    if (!_hasQuery) return _buildPromptState();
    // With a show search running, the tab is the All tab's top rows (Live
    // TV, then Upcoming), each in full.
    if (showResult != null) {
      final rows = [
        ?_channelRow(
          _liveTvChannels(channels, showResult),
          showResult,
          preview: false,
        ),
        ?_upcomingRow(channelsById, showResult.upcoming, preview: false),
      ];
      if (rows.isNotEmpty) return _buildRows(rows);
      final l = AppLocalizations.of(context);
      return _buildEmptyState(
        _showSearchController.isLoading
            ? l.liveTvShowResultsLoading
            : _showSearchController.error != null
            ? l.showsSearchError
            : l.searchNoResults,
      );
    }
    if (channels.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context).searchNoResults);
    }
    return _ChannelResultsGrid(
      channels: channels,
      onChannelTap: (channel) => _selectChannel(channels, channel),
      onEnsureEpg: widget.onEnsureEpg,
      onEdge: _handleContentEdge,
    );
  }

  Widget _buildMoviesTab(List<VodItem> vodItems) {
    if (!_hasQuery) return _buildPromptState();
    if (vodItems.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context).searchNoResults);
    }
    return _buildPosterGrid(
      memoryKey: 'search/movies',
      itemCount: vodItems.length,
      itemAt: (index) => _vodItem(vodItems[index]),
    );
  }

  Widget _buildSeriesTab(List<Series> seriesList) {
    if (!_hasQuery) return _buildPromptState();
    if (seriesList.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context).searchNoResults);
    }
    return _buildPosterGrid(
      memoryKey: 'search/series',
      itemCount: seriesList.length,
      itemAt: (index) => _seriesItem(seriesList[index]),
    );
  }

  /// The Movies and Series pages' poster grid.
  Widget _buildPosterGrid({
    required String memoryKey,
    required int itemCount,
    required MediaPreviewItem Function(int index) itemAt,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = posterGridColumnCount(
          constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2,
          FontSizeScope.scaleOf(context),
        );
        return DpadRegion(
          memoryKey: memoryKey,
          horizontalEdge: DpadEdgeBehavior.stop,
          upEdge: DpadEdgeBehavior.stop,
          onEdge: _handleContentEdge,
          child: ScrollbarGridView(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columnCount,
              childAspectRatio: 0.6,
              mainAxisSpacing: MediaBrowsingMetrics.itemGap,
              crossAxisSpacing: MediaBrowsingMetrics.itemGap,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) => MediaPreviewCard(
              item: itemAt(index),
              posterStyle: true,
              keepAlive: false,
              autofocus: index == 0,
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordingsTab(List<DvrRecording> recordings) {
    if (!_hasQuery) return _buildPromptState();
    if (recordings.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context).searchNoResults);
    }
    return _buildPosterGrid(
      memoryKey: 'search/recordings',
      itemCount: recordings.length,
      itemAt: (index) => _recordingItem(recordings[index]),
    );
  }

  MediaPreviewItem _vodItem(VodItem item) {
    final rating = item.rating;
    return MediaPreviewItem(
      title: item.name,
      imageUrl: item.logoUrl,
      subtitle: item.year,
      ratingLabel: rating == null ? null : formatRating(rating),
      fallbackIcon: Icons.movie,
      onTap: () => widget.onVodSelect(item),
    );
  }

  MediaPreviewItem _seriesItem(Series series) {
    final rating = series.rating;
    return MediaPreviewItem(
      title: series.name,
      imageUrl: series.coverUrl,
      subtitle: series.year,
      ratingLabel: rating == null ? null : formatRating(rating),
      fallbackIcon: Icons.tv,
      onTap: () => widget.onSeriesSelect(series),
    );
  }

  MediaPreviewItem _recordingItem(DvrRecording recording) {
    final season = recording.seasonNumber;
    final episode = recording.episodeNumber;
    final details = [
      if (season != null && episode != null)
        'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
      ?nullIfBlank(recording.subtitle),
      ?nullIfBlank(recording.channelName),
    ];
    // Library recordings have a poster (the movie's, or the series cover);
    // ones still recording or not yet added show their channel's logo.
    final posterUrl = recording.posterUrl;
    return MediaPreviewItem(
      title: recording.title,
      subtitle: details.isEmpty ? null : details.join(' · '),
      imageUrl: posterUrl ?? recording.channelIconUrl,
      imageFit: posterUrl == null ? BoxFit.contain : BoxFit.cover,
      fallbackIcon: Icons.video_library,
      // Same corner badge the poster cards use for favorites, in red while
      // the recording is still in progress.
      cornerBadgeIcon: recording.isInProgress
          ? Icons.fiber_manual_record
          : null,
      cornerBadgeColor: recording.isInProgress
          ? Theme.of(context).colorScheme.error
          : null,
      onTap: () =>
          widget.onRecordingPlay?.call(PlayerArgs.dvrRecording(recording)),
    );
  }

  Widget _buildPromptState() =>
      _buildEmptyState(AppLocalizations.of(context).searchTypeToSearch);

  Widget _buildEmptyState(String label) =>
      Center(child: Text(label, style: Theme.of(context).textTheme.bodyLarge));
}

/// All, Live TV, Movies and Series; Recordings is added on top when DVR is
/// on.
const _baseTabCount = 4;
const _liveTvTabIndex = 1;
const _moviesTabIndex = 2;
const _seriesTabIndex = 3;
const _recordingsTabIndex = 4;

/// The All tab's Live TV row: the Home Live TV row's card (logo, current
/// programme and its progress). Watches the EPG on its own so a guide update
/// rebuilds just this row, not the whole search screen.
class _ChannelResultsRow extends ConsumerWidget {
  const _ChannelResultsRow({
    required this.title,
    required this.channels,
    required this.airingByChannel,
    required this.maxItems,
    required this.viewAll,
    required this.onChannelTap,
    required this.onEnsureEpg,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.onTopEdge,
  });

  final String title;
  final List<Channel> channels;

  /// The matching show airing now on a channel, shown in place of its guide
  /// entry.
  final Map<int, ShowResultEntry> airingByChannel;
  final int maxItems;
  final MediaPreviewItem? viewAll;
  final ValueChanged<Channel> onChannelTap;
  final EnsureEpg? onEnsureEpg;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final VoidCallback? onTopEdge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgService = ref.watch(epgServiceProvider);
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);
    final l = AppLocalizations.of(context);
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    return MediaPreviewSection.builder(
      autofocusFirst: false,
      title: title,
      titleIcon: Icons.live_tv,
      emptyLabel: AppLocalizations.of(context).searchNoResults,
      viewAll: viewAll,
      maxItems: maxItems,
      itemCount: channels.length,
      baseCardWidth: ChannelGridTile.baseWidth,
      baseCardHeight: ChannelGridTile.baseHeight,
      itemBuilder: (context, index, cardSize, {required autofocus}) {
        final channel = channels[index];
        onEnsureEpg?.call([channel]);
        final airing = airingByChannel[channel.id];
        return SizedBox.fromSize(
          size: cardSize,
          child: ChannelGridTile(
            channel: channel,
            epg: epgService.lookupForChannel(channel),
            programme: airing == null
                ? null
                : showResultTileProgramme(airing, languageTag, l),
            isFavorite: false,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: autofocus,
            onTap: () => onChannelTap(channel),
          ),
        );
      },
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
      onTopEdge: onTopEdge,
    );
  }
}

/// The Upcoming row: each show on its channel's Live TV tile, with the airing
/// (not the channel's current guide entry) under the channel name.
class _ShowResultsRow extends ConsumerWidget {
  const _ShowResultsRow({
    required this.title,
    required this.titleIcon,
    required this.entries,
    required this.channelsById,
    required this.maxItems,
    required this.viewAll,
    required this.onEntryTap,
    required this.useSidebarLayout,
    required this.onSidebarActivate,
    required this.onTopEdge,
  });

  final String title;
  final IconData titleIcon;
  final List<ShowResultEntry> entries;
  final Map<int, Channel> channelsById;
  final int maxItems;
  final MediaPreviewItem? viewAll;
  final ValueChanged<ShowResultEntry> onEntryTap;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;
  final VoidCallback? onTopEdge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);
    final l = AppLocalizations.of(context);
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    return MediaPreviewSection.builder(
      autofocusFirst: false,
      title: title,
      titleIcon: titleIcon,
      emptyLabel: l.searchNoResults,
      viewAll: viewAll,
      maxItems: maxItems,
      itemCount: entries.length,
      baseCardWidth: ChannelGridTile.baseWidth,
      baseCardHeight: ChannelGridTile.baseHeight,
      itemBuilder: (context, index, cardSize, {required autofocus}) {
        final entry = entries[index];
        final firstEpisode = entry.episodes.first;
        // An Upcoming show can air on a channel this playlist doesn't carry;
        // its tile still names the channel and opens the show.
        final channel =
            channelsById[entry.channelId] ??
            Channel(
              id: entry.channelId,
              name: firstEpisode.channelName ?? '',
              streamUrl: '',
            );
        return SizedBox.fromSize(
          size: cardSize,
          child: ChannelGridTile(
            channel: channel,
            programme: showResultTileProgramme(entry, languageTag, l),
            isFavorite: false,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: autofocus,
            onTap: () => onEntryTap(entry),
          ),
        );
      },
      useSidebarLayout: useSidebarLayout,
      onSidebarActivate: onSidebarActivate,
      onTopEdge: onTopEdge,
    );
  }
}

/// The Live TV tab: Live TV's Grid view over the matching channels.
class _ChannelResultsGrid extends ConsumerWidget {
  const _ChannelResultsGrid({
    required this.channels,
    required this.onChannelTap,
    required this.onEnsureEpg,
    required this.onEdge,
  });

  final List<Channel> channels;
  final ValueChanged<Channel> onChannelTap;
  final EnsureEpg? onEnsureEpg;
  final ValueChanged<TraversalDirection> onEdge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epgService = ref.watch(epgServiceProvider);
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);
    final scale = FontSizeScope.scaleOf(context);
    return DpadRegion(
      memoryKey: 'search/live-tv',
      horizontalEdge: DpadEdgeBehavior.stop,
      upEdge: DpadEdgeBehavior.stop,
      onEdge: onEdge,
      child: ScrollbarGridView(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: ChannelGridTile.baseWidth * scale,
          mainAxisExtent: ChannelGridTile.baseHeight * scale,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          onEnsureEpg?.call([channel]);
          return ChannelGridTile(
            channel: channel,
            epg: epgService.lookupForChannel(channel),
            isFavorite: false,
            isRecording: recordingChannelIds.contains(channel.id),
            autofocus: index == 0,
            onTap: () => onChannelTap(channel),
          );
        },
      ),
    );
  }
}
