import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/epg_show_results.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Renders the All / On Now / Upcoming sub-tab view used by both
/// LiveTvScreen and SearchScreen when a qualifying EPG show search is
/// active. Owns its own `TabController` so callers don't need a second
/// `TickerProvider` slot, and emits a dedicated `DpadRegion` per tab so
/// focus memory doesn't collide between screens (each screen passes a
/// distinct `memoryKeyPrefix`).
class ShowSearchResultsView extends StatefulWidget {
  const ShowSearchResultsView({
    super.key,
    required this.shows,
    required this.isLoading,
    this.error,
    required this.channelsById,
    required this.onChannelSelect,
    this.onChannelContextChanged,
    this.onShowSelect,
    required this.memoryKeyPrefix,
    this.onEdge,
    this.resetTabsToken,
  });

  final List<EpgShow> shows;
  final bool isLoading;
  final String? error;
  final Map<int, Channel> channelsById;
  final void Function(Channel) onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(EpgShow)? onShowSelect;

  /// Prefix for each tab's `DpadRegion` memoryKey (e.g. `live-tv/search-results`
  /// or `search/live-tv/search-results`) - must be distinct per screen so
  /// D-pad focus memory doesn't collide between LiveTvScreen and SearchScreen.
  final String memoryKeyPrefix;
  final void Function(TraversalDirection)? onEdge;

  /// Bump this (e.g. a counter) when a *new* search starts (not on every
  /// keystroke of an already-active one) to reset the internal tab index
  /// back to "All". Mirrors `live_tv_screen.dart:404-407`'s
  /// `_searchResultsTabController.index = 0` side effect, which becomes
  /// unreachable from the parent once the TabController moves in here.
  final Object? resetTabsToken;

  @override
  State<ShowSearchResultsView> createState() => _ShowSearchResultsViewState();
}

class _ShowSearchResultsViewState extends State<ShowSearchResultsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(covariant ShowSearchResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetTabsToken != oldWidget.resetTabsToken) {
      _tabController.index = 0;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageTag = Localizations.localeOf(context).toLanguageTag();
    final result = buildShowResultEntries(widget.shows, widget.channelsById);
    return Column(
      children: [
        DpadTabBar(
          controller: _tabController,
          tabs: [
            l10n.liveTvSearchFilterAll,
            l10n.liveTvOnNow,
            l10n.liveTvUpcomingAirings,
          ],
        ),
        Expanded(
          child: DpadTabBarView(
            controller: _tabController,
            children: [
              _buildResultsList(
                result.all,
                result.onNowChannels,
                languageTag,
                'all',
              ),
              _buildResultsList(
                result.onNow,
                result.onNowChannels,
                languageTag,
                'on-now',
              ),
              _buildResultsList(
                result.upcoming,
                result.onNowChannels,
                languageTag,
                'upcoming',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList(
    List<ShowResultEntry> entries,
    List<Channel> onNowChannels,
    String languageTag,
    String tabKey,
  ) {
    if (entries.isEmpty) {
      // Preserve the R2.1 loading UX: when the user types a qualifying
      // query and the search is still in flight, show the loading label
      // instead of the no-matches label, so the latter doesn't flash
      // before the request resolves.
      final l10n = AppLocalizations.of(context);
      final emptyText = widget.isLoading
          ? l10n.liveTvShowResultsLoading
          : widget.error != null
          ? l10n.showsSearchError
          : l10n.showsNoResults;
      return Center(
        child: Text(emptyText, style: Theme.of(context).textTheme.bodyLarge),
      );
    }
    return DpadRegion(
      memoryKey: '${widget.memoryKeyPrefix}/$tabKey',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: widget.onEdge,
      child: ScrollbarListView(
        itemCount: entries.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ShowResultRow(
            entry: entries[index],
            channel: widget.channelsById[entries[index].channelId],
            onNowChannels: onNowChannels,
            onChannelSelect: widget.onChannelSelect,
            onChannelContextChanged: widget.onChannelContextChanged,
            onShowSelect: widget.onShowSelect,
            languageTag: languageTag,
            autofocus: index == 0,
          ),
        ),
      ),
    );
  }
}
