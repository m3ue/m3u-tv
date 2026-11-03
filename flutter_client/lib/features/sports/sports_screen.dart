import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/multiview/multiview_controller.dart';
import 'package:m3u_tv/features/multiview/multiview_manage_dialog.dart';
import 'package:m3u_tv/features/multiview/multiview_screen.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_resolver.dart';
import 'package:m3u_tv/services/sports_matcher.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_menu_dialog.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';
import 'package:material_ui/material_ui.dart';

/// The days a Sports list covers.
enum SportsRange { yesterday, today, upcoming }

/// Games from the followed competitions (ESPN's schedule), each tied to the
/// channels in the active playlist that carry it, so a game is one press
/// from playing or from joining Multiview.
///
/// Fixtures come from M3U Editor ([sportsServiceProvider]); channels from
/// [SportsChannelResolver] over the locally stored guide and channel names.
/// While a game is on, or about to start, the list refreshes every minute.
class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({
    super.key,
    required this.onChannelSelect,
    required this.useSidebarLayout,
    this.onSidebarActivate,
    this.onEntryFocusScopeReady,
    this.onEnterFullScreenDetail,
    this.onExitFullScreenDetail,
  });

  final ValueChanged<Channel> onChannelSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;

  /// TV/desktop only: forwarded to [MediaCategoryNav.onEntryFocusScopeReady]
  /// so AppShell re-enters this screen's strip when the sidebar deactivates.
  final ValueChanged<FocusScopeNode>? onEntryFocusScopeReady;

  /// Hide and restore AppShell's chrome around the Multiview push, as Live
  /// TV does.
  final VoidCallback? onEnterFullScreenDetail;
  final VoidCallback? onExitFullScreenDetail;

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen>
    with SingleTickerProviderStateMixin {
  static const String _scopeAll = '';
  static const String _scopeMyTeams = '__my_teams__';
  static const Duration _refreshInterval = Duration(minutes: 1);
  static const Duration _guideChangeDebounce = Duration(seconds: 3);

  late final TabController _tabController = TabController(
    length: SportsRange.values.length,
    initialIndex: SportsRange.today.index,
    vsync: this,
  );
  final FocusScopeNode _listFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();
  final GlobalKey<DpadTabBarState> _tabBarKey = GlobalKey<DpadTabBarState>();

  late final SportsSettings _settings = ref.read(sportsSettingsProvider);
  late String _scope = _settings.followedTeams.isEmpty
      ? _scopeAll
      : _scopeMyTeams;
  late String _leagueSignature = _leagueIdsSignature();
  String _query = '';

  List<SportsFixture> _fixtures = const [];
  bool _loading = true;

  /// The last load failed with nothing loaded before it to keep showing.
  bool _loadFailed = false;
  int _loadGeneration = 0;
  Map<String, List<SportsChannelMatch>> _matches = const {};
  bool _resolving = false;
  Future<void>? _resolveInFlight;
  int _resolveGeneration = 0;

  /// The watchable games [_matches] was resolved for. A score refresh that
  /// brings the same games skips the resolve; a guide or playlist change
  /// clears it.
  String? _resolvedSignature;
  List<_SportsRow> _rows = const [];

  Timer? _refreshTimer;
  Timer? _guideChangeTimer;
  ValueListenable<TickerModeData>? _tickerModeNotifier;

  SportsRange get _range => SportsRange.values[_tabController.index];

  bool get _isVisible => _tickerModeNotifier?.value.enabled ?? true;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_onRangeChanged);
    _settings.addListener(_onSettingsChanged);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // AppShell keeps every tab mounted; TickerMode turns off for the hidden
    // ones, which is the signal to stop polling for scores.
    final notifier = TickerMode.getValuesNotifier(context);
    if (!identical(notifier, _tickerModeNotifier)) {
      _tickerModeNotifier?.removeListener(_onVisibilityChanged);
      _tickerModeNotifier = notifier..addListener(_onVisibilityChanged);
    }
  }

  @override
  void dispose() {
    _tickerModeNotifier?.removeListener(_onVisibilityChanged);
    _settings.removeListener(_onSettingsChanged);
    _refreshTimer?.cancel();
    _guideChangeTimer?.cancel();
    _tabController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (_isVisible) {
      // Guide changes aren't followed while hidden.
      _resolvedSignature = null;
      unawaited(_load());
    } else {
      _refreshTimer?.cancel();
      _guideChangeTimer?.cancel();
    }
  }

  void _onRangeChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {
      _fixtures = const [];
      _matches = const {};
      _resolvedSignature = null;
      _rows = const [];
      _loading = true;
    });
    unawaited(_load());
  }

  /// What the editor's Sports integration offers; null while it's off.
  SportsCapability? get _capability => ref.read(sportsCapabilityProvider);

  /// The competitions listed: the viewer's picks among the editor's.
  List<SportsLeague> get _leagues =>
      _settings.enabledLeagues(_capability?.leagues ?? const []);

  String _leagueIdsSignature() => _leagues.map((league) => league.id).join(',');

  void _onSettingsChanged() {
    if (!mounted) return;
    _onLeaguesMaybeChanged();
  }

  /// Reloads when the listed competitions changed (the viewer's picks or the
  /// editor's catalog); otherwise only the rows (a follow) need rebuilding.
  void _onLeaguesMaybeChanged() {
    final signature = _leagueIdsSignature();
    if (signature != _leagueSignature) {
      _leagueSignature = signature;
      final leagueIds = _leagues.map((league) => league.id).toSet();
      if (_scope != _scopeAll &&
          _scope != _scopeMyTeams &&
          !leagueIds.contains(_scope)) {
        _scope = _scopeAll;
      }
      unawaited(_load());
      return;
    }
    setState(_rebuildRows);
  }

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Local-day bounds of [range].
  static (DateTime, DateTime) _bounds(SportsRange range, DateTime now) {
    final midnight = DateTime(now.year, now.month, now.day);
    DateTime day(int offset) =>
        DateTime(midnight.year, midnight.month, midnight.day + offset);
    return switch (range) {
      SportsRange.yesterday => (day(-1), midnight),
      SportsRange.today => (midnight, day(1)),
      SportsRange.upcoming => (day(1), day(8)),
    };
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _refreshTimer?.cancel();
    final capability = _capability;
    final leagues = _leagues;
    if (capability == null || leagues.isEmpty) {
      setState(() {
        _fixtures = const [];
        _matches = const {};
        _loading = false;
        _loadFailed = false;
        _rebuildRows();
      });
      return;
    }
    final (from, to) = _bounds(_range, DateTime.now());
    final List<SportsFixture> fixtures;
    try {
      fixtures = await ref
          .read(sportsServiceProvider)
          .fixtures(
            capability: capability,
            leagues: leagues,
            from: from.toUtc(),
            to: to.toUtc(),
          );
    } on Object catch (error) {
      debugPrint('[Sports] fixtures load failed: $error');
      if (!mounted || generation != _loadGeneration) return;
      // A failed refresh keeps the games already shown; either way, try
      // again in a minute.
      setState(() {
        _loading = false;
        _loadFailed = _fixtures.isEmpty;
      });
      if (_isVisible) {
        _refreshTimer = Timer(_refreshInterval, () {
          if (mounted) unawaited(_load());
        });
      }
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _fixtures = fixtures;
      _loading = false;
      _loadFailed = false;
      _rebuildRows();
    });
    _scheduleRefresh();
    if (_watchableSignature(fixtures) != _resolvedSignature) {
      unawaited(_resolveChannels());
    }
  }

  String _watchableSignature(List<SportsFixture> fixtures) => [
    for (final fixture in fixtures)
      if (_isWatchable(fixture))
        '${fixture.league.id}:${fixture.id}@${fixture.start.millisecondsSinceEpoch}',
  ].join(',');

  /// Polls while a game is on or starts within the hour.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!_isVisible || _range == SportsRange.yesterday) return;
    final soon = DateTime.now().toUtc().add(const Duration(hours: 1));
    final active = _fixtures.any(
      (fixture) =>
          fixture.state == SportsFixtureState.live ||
          (fixture.state == SportsFixtureState.scheduled &&
              fixture.start.isBefore(soon)),
    );
    if (!active) return;
    _refreshTimer = Timer(_refreshInterval, () {
      if (mounted) unawaited(_load());
    });
  }

  /// Ties the loaded fixtures to channels. Runs again when the guide or the
  /// playlist changes, since either can add or remove a match.
  Future<void> _resolveChannels() {
    final generation = ++_resolveGeneration;
    final fixtures = _fixtures;
    _resolvedSignature = _watchableSignature(fixtures);
    final future = () async {
      if (mounted) setState(() => _resolving = true);
      try {
        final matches = await SportsChannelResolver(
          ref.read(catalogRepositoryProvider),
        ).resolve(fixtures);
        if (!mounted || generation != _resolveGeneration) return;
        setState(() => _matches = matches);
      } on Object catch (error) {
        debugPrint('[Sports] channel resolve failed: $error');
        if (generation == _resolveGeneration) _resolvedSignature = null;
      } finally {
        if (mounted && generation == _resolveGeneration) {
          setState(() => _resolving = false);
        }
      }
    }();
    _resolveInFlight = future;
    return future;
  }

  void _onGuideChanged() {
    if (!_isVisible || _fixtures.isEmpty) return;
    _guideChangeTimer?.cancel();
    _guideChangeTimer = Timer(_guideChangeDebounce, () {
      if (mounted) unawaited(_resolveChannels());
    });
  }

  // ---------------------------------------------------------------------------
  // Rows
  // ---------------------------------------------------------------------------

  void _rebuildRows() {
    final followed = _settings.followedTeamKeys;
    final query = SportsMatcher.normalize(_query).trim();
    final visible = [
      for (final fixture in _fixtures)
        if (_inScope(fixture, followed) && _matchesQuery(fixture, query))
          fixture,
    ];
    _rows = switch (_range) {
      SportsRange.upcoming => _groupByDay(visible),
      SportsRange.today => _groupByLeague(visible, liveFirst: true),
      SportsRange.yesterday => _groupByLeague(visible, liveFirst: false),
    };
  }

  bool _inScope(SportsFixture fixture, Set<String> followed) =>
      switch (_scope) {
        _scopeAll => true,
        _scopeMyTeams => fixture.involves(followed),
        final leagueId => fixture.league.id == leagueId,
      };

  static bool _matchesQuery(SportsFixture fixture, String query) {
    if (query.isEmpty) return true;
    for (final side in [fixture.home, fixture.away]) {
      if (side == null) continue;
      if (SportsMatcher.normalize(side.team.displayName).contains(query)) {
        return true;
      }
    }
    return false;
  }

  List<_SportsRow> _groupByLeague(
    List<SportsFixture> fixtures, {
    required bool liveFirst,
  }) {
    final rows = <_SportsRow>[];
    final live = liveFirst
        ? fixtures
              .where((fixture) => fixture.state == SportsFixtureState.live)
              .toList()
        : const <SportsFixture>[];
    if (live.isNotEmpty) {
      rows
        ..add(const _LiveHeaderRow())
        ..addAll(live.map((fixture) => _FixtureRow(fixture, showLeague: true)));
    }
    final byLeague = <String, List<SportsFixture>>{};
    for (final fixture in fixtures) {
      if (liveFirst && fixture.state == SportsFixtureState.live) continue;
      byLeague.putIfAbsent(fixture.league.id, () => []).add(fixture);
    }
    for (final league in _leagues) {
      final games = byLeague[league.id];
      if (games == null) continue;
      rows
        ..add(_LeagueHeaderRow(league))
        ..addAll(games.map(_FixtureRow.new));
    }
    return rows;
  }

  static List<_SportsRow> _groupByDay(List<SportsFixture> fixtures) {
    final rows = <_SportsRow>[];
    DateTime? currentDay;
    for (final fixture in fixtures) {
      final local = fixture.start.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (day != currentDay) {
        currentDay = day;
        rows.add(_DayHeaderRow(day));
      }
      rows.add(_FixtureRow(fixture, showLeague: true));
    }
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  bool _isWatchable(SportsFixture fixture) =>
      fixture.state == SportsFixtureState.live ||
      fixture.state == SportsFixtureState.scheduled;

  /// The fixture's channels, waiting out a resolve already under way so a
  /// press right after the list loads doesn't report "no channel".
  Future<List<SportsChannelMatch>> _matchesFor(SportsFixture fixture) async {
    if (_resolving) await _resolveInFlight;
    return _matches[fixture.id] ?? const [];
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFixture(SportsFixture fixture) async {
    final l10n = AppLocalizations.of(context);
    if (!_isWatchable(fixture)) {
      _showMessage(l10n.sportsGameOver);
      return;
    }
    final matches = await _matchesFor(fixture);
    if (!mounted) return;
    if (matches.isEmpty) {
      _showMessage(l10n.sportsNoChannelFound);
      return;
    }
    final match = matches.length == 1
        ? matches.single
        : await _pickChannel(fixture, matches);
    if (match != null && mounted) widget.onChannelSelect(match.channel);
  }

  Future<SportsChannelMatch?> _pickChannel(
    SportsFixture fixture,
    List<SportsChannelMatch> matches,
  ) {
    final l10n = AppLocalizations.of(context);
    return showAppDialog<SportsChannelMatch>(
      context: context,
      builder: (dialogContext) => AppMenuDialog(
        title: Text(
          sportsFixtureTitle(l10n, fixture),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          DpadRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < matches.length; i++)
                  AppMenuOption(
                    icon: Icons.live_tv,
                    label: matches[i].channel.name,
                    subtitle:
                        matches[i].program?.displayTitle ??
                        l10n.sportsEventChannel,
                    autofocus: i == 0,
                    onTap: () => Navigator.of(dialogContext).pop(matches[i]),
                  ),
                AppMenuOption(
                  icon: Icons.close,
                  label: l10n.cancel,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFixtureActions(SportsFixture fixture) async {
    final l10n = AppLocalizations.of(context);
    final matches = _isWatchable(fixture)
        ? await _matchesFor(fixture)
        : const <SportsChannelMatch>[];
    if (!mounted) return;
    final multiview = ref.read(multiviewControllerProvider);
    final inMultiview = matches
        .where((match) => multiview.contains(match.channel.id))
        .toList();
    final teams = [for (final side in fixture.displayOrder) side.team];

    final action = await showAppDialog<_FixtureAction>(
      context: context,
      builder: (dialogContext) {
        final inMultiviewAlready = inMultiview.isNotEmpty;
        final options = <(IconData, String, _FixtureAction?)>[
          if (matches.isNotEmpty)
            (Icons.play_arrow, l10n.sportsWatch, const _WatchAction()),
          if (multiviewSupported && matches.isNotEmpty && !inMultiviewAlready)
            (
              Icons.grid_view_outlined,
              l10n.liveTvAddMultiview,
              const _AddToMultiviewAction(),
            ),
          if (multiviewSupported && inMultiviewAlready)
            (
              Icons.grid_view,
              l10n.liveTvRemoveMultiview,
              const _RemoveFromMultiviewAction(),
            ),
          for (final team in teams)
            if (_settings.isFollowing(team.key))
              (
                Icons.star,
                l10n.sportsUnfollowTeam(team.displayName),
                _FollowAction(team),
              )
            else
              (
                Icons.star_border,
                l10n.sportsFollowTeam(team.displayName),
                _FollowAction(team),
              ),
          (Icons.close, l10n.cancel, null),
        ];
        return AppMenuDialog(
          title: Text(
            sportsFixtureTitle(l10n, fixture),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            DpadRegion(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (index, (icon, label, action)) in options.indexed)
                    AppMenuOption(
                      icon: icon,
                      label: label,
                      autofocus: index == 0,
                      onTap: () => Navigator.of(dialogContext).pop(action),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _WatchAction():
        await _openFixture(fixture);
      case _AddToMultiviewAction():
        final match = matches.length == 1
            ? matches.single
            : await _pickChannel(fixture, matches);
        if (match == null || !mounted) return;
        final added = ref
            .read(multiviewControllerProvider)
            .toggle(match.channel);
        _showMessage(
          added
              ? l10n.sportsAddedToMultiview(match.channel.name)
              : l10n.liveTvMultiviewFull,
        );
      case _RemoveFromMultiviewAction():
        for (final match in inMultiview) {
          multiview.remove(match.channel.id);
        }
      case _FollowAction(:final team):
        final following = await _settings.toggleFollow(team);
        if (!mounted) return;
        _showMessage(
          following
              ? l10n.sportsFollowingTeam(team.displayName)
              : l10n.sportsUnfollowedTeam(team.displayName),
        );
    }
  }

  Future<void> _showLeagues() async {
    final available = _capability?.leagues ?? const <SportsLeague>[];
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => AppMenuDialog(
            title: Text(l10n.sportsLeaguesTitle),
            children: [
              DpadRegion(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (index, league) in available.indexed)
                      AppMenuOption(
                        icon: _settings.isLeagueEnabled(league)
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        label: league.name,
                        autofocus: index == 0,
                        onTap: () => unawaited(
                          _settings.setLeagueEnabled(
                            league,
                            enabled: !_settings.isLeagueEnabled(league),
                            available: available,
                          ),
                        ),
                      ),
                    AppMenuOption(
                      icon: Icons.check,
                      label: l10n.sportsDone,
                      onTap: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openMultiview() async {
    widget.onEnterFullScreenDetail?.call();
    try {
      await Navigator.of(context).push<void>(
        appPageRoute<void>(builder: (context) => const MultiviewScreen()),
      );
    } finally {
      widget.onExitFullScreenDetail?.call();
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    ref.listen(epgServiceProvider, (_, _) => _onGuideChanged());
    ref.listen(sportsCapabilityProvider, (_, _) => _onLeaguesMaybeChanged());
    ref.listen(shownPlaylistKeyProvider, (_, _) {
      if (_fixtures.isNotEmpty) unawaited(_resolveChannels());
    });

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            l10n.appNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final nav = MediaCategoryNav(
      key: _navKey,
      useSidebarLayout: widget.useSidebarLayout,
      query: _query,
      onQueryChanged: (value) {
        if (value == _query) return;
        setState(() {
          _query = value;
          _rebuildRows();
        });
      },
      searchHint: l10n.sportsSearchHint,
      tabs: [
        CategoryTabData(id: _scopeMyTeams, name: l10n.sportsScopeMyTeams),
        CategoryTabData(id: _scopeAll, name: l10n.sportsScopeAll),
        for (final league in _leagues)
          CategoryTabData(id: league.id, name: league.name),
      ],
      selectedId: _scope,
      onSelected: (id) => setState(() {
        _scope = id;
        _rebuildRows();
      }),
      filterButtonLabel: l10n.mediaCategoryFilterButton,
      filterScreenTitle: l10n.mediaCategoryFilterScreenTitle,
      trailing: _buildMultiviewButton(l10n),
      extraActions: [
        AppButton(
          icon: Icons.tune,
          label: l10n.sportsLeaguesButton,
          onPressed: () => unawaited(_showLeagues()),
        ),
      ],
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _listFocusNode,
      memoryKeyPrefix: 'sports',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
      onTopEdge: () => _tabBarKey.currentState?.requestFocus(),
    );
    final content = Expanded(child: _buildContent(l10n));

    return Scaffold(
      body: DpadRegion(
        memoryKey: 'sports/screen',
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            widget.onSidebarActivate?.call();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DpadTabBar(
              key: _tabBarKey,
              controller: _tabController,
              tabs: [
                l10n.sportsRangeYesterday,
                l10n.sportsRangeToday,
                l10n.sportsRangeUpcoming,
              ],
            ),
            Expanded(
              child: widget.useSidebarLayout
                  ? Row(children: [nav, content])
                  : Column(children: [nav, content]),
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildMultiviewButton(AppLocalizations l10n) {
    final count = ref.watch(multiviewChannelsProvider).length;
    if (!multiviewSupported || count == 0) return null;
    return AppButton(
      icon: Icons.grid_view,
      badgeCount: count,
      label: l10n.multiviewTitle,
      onPressed: () => unawaited(_openMultiview()),
      onLongPress: () => unawaited(showMultiviewManageDialog(context)),
    );
  }

  Widget _buildContent(AppLocalizations l10n) {
    if (_loading) return const Center(child: AppLoadingIndicator());
    final String? empty;
    if (_capability == null) {
      empty = l10n.sportsUnavailable;
    } else if (_loadFailed) {
      empty = l10n.sportsLoadFailed;
    } else if (_leagues.isEmpty) {
      empty = l10n.sportsNoLeagues;
    } else if (_scope == _scopeMyTeams && _settings.followedTeams.isEmpty) {
      empty = l10n.sportsMyTeamsEmpty;
    } else if (_rows.isEmpty) {
      empty = _scope == _scopeMyTeams
          ? l10n.sportsMyTeamsNoGames
          : l10n.sportsNoGames;
    } else {
      empty = null;
    }
    if (empty != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          child: Text(
            empty,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final multiviewIds = {
      for (final channel in ref.watch(multiviewChannelsProvider)) channel.id,
    };
    return FocusScope(
      node: _listFocusNode,
      child: DpadRegion(
        memoryKey: 'sports/list',
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction != TraversalDirection.left) return;
          if (widget.useSidebarLayout) {
            _navKey.currentState?.requestFocus();
          } else {
            widget.onSidebarActivate?.call();
          }
        },
        child: ScrollbarListView(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          itemCount: _rows.length,
          itemBuilder: (context, index) => switch (_rows[index]) {
            _LiveHeaderRow() => _SectionHeader(title: l10n.sportsLiveNow),
            _LeagueHeaderRow(:final league) => _SectionHeader(
              title: league.name,
            ),
            _DayHeaderRow(:final day) => _SectionHeader(
              title: DateFormat.MMMMEEEEd(
                Localizations.localeOf(context).toLanguageTag(),
              ).format(day),
            ),
            _FixtureRow(:final fixture, :final showLeague) => _buildCard(
              fixture,
              showLeague: showLeague,
              multiviewIds: multiviewIds,
            ),
          },
        ),
      ),
    );
  }

  Widget _buildCard(
    SportsFixture fixture, {
    required bool showLeague,
    required Set<int> multiviewIds,
  }) {
    final watchable = _isWatchable(fixture);
    final matches = _matches[fixture.id] ?? const <SportsChannelMatch>[];
    return SportsFixtureCard(
      key: ValueKey('${fixture.league.id}:${fixture.id}'),
      fixture: fixture,
      channelCount: watchable ? matches.length : null,
      isResolving: _resolving,
      showLeague: showLeague,
      inMultiview: matches.any(
        (match) => multiviewIds.contains(match.channel.id),
      ),
      onTap: () => unawaited(_openFixture(fixture)),
      onLongTap: () => unawaited(_showFixtureActions(fixture)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return Padding(
      padding: EdgeInsets.only(top: 12 * scale, bottom: 10 * scale),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

sealed class _SportsRow {
  const _SportsRow();
}

class _LiveHeaderRow extends _SportsRow {
  const _LiveHeaderRow();
}

class _LeagueHeaderRow extends _SportsRow {
  const _LeagueHeaderRow(this.league);

  final SportsLeague league;
}

class _DayHeaderRow extends _SportsRow {
  const _DayHeaderRow(this.day);

  final DateTime day;
}

class _FixtureRow extends _SportsRow {
  const _FixtureRow(this.fixture, {this.showLeague = false});

  final SportsFixture fixture;
  final bool showLeague;
}

sealed class _FixtureAction {
  const _FixtureAction();
}

class _WatchAction extends _FixtureAction {
  const _WatchAction();
}

class _AddToMultiviewAction extends _FixtureAction {
  const _AddToMultiviewAction();
}

class _RemoveFromMultiviewAction extends _FixtureAction {
  const _RemoveFromMultiviewAction();
}

class _FollowAction extends _FixtureAction {
  const _FollowAction(this.team);

  final SportsTeam team;
}
