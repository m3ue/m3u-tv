import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/multiview/multiview_controller.dart';
import 'package:m3u_tv/features/multiview/multiview_manage_dialog.dart';
import 'package:m3u_tv/features/multiview/multiview_screen.dart';
import 'package:m3u_tv/features/sports/sports_fixture_actions.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/features/sports/sports_fixture_details_screen.dart';
import 'package:m3u_tv/features/sports/sports_teams_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_matcher.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_menu_dialog.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/day_toolbar.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';
import 'package:material_ui/material_ui.dart';

/// One day's games from the followed competitions, each tied to the channels
/// in the active playlist that carry it, so a game is one press from playing
/// or from joining Multiview.
///
/// Games and channels both come from M3U Editor ([sportsServiceProvider]). The
/// games show first; finding their channels can take longer on a big playlist.
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
    this.onHandleTopLevelBack,
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

  /// `AppShellState.handleBackFromTopLevelRoute`, for pages this screen opens
  /// on the root Navigator.
  final bool Function()? onHandleTopLevelBack;

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  static const String _scopeAll = '';
  static const String _scopeMyTeams = '__my_teams__';
  static const Duration _refreshInterval = Duration(minutes: 1);

  /// Skipping through several days sends one request.
  static const Duration _dayChangeDebounce = Duration(milliseconds: 300);
  static const int _daysBack = 7;
  static const int _daysAhead = 14;

  final FocusScopeNode _listFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();
  final FocusNode _nowFocusNode = FocusNode(debugLabel: 'sports-now');

  late final SportsSettings _settings = ref.read(sportsSettingsProvider);
  String _scope = _scopeAll;
  late String _leagueSignature = _leagueIdsSignature();
  String _query = '';
  DateTime _selectedDay = _dateOnly(DateTime.now());

  List<SportsFixture> _fixtures = const [];
  bool _loading = true;

  /// The last load failed with nothing loaded before it to keep showing.
  bool _loadFailed = false;
  int _loadGeneration = 0;
  Map<String, List<SportsChannelMatch>> _matches = const {};
  bool _channelsLoading = false;
  Future<void>? _channelsInFlight;
  int _channelsGeneration = 0;

  /// The day and leagues [_matches] covers. A score refresh reuses it until
  /// [kSportsChannelsMaxAge]; a playlist change clears it.
  String? _channelsFor;
  DateTime? _channelsFetchedAt;
  List<_SportsRow> _rows = const [];

  Timer? _refreshTimer;
  Timer? _dayChangeTimer;
  ValueListenable<TickerModeData>? _tickerModeNotifier;

  static DateTime _dateOnly(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  static DateTime _offsetDay(DateTime day, int days) =>
      DateTime(day.year, day.month, day.day + days);

  bool get _isVisible => _tickerModeNotifier?.value.enabled ?? true;

  @override
  void initState() {
    super.initState();
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
    _dayChangeTimer?.cancel();
    _nowFocusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (_isVisible) {
      unawaited(_load());
    } else {
      _refreshTimer?.cancel();
      _dayChangeTimer?.cancel();
    }
  }

  /// Shows [day], loading it once the viewer stops pressing.
  void _selectDay(DateTime day) {
    if (day == _selectedDay) return;
    _refreshTimer?.cancel();
    _dayChangeTimer?.cancel();
    _loadGeneration++;
    _channelsGeneration++;
    setState(() {
      _selectedDay = day;
      _fixtures = const [];
      _matches = const {};
      _channelsFor = null;
      _channelsFetchedAt = null;
      _channelsInFlight = null;
      _channelsLoading = false;
      _rows = const [];
      _loading = true;
      _loadFailed = false;
    });
    _dayChangeTimer = Timer(_dayChangeDebounce, () {
      if (mounted) unawaited(_load());
    });
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

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _refreshTimer?.cancel();
    _dayChangeTimer?.cancel();
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
    final from = _selectedDay.toUtc();
    final to = _offsetDay(_selectedDay, 1).toUtc();
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
    _loadChannels(capability, leagues, from, to);
  }

  /// Polls while a game is on or starts within the hour.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    if (!_isVisible) return;
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

  /// Fetches the day's channels, unless [_matches] is recent enough or nothing
  /// left on the day can be watched.
  void _loadChannels(
    SportsCapability capability,
    List<SportsLeague> leagues,
    DateTime from,
    DateTime to,
  ) {
    final channelsFor = [
      from.millisecondsSinceEpoch,
      for (final league in leagues) league.id,
    ].join(',');
    final fetchedAt = _channelsFetchedAt;
    final isFresh =
        channelsFor == _channelsFor &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < kSportsChannelsMaxAge;
    if (isFresh || !_fixtures.any(_isWatchable)) return;
    final generation = ++_channelsGeneration;
    _channelsFor = channelsFor;
    _channelsFetchedAt = DateTime.now();
    _channelsInFlight = () async {
      setState(() => _channelsLoading = true);
      try {
        final matches = await loadSportsChannelMatches(
          service: ref.read(sportsServiceProvider),
          repository: ref.read(catalogRepositoryProvider),
          capability: capability,
          leagues: leagues,
          from: from,
          to: to,
        );
        if (!mounted || generation != _channelsGeneration) return;
        setState(() => _matches = matches);
      } on Object catch (error) {
        debugPrint('[Sports] channels load failed: $error');
        // Try again on the next refresh
        if (generation == _channelsGeneration) _channelsFor = null;
      } finally {
        if (mounted && generation == _channelsGeneration) {
          setState(() => _channelsLoading = false);
        }
      }
    }();
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
    _rows = _groupByLeague(visible);
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

  List<_SportsRow> _groupByLeague(List<SportsFixture> fixtures) {
    final rows = <_SportsRow>[];
    final live = fixtures
        .where((fixture) => fixture.state == SportsFixtureState.live)
        .toList();
    if (live.isNotEmpty) {
      rows
        ..add(const _LiveHeaderRow())
        ..addAll(live.map((fixture) => _FixtureRow(fixture, showLeague: true)));
    }
    final byLeague = <String, List<SportsFixture>>{};
    for (final fixture in fixtures) {
      if (fixture.state == SportsFixtureState.live) continue;
      byLeague.putIfAbsent(fixture.league.id, () => []).add(fixture);
    }
    for (final league in _leagues) {
      final games = byLeague[league.id];
      if (games == null) continue;
      rows
        ..add(_LeagueHeaderRow(league, logoUrl: games.first.leagueLogoUrl))
        ..addAll(games.map(_FixtureRow.new));
    }
    return rows;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  bool _isWatchable(SportsFixture fixture) => isSportsFixtureWatchable(fixture);

  /// The fixture's channels, waiting out a load already under way so a press
  /// right after the list loads doesn't report "no channel".
  Future<List<SportsChannelMatch>> _matchesFor(SportsFixture fixture) async {
    if (_channelsLoading) await _channelsInFlight;
    return _matches[fixture.key] ?? const [];
  }

  /// D-pad Up at the top of the list's focus scope: scrolls the rest of the
  /// way up first, then moves to the date bar.
  void _moveUpFromList() {
    if (!scrollFocusedContentPageUp()) _nowFocusNode.requestFocus();
  }

  /// Moves into the games, when there are any on screen.
  bool _enterList() {
    if (_listFocusNode.context == null ||
        _listFocusNode.traversalDescendants.isEmpty) {
      return false;
    }
    _listFocusNode.requestFocus();
    return true;
  }

  /// D-pad Right from the filter strip: the games, or the date bar on a day
  /// with none, so another day is still within reach.
  void _enterContent() {
    if (!_enterList()) _nowFocusNode.requestFocus();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFixture(SportsFixture fixture) async {
    final matches = _isWatchable(fixture)
        ? await _matchesFor(fixture)
        : const <SportsChannelMatch>[];
    if (!mounted) return;
    await openSportsFixture(
      context,
      fixture: fixture,
      matches: matches,
      onChannelSelect: widget.onChannelSelect,
      onBack: widget.onHandleTopLevelBack,
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
          (Icons.info_outline, l10n.sportsViewDetails, const _DetailsAction()),
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
      case _DetailsAction():
        await openSportsFixtureDetails(
          context,
          fixture: fixture,
          matches: matches,
          onChannelSelect: widget.onChannelSelect,
          onBack: widget.onHandleTopLevelBack,
        );
      case _AddToMultiviewAction():
        final match = matches.length == 1
            ? matches.single
            : await pickSportsChannel(context, fixture, matches);
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
    final bySport = <String, List<SportsLeague>>{};
    for (final league in available) {
      (bySport[league.sport] ??= []).add(league);
    }
    if (bySport.length <= 1) {
      return _showLeagueOptions(available, available: available);
    }
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => AppMenuDialog(
            title: Text(l10n.sportsLeaguesTitle),
            width: _pickerWidth,
            children: [
              DpadRegion(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._inColumns([
                      for (final (index, leagues) in bySport.values.indexed)
                        AppMenuOption(
                          icon: _sportIcon(leagues.first.sport),
                          label: leagues.first.sportName,
                          subtitle: l10n.sportsLeaguesShownCount(
                            leagues.where(_settings.isLeagueEnabled).length,
                            leagues.length,
                          ),
                          autofocus: index == 0,
                          onTap: () => unawaited(
                            _showLeagueOptions(
                              leagues,
                              available: available,
                              title: leagues.first.sportName,
                            ),
                          ),
                        ),
                    ]),
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

  /// Checkboxes for [leagues]; [available] is the whole catalog, which
  /// the settings need to turn the defaults into explicit picks.
  Future<void> _showLeagueOptions(
    List<SportsLeague> leagues, {
    required List<SportsLeague> available,
    String? title,
  }) async {
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => AppMenuDialog(
            title: Text(title ?? l10n.sportsLeaguesTitle),
            width: _pickerWidth,
            children: [
              DpadRegion(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ..._inColumns([
                      for (final (index, league) in leagues.indexed)
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
                    ]),
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

  /// The league pickers' width: room for two columns of options.
  static const double _pickerWidth = 640;

  /// [options] two to a row, so long pickers (220 soccer leagues) scroll
  /// half as far. Rows stay aligned for D-pad up/down. One to a row where
  /// the dialog is too narrow for two to fit their labels (phones).
  List<Widget> _inColumns(List<Widget> options) => [
    if (MediaQuery.sizeOf(context).width < _pickerWidth)
      ...options
    else
      for (var i = 0; i < options.length; i += 2)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: options[i]),
            Expanded(
              child: i + 1 < options.length
                  ? options[i + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
  ];

  static IconData _sportIcon(String sport) => switch (sport) {
    'football' => Icons.sports_football,
    'basketball' => Icons.sports_basketball,
    'baseball' => Icons.sports_baseball,
    'hockey' || 'field-hockey' => Icons.sports_hockey,
    'soccer' => Icons.sports_soccer,
    'rugby' || 'rugby-league' || 'australian-football' => Icons.sports_rugby,
    'volleyball' => Icons.sports_volleyball,
    'cricket' => Icons.sports_cricket,
    'handball' => Icons.sports_handball,
    _ => Icons.sports,
  };

  Future<void> _openTeams() => openSportsTeams(
    context,
    useSidebarLayout: widget.useSidebarLayout,
    initialLeagueId: _scope == _scopeAll || _scope == _scopeMyTeams
        ? null
        : _scope,
    onBack: widget.onHandleTopLevelBack,
  );

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
    ref.listen(sportsCapabilityProvider, (_, _) => _onLeaguesMaybeChanged());
    ref.listen(shownPlaylistKeyProvider, (_, _) {
      _channelsFor = null;
      _matches = const {};
      if (_fixtures.isNotEmpty) unawaited(_load());
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
        CategoryTabData(id: _scopeAll, name: l10n.sportsScopeAll),
        CategoryTabData(id: _scopeMyTeams, name: l10n.sportsScopeMyTeams),
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
        if (ref.watch(sportsCapabilityProvider)?.listsTeams ?? false)
          AppButton(
            icon: Icons.groups,
            label: l10n.sportsTeamsButton,
            onPressed: () => unawaited(_openTeams()),
          ),
      ],
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _listFocusNode,
      memoryKeyPrefix: 'sports',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
      onGridEdgeEnter: _enterContent,
    );
    final content = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDayToolbar(l10n),
          Expanded(child: _buildContent(l10n)),
        ],
      ),
    );

    return Scaffold(
      body: DpadRegion(
        memoryKey: 'sports/screen',
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            widget.onSidebarActivate?.call();
          }
        },
        child: widget.useSidebarLayout
            ? Row(children: [nav, content])
            : Column(children: [nav, content]),
      ),
    );
  }

  Widget _buildDayToolbar(AppLocalizations l10n) {
    final today = _dateOnly(DateTime.now());
    return DpadRegion(
      memoryKey: 'sports/days',
      horizontalEdge: DpadEdgeBehavior.stop,
      verticalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.down) {
          _enterList();
        } else if (direction == TraversalDirection.left) {
          if (widget.useSidebarLayout) {
            _navKey.currentState?.requestFocus();
          } else {
            widget.onSidebarActivate?.call();
          }
        } else if (direction == TraversalDirection.up &&
            !widget.useSidebarLayout) {
          _navKey.currentState?.requestFocus();
        }
      },
      child: DayToolbar(
        keyPrefix: 'sports',
        nowFocusNode: _nowFocusNode,
        nowLabel: l10n.epgToday,
        selectedDate: _selectedDay,
        today: today,
        compact: !widget.useSidebarLayout,
        canGoPrevious: _selectedDay.isAfter(_offsetDay(today, -_daysBack)),
        canGoNext: _selectedDay.isBefore(_offsetDay(today, _daysAhead)),
        onPrevious: () => _selectDay(_offsetDay(_selectedDay, -1)),
        onNow: () => _selectDay(today),
        onNext: () => _selectDay(_offsetDay(_selectedDay, 1)),
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
        // The date bar sits outside this scope, beyond plain traversal
        upEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.up) {
            _moveUpFromList();
            return;
          }
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
            _LeagueHeaderRow(:final league, :final logoUrl) => _SectionHeader(
              title: league.name,
              logoUrl: logoUrl,
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
    final matches = _matches[fixture.key] ?? const <SportsChannelMatch>[];
    return SportsFixtureCard(
      key: ValueKey('${fixture.league.id}:${fixture.id}'),
      fixture: fixture,
      channelCount: watchable ? matches.length : null,
      isResolving: _channelsLoading,
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
  const _SectionHeader({required this.title, this.logoUrl});

  final String title;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final logoUrl = this.logoUrl;
    return Padding(
      padding: EdgeInsets.only(top: 12 * scale, bottom: 10 * scale),
      child: Row(
        children: [
          if (logoUrl != null) ...[
            SportsTeamLogo(url: logoUrl, size: 28 * scale),
            SizedBox(width: 10 * scale),
          ],
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
  const _LeagueHeaderRow(this.league, {this.logoUrl});

  final SportsLeague league;
  final String? logoUrl;
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

class _DetailsAction extends _FixtureAction {
  const _DetailsAction();
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
