import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/sports/sports_fixture_actions.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/desktop_fullscreen_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/app_top_bar.dart';
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';
import 'package:m3u_tv/shared/desktop_back_key.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/draggable_text.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

class _SportsDetailsPopIntent extends Intent {
  const _SportsDetailsPopIntent();
}

/// Pushes [SportsFixtureDetailsScreen] over the shell. Out on the root
/// Navigator AppShell's Back handling can't reach it, so it brings its own,
/// through [onBack] (`AppShellState.handleBackFromTopLevelRoute`) when given.
Future<void> openSportsFixtureDetails(
  BuildContext context, {
  required SportsFixture fixture,
  required List<SportsChannelMatch> matches,
  required ValueChanged<Channel> onChannelSelect,
  bool Function()? onBack,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    appPageRoute<void>(
      builder: (context) {
        final screen = Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            LogicalKeySet(LogicalKeyboardKey.escape):
                const _SportsDetailsPopIntent(),
            const DesktopBackspaceActivator(): const _SportsDetailsPopIntent(),
            LogicalKeySet(LogicalKeyboardKey.goBack):
                const _SportsDetailsPopIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _SportsDetailsPopIntent: CallbackAction<_SportsDetailsPopIntent>(
                onInvoke: (_) {
                  if (onBack != null) {
                    onBack();
                  } else {
                    Navigator.of(context, rootNavigator: true).maybePop();
                  }
                  return null;
                },
              ),
            },
            child: SportsFixtureDetailsScreen(
              fixture: fixture,
              matches: matches,
              onChannelSelect: onChannelSelect,
            ),
          ),
        );
        return HostPlatform.isTvOS
            ? MediaQuery.removePadding(
                context: context,
                removeTop: true,
                removeBottom: true,
                removeLeft: true,
                removeRight: true,
                child: screen,
              )
            : screen;
      },
    ),
  );
}

/// One game: both teams with their scores and follow buttons, the channels
/// carrying it, then score by period, key moments, team stats, top performers
/// and game info, as far as the editor's provider has them. Stays current while
/// the game is on.
class SportsFixtureDetailsScreen extends ConsumerStatefulWidget {
  const SportsFixtureDetailsScreen({
    super.key,
    required this.fixture,
    required this.matches,
    required this.onChannelSelect,
  });

  final SportsFixture fixture;

  /// The channels carrying the game, listed while it can still be watched.
  final List<SportsChannelMatch> matches;
  final ValueChanged<Channel> onChannelSelect;

  @override
  ConsumerState<SportsFixtureDetailsScreen> createState() =>
      _SportsFixtureDetailsScreenState();
}

class _SportsFixtureDetailsScreenState
    extends ConsumerState<SportsFixtureDetailsScreen> {
  /// The editor caches a live game's details for about this long.
  static const Duration _refreshInterval = Duration(seconds: 30);

  /// The least room, in units of the viewer's font size, for the scoreboard
  /// and columns. Anything less (phones, portrait) keeps the single column.
  static const double _columnsMinWidth = 900;
  static const double _columnsMinHeight = 480;

  /// Keeps the columns readable on very wide windows.
  static const double _columnsMaxWidth = 1600;

  final GlobalKey<_ReadingPaneState> _leftPane = GlobalKey();
  final GlobalKey<_ReadingPaneState> _rightPane = GlobalKey();

  late SportsFixture _fixture = widget.fixture;
  SportsFixtureDetails? _details;
  bool _isLoading = true;
  bool _loadFailed = false;
  Timer? _refreshTimer;

  bool get _canWatch =>
      widget.matches.isNotEmpty && isSportsFixtureWatchable(_fixture);

  bool get _changesSoon =>
      _fixture.state == SportsFixtureState.live ||
      (_fixture.state == SportsFixtureState.scheduled &&
          _fixture.start.isBefore(
            DateTime.now().toUtc().add(const Duration(minutes: 30)),
          ));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final capability = ref.read(sportsCapabilityProvider);
    if (capability == null) {
      _isLoading = false;
      return;
    }
    SportsFixtureDetails? details;
    var failed = false;
    try {
      details = await ref
          .read(sportsServiceProvider)
          .details(capability: capability, fixture: _fixture);
    } on Object catch (error) {
      debugPrint('[Sports] details for ${_fixture.key} failed: $error');
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadFailed = failed && _details == null;
      // A failed refresh keeps what's on screen
      if (details != null) {
        _details = details;
        final fresh = details.fixture;
        if (fresh != null) _fixture = _withListedExtras(fresh);
      }
    });
    if (failed || _changesSoon) {
      _refreshTimer = Timer(_refreshInterval, () => unawaited(_load()));
    }
  }

  /// What a game's details leave out and its list entry has.
  SportsFixture _withListedExtras(SportsFixture fresh) => SportsFixture(
    id: fresh.id,
    league: fresh.league,
    start: fresh.start,
    state: fresh.state,
    statusDetail: fresh.statusDetail,
    home: fresh.home,
    away: fresh.away,
    name: fresh.name ?? _fixture.name,
    broadcasts: fresh.broadcasts.isEmpty
        ? _fixture.broadcasts
        : fresh.broadcasts,
    leagueLogoUrl: fresh.leagueLogoUrl ?? _fixture.leagueLogoUrl,
  );

  void _watch(SportsChannelMatch match) {
    // The player opens from the shell, beneath this page
    Navigator.of(context).pop();
    widget.onChannelSelect(match.channel);
  }

  bool _usesColumns(double scale) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height &&
        size.width >= _columnsMinWidth * scale &&
        size.height >= _columnsMinHeight * scale;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final usesColumns = _usesColumns(scale);
    final theme = Theme.of(context);
    final wash = [
      for (final side in _fixture.displayOrder) sportsTeamWash(side.team),
    ];
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: wash.length == 2 ? LinearGradient(colors: wash) : null,
        ),
        // Clear, so the wash runs up behind the top bar too
        child: Theme(
          data: theme.copyWith(
            appBarTheme: theme.appBarTheme.copyWith(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppTopBar(
              // The scoreboard has no line of its own for the league
              title: usesColumns
                  ? _LeagueLabel(fixture: _fixture)
                  : Text(l10n.sportsDetailsTitle),
              scale: scale,
              leadingInset:
                  HostPlatform.isMacOS &&
                      !DesktopFullscreenScope.isFullscreenOf(context)
                  ? 72.0
                  : 0.0,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            body: SafeArea(
              top: false,
              child: usesColumns
                  ? _buildColumns(l10n, scale)
                  : _buildSingleColumn(l10n, scale),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelsSection(
    AppLocalizations l10n,
    VoidCallback scrollToTop,
  ) => _Section(
    title: l10n.sportsDetailsOnYourChannels,
    child: _ChannelList(
      matches: widget.matches,
      onWatch: _watch,
      onFirstRowFocused: scrollToTop,
    ),
  );

  Widget _buildSingleColumn(AppLocalizations l10n, double scale) {
    final canWatch = _canWatch;
    final sections = _sections(l10n);
    return _ReadingPane(
      padding: const EdgeInsets.fromLTRB(
        MediaBrowsingMetrics.pagePadding,
        8,
        MediaBrowsingMetrics.pagePadding,
        24,
      ),
      maxContentWidth: 860 * scale,
      autofocus: !canWatch,
      leading: (scrollToTop) => [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (hasFocus) {
            if (hasFocus) scrollToTop();
          },
          child: _Matchup(
            fixture: _fixture,
            sides: _SidePair.of(_fixture),
            details: _details,
          ),
        ),
        if (canWatch) _buildChannelsSection(l10n, scrollToTop),
      ],
      sections: [
        ...sections.status,
        ?sections.lineScore,
        ?sections.events,
        ?sections.stats,
        ?sections.leaders,
        ?sections.info,
      ],
    );
  }

  /// The scoreboard over two columns, which scroll separately: what can be
  /// acted on or changes most on the left, the numbers on the right. Game info
  /// goes left too, under the shorter column, unless it's all there is.
  Widget _buildColumns(AppLocalizations l10n, double scale) {
    final canWatch = _canWatch;
    final hasTeams = _fixture.hasTeams;
    final isLive = _fixture.state == SportsFixtureState.live;
    final sections = _sections(l10n, newestEventsFirst: isLive);
    final infoOnLeft = sections.stats != null || sections.leaders != null;
    final left = [
      ...sections.status,
      ?sections.events,
      if (infoOnLeft) ?sections.info,
    ];
    final right = [
      ?sections.stats,
      ?sections.leaders,
      if (!infoOnLeft) ?sections.info,
    ];
    final hasLeft = canWatch || left.isNotEmpty;
    final hasRight = right.isNotEmpty;
    final gutter = 10 * scale;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _columnsMaxWidth * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MediaBrowsingMetrics.pagePadding,
              ),
              child: _Scoreboard(
                fixture: _fixture,
                sides: _SidePair.of(_fixture),
                details: _details,
                // An empty focus target would hide where focus is
                autofocusFollow: !canWatch && hasTeams,
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasLeft)
                    Expanded(
                      key: const ValueKey('sports-details-left'),
                      child: _ReadingPane(
                        key: _leftPane,
                        padding: EdgeInsets.fromLTRB(
                          MediaBrowsingMetrics.pagePadding,
                          0,
                          hasRight ? gutter : MediaBrowsingMetrics.pagePadding,
                          24,
                        ),
                        onSideways: _moveBetweenPanes,
                        autofocus: !canWatch && !hasTeams,
                        leading: (scrollToTop) => [
                          if (canWatch)
                            _buildChannelsSection(l10n, scrollToTop),
                        ],
                        sections: left,
                      ),
                    ),
                  if (hasRight)
                    Expanded(
                      key: const ValueKey('sports-details-right'),
                      child: _ReadingPane(
                        key: _rightPane,
                        padding: EdgeInsets.fromLTRB(
                          hasLeft ? gutter : MediaBrowsingMetrics.pagePadding,
                          0,
                          MediaBrowsingMetrics.pagePadding,
                          24,
                        ),
                        onSideways: _moveBetweenPanes,
                        leading: (_) => const [],
                        sections: right,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _moveBetweenPanes(TraversalDirection direction) {
    final target = direction == TraversalDirection.left
        ? _leftPane
        : _rightPane;
    target.currentState?.enter();
  }

  /// The game's sections, each null when there's nothing to put in it.
  ({
    List<Widget> status,
    Widget? lineScore,
    Widget? events,
    Widget? stats,
    Widget? leaders,
    Widget? info,
  })
  _sections(AppLocalizations l10n, {bool newestEventsFirst = false}) {
    final details = _details;
    final sides = _SidePair.of(_fixture);
    final isUpcoming = _fixture.state == SportsFixtureState.scheduled;
    final lineScore = details?.lineScore;
    final infoRows = _infoRows(l10n, details);
    final message = _loadFailed
        ? l10n.sportsDetailsLoadFailed
        : !_isLoading && details == null
        ? l10n.sportsDetailsUnavailable
        : null;
    return (
      status: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: AppLoadingIndicator()),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
      lineScore: lineScore == null
          ? null
          : _Section(
              title: l10n.sportsDetailsLineScore,
              child: _LineScoreTable(lineScore: lineScore, sides: sides),
            ),
      events: details == null || details.events.isEmpty
          ? null
          : _Section(
              title: l10n.sportsDetailsEvents,
              child: _EventList(
                events: newestEventsFirst
                    ? details.events.reversed.toList()
                    : details.events,
                sides: sides,
              ),
            ),
      stats: details == null || details.stats.isEmpty
          ? null
          : _Section(
              // Before a game, the provider's numbers are its season so far
              title: isUpcoming
                  ? l10n.sportsDetailsSeasonStats
                  : l10n.sportsDetailsStats,
              child: _StatList(stats: details.stats, sides: sides),
            ),
      leaders: details == null || details.leaders.isEmpty
          ? null
          : _Section(
              title: isUpcoming
                  ? l10n.sportsDetailsSeasonLeaders
                  : l10n.sportsDetailsLeaders,
              child: _LeaderList(categories: details.leaders, sides: sides),
            ),
      info: infoRows.isEmpty
          ? null
          : _Section(
              title: l10n.sportsDetailsInfo,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: infoRows,
              ),
            ),
    );
  }

  List<Widget> _infoRows(
    AppLocalizations l10n,
    SportsFixtureDetails? details,
  ) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final venue = [
      details?.venue,
      details?.location,
    ].whereType<String>().join(', ');
    final attendance = details?.attendance;
    final broadcasts = _fixture.broadcasts;
    final officials = details?.officials ?? const <String>[];
    final series = details?.series;
    return [
      _InfoRow(
        label: l10n.sportsDetailsStart,
        value: DateFormat.yMMMEd(
          locale,
        ).add_jm().format(_fixture.start.toLocal()),
      ),
      if (venue.isNotEmpty)
        _InfoRow(label: l10n.sportsDetailsVenue, value: venue),
      if (attendance != null)
        _InfoRow(
          label: l10n.sportsDetailsAttendance,
          value: NumberFormat.decimalPattern(locale).format(attendance),
        ),
      if (broadcasts.isNotEmpty)
        _InfoRow(
          label: l10n.sportsDetailsBroadcast,
          value: broadcasts.join(', '),
        ),
      if (series != null)
        _InfoRow(label: l10n.sportsDetailsSeries, value: series),
      if (officials.isNotEmpty)
        _InfoRow(
          label: l10n.sportsDetailsOfficials,
          value: officials.join(', '),
        ),
    ];
  }
}

/// A scrolling stretch of the page: [leading] focusable content, then
/// [sections], which can't hold focus themselves, so one focus target covers
/// them and Up and Down read through them.
class _ReadingPane extends StatefulWidget {
  const _ReadingPane({
    super.key,
    required this.padding,
    required this.leading,
    required this.sections,
    this.maxContentWidth,
    this.autofocus = false,
    this.onSideways,
  });

  final EdgeInsets padding;

  /// Given a callback for focus landing on the top of the pane. Whatever
  /// triggers it needs `autoScroll: false`, or its partial reveal overrides
  /// the animation and the pane stops short of the top.
  final List<Widget> Function(VoidCallback scrollToTop) leading;
  final List<Widget> sections;
  final double? maxContentWidth;
  final bool autofocus;

  /// Set on panes side by side, for Left and Right from the sections. Plain
  /// traversal can't be trusted there: it measures from the centre of a target
  /// that may be far taller than the screen. The sections also only take focus
  /// when there's something to scroll to.
  final ValueChanged<TraversalDirection>? onSideways;

  @override
  State<_ReadingPane> createState() => _ReadingPaneState();
}

class _ReadingPaneState extends State<_ReadingPane> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _readingKey = GlobalKey();
  final FocusNode _contentNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );
  bool _isReading = false;
  bool _canScroll = false;

  /// Focuses the first thing in the pane, if there's anything to focus.
  void enter() => _contentNode.traversalDescendants.firstOrNull?.requestFocus();

  @override
  void dispose() {
    _contentNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  double get _scrollStep =>
      (_scrollController.position.viewportDimension * 0.4).clamp(120.0, 400.0);

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  /// Whether the top of the sections is on screen, so Up has nothing left to
  /// read and can move on.
  bool get _readingTopVisible {
    final box = _readingKey.currentContext?.findRenderObject();
    if (box == null || !_scrollController.hasClients) return true;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    return _scrollController.position.pixels <= top + 0.5;
  }

  bool _onReadingDirection(TraversalDirection direction) {
    if (!_scrollController.hasClients) return true;
    switch (direction) {
      case TraversalDirection.up:
        if (_readingTopVisible) return false;
        _scrollBy(-_scrollStep);
      case TraversalDirection.down:
        _scrollBy(_scrollStep);
      case TraversalDirection.left:
      case TraversalDirection.right:
        widget.onSideways?.call(direction);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...widget.leading(_scrollToTop),
        if (widget.sections.isNotEmpty)
          DpadFocusable(
            key: _readingKey,
            enabled:
                widget.onSideways == null ||
                widget.autofocus ||
                _canScroll ||
                _isReading,
            autofocus: widget.autofocus,
            // Only here for D-pad scrolling; the scrollbar shows focus, as a
            // border around the whole page would look selected on touch.
            effects: const [],
            // It can be taller than the page; revealing it would jump past
            // the top.
            autoScroll: false,
            // Nothing to activate; a tap should just scroll (touch).
            tapToSelect: false,
            onDirection: _onReadingDirection,
            onFocusChange: (focused) => setState(() => _isReading = focused),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.sections,
            ),
          ),
      ],
    );
    final maxContentWidth = widget.maxContentWidth;
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        final canScroll = notification.metrics.maxScrollExtent > 0;
        if (notification.depth == 0 && canScroll != _canScroll) {
          setState(() => _canScroll = canScroll);
        }
        return false;
      },
      child: Focus(
        focusNode: _contentNode,
        child: Scrollbar(
          controller: _scrollController,
          // While reading, nothing else shows a remote user where focus is.
          thumbVisibility: _isReading,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: widget.padding,
            child: maxContentWidth == null
                ? content
                : Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: content,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The game's two sides, in the order the league reads them.
class _SidePair {
  const _SidePair(this.order, this._fixture);

  factory _SidePair.of(SportsFixture fixture) => _SidePair(
    fixture.league.soccerStyle
        ? const [SportsSide.home, SportsSide.away]
        : const [SportsSide.away, SportsSide.home],
    fixture,
  );

  final List<SportsSide> order;
  final SportsFixture _fixture;

  SportsSide get first => order.first;
  SportsSide get second => order.last;

  SportsCompetitor? competitor(SportsSide side) =>
      side == SportsSide.home ? _fixture.home : _fixture.away;

  /// The team's abbreviation, else as much of its name as a table can take.
  String shortLabel(SportsSide side) {
    final team = competitor(side)?.team;
    if (team == null) return '';
    return team.abbreviation.isNotEmpty ? team.abbreviation : team.shortName;
  }
}

/// The game at a glance: league on top, the two teams either side of the score
/// or start time, each with its record and follow button.
class _Matchup extends StatelessWidget {
  const _Matchup({
    required this.fixture,
    required this.sides,
    required this.details,
  });

  final SportsFixture fixture;
  final _SidePair sides;
  final SportsFixtureDetails? details;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final record = {
      SportsSide.home: details?.homeRecord,
      SportsSide.away: details?.awayRecord,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LeagueLabel(fixture: fixture),
        SizedBox(height: 12 * scale),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _TeamColumn(
                competitor: sides.competitor(sides.first),
                record: record[sides.first],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: EdgeInsets.only(top: 12 * scale),
                child: _MatchupCenter(fixture: fixture, sides: sides),
              ),
            ),
            Expanded(
              flex: 3,
              child: _TeamColumn(
                competitor: sides.competitor(sides.second),
                record: record[sides.second],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LeagueLabel extends StatelessWidget {
  const _LeagueLabel({required this.fixture});

  final SportsFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final leagueLogo = fixture.leagueLogoUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leagueLogo != null) ...[
          SportsTeamLogo(url: leagueLogo, size: 22 * scale),
          SizedBox(width: 8 * scale),
        ],
        Flexible(
          child: Text(
            fixture.league.name,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// [_Matchup] for wide screens, as short as it can be to leave room below:
/// each team beside its crest, with the score by period under the score.
class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.fixture,
    required this.sides,
    required this.details,
    required this.autofocusFollow,
  });

  final SportsFixture fixture;
  final _SidePair sides;
  final SportsFixtureDetails? details;
  final bool autofocusFollow;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final details = this.details;
    String? recordOf(SportsSide side) =>
        side == SportsSide.home ? details?.homeRecord : details?.awayRecord;
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: _ScoreboardTeam(
            competitor: sides.competitor(sides.first),
            record: recordOf(sides.first),
            autofocusFollow: autofocusFollow,
          ),
        ),
        SizedBox(width: 16 * scale),
        Expanded(
          flex: 3,
          child: _MatchupCenter(
            fixture: fixture,
            sides: sides,
            inlineStatus: true,
            lineScore: details?.lineScore,
          ),
        ),
        SizedBox(width: 16 * scale),
        Expanded(
          flex: 4,
          child: _ScoreboardTeam(
            competitor: sides.competitor(sides.second),
            record: recordOf(sides.second),
            mirrored: true,
          ),
        ),
      ],
    );
  }
}

class _ScoreboardTeam extends ConsumerWidget {
  const _ScoreboardTeam({
    required this.competitor,
    required this.record,
    this.mirrored = false,
    this.autofocusFollow = false,
  });

  final SportsCompetitor? competitor;
  final String? record;

  /// The right-hand team: crest on the outside, text against the score.
  final bool mirrored;
  final bool autofocusFollow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competitor = this.competitor;
    if (competitor == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final record = this.record;
    final team = competitor.team;
    final settings = ref.watch(sportsSettingsProvider);
    final crest = SportsTeamLogo(url: team.logoUrl, size: 64 * scale);
    final text = Flexible(
      child: Column(
        crossAxisAlignment: mirrored
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            team.displayName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: mirrored ? TextAlign.end : TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 6 * scale),
          Wrap(
            alignment: mirrored ? WrapAlignment.end : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10 * scale,
            runSpacing: 4 * scale,
            children: [
              if (record != null)
                Text(
                  record,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              _FollowChip(
                following: settings.isFollowing(team.key),
                autofocus: autofocusFollow,
                onTap: () => unawaited(settings.toggleFollow(team)),
              ),
            ],
          ),
        ],
      ),
    );
    final gap = SizedBox(width: 14 * scale);
    // Up against the score, so the eye doesn't have to cross the screen
    return Row(
      mainAxisAlignment: mirrored
          ? MainAxisAlignment.start
          : MainAxisAlignment.end,
      children: mirrored ? [text, gap, crest] : [crest, gap, text],
    );
  }
}

/// The start time before a game; the score and status once it's under way.
class _MatchupCenter extends StatelessWidget {
  const _MatchupCenter({
    required this.fixture,
    required this.sides,
    this.inlineStatus = false,
    this.lineScore,
  });

  final SportsFixture fixture;
  final _SidePair sides;

  /// The status on one line rather than two.
  final bool inlineStatus;

  /// Shown under the score, compactly.
  final SportsLineScore? lineScore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final big = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget headline(String text) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, style: big, maxLines: 1),
    );
    if (fixture.state == SportsFixtureState.scheduled) {
      return headline(
        DateFormat.jm(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(fixture.start.toLocal()),
      );
    }
    final firstScore = sides.competitor(sides.first)?.score;
    final secondScore = sides.competitor(sides.second)?.score;
    final lineScore = this.lineScore;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (firstScore != null && secondScore != null) ...[
          headline('$firstScore - $secondScore'),
          SizedBox(height: 6 * scale),
        ],
        SportsFixtureStatus(
          fixture: fixture,
          showLeague: false,
          alignment: CrossAxisAlignment.center,
          inline: inlineStatus,
        ),
        if (lineScore != null) ...[
          SizedBox(height: 6 * scale),
          _LineScoreTable(lineScore: lineScore, sides: sides, compact: true),
        ],
      ],
    );
  }
}

class _TeamColumn extends ConsumerWidget {
  const _TeamColumn({required this.competitor, required this.record});

  final SportsCompetitor? competitor;
  final String? record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final competitor = this.competitor;
    if (competitor == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final record = this.record;
    final team = competitor.team;
    final settings = ref.watch(sportsSettingsProvider);
    return Column(
      children: [
        SportsTeamLogo(url: team.logoUrl, size: 64 * scale),
        SizedBox(height: 8 * scale),
        Text(
          team.displayName,
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        if (record != null) ...[
          SizedBox(height: 2 * scale),
          Text(
            record,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        SizedBox(height: 8 * scale),
        _FollowChip(
          following: settings.isFollowing(team.key),
          onTap: () => unawaited(settings.toggleFollow(team)),
        ),
      ],
    );
  }
}

class _FollowChip extends StatelessWidget {
  const _FollowChip({
    required this.following,
    required this.onTap,
    this.autofocus = false,
  });

  final bool following;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return DpadInkWell(
      onTap: onTap,
      autofocus: autofocus,
      // The Focus around the matchup scrolls to the top instead
      autoScroll: false,
      color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(50),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10 * scale,
          vertical: 6 * scale,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                following ? Icons.star : Icons.star_border,
                size: 16 * scale,
              ),
              SizedBox(width: 4 * scale),
              Text(
                following ? l10n.sportsFollowing : l10n.sportsFollow,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every channel carrying the game, each a press away from playing. Long
/// names drag sideways, as the row can't show them whole.
class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.matches,
    required this.onWatch,
    required this.onFirstRowFocused,
  });

  final List<SportsChannelMatch> matches;
  final ValueChanged<SportsChannelMatch> onWatch;
  final VoidCallback onFirstRowFocused;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, match) in matches.indexed)
          _ChannelRow(
            match: match,
            autofocus: index == 0,
            onFocused: index == 0 ? onFirstRowFocused : null,
            onTap: () => onWatch(match),
          ),
      ],
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.match,
    required this.autofocus,
    required this.onFocused,
    required this.onTap,
  });

  final SportsChannelMatch match;
  final bool autofocus;

  /// Takes over scrolling for this row when set, in place of the partial
  /// reveal the other rows use.
  final VoidCallback? onFocused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final channel = match.channel;
    final logo = channel.logoUrl;
    final logoWidth = 52 * scale;
    final logoHeight = 36 * scale;
    final fallback = Icon(
      Icons.live_tv,
      size: logoHeight * 0.7,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final detail = [
      match.programTitle,
      channel.groupTitle,
    ].whereType<String>().where((text) => text.isNotEmpty).join(' · ');
    final detailStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final onFocused = this.onFocused;
    return DpadInkWell(
      onTap: onTap,
      autofocus: autofocus,
      autoScroll: onFocused == null,
      onFocusChange: onFocused == null
          ? null
          : (hasFocus) {
              if (hasFocus) onFocused();
            },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.all(6 * scale),
        child: Row(
          children: [
            SizedBox(
              width: logoWidth,
              height: logoHeight,
              child: logo == null || logo.isEmpty
                  ? fallback
                  : CachedMediaThumbnail(
                      url: logo,
                      fallback: fallback,
                      width: logoWidth,
                      height: logoHeight,
                      fit: BoxFit.contain,
                    ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DraggableText(
                    channel.name,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (detail.isNotEmpty) ...[
                    SizedBox(height: 4 * scale),
                    // A remote can't drag, so wider screens keep the ellipsis
                    if (MediaQuery.sizeOf(context).width < 600)
                      DraggableText(detail, style: detailStyle)
                    else
                      Text(
                        detail,
                        style: detailStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 10 * scale),
            Icon(
              Icons.play_circle_fill,
              size: 30 * scale,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return Padding(
      padding: EdgeInsets.only(top: 20 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8 * scale),
          DecoratedBox(
            decoration: BoxDecoration(
              // The page's team colours show through
              color: theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: 0.7,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(padding: EdgeInsets.all(14 * scale), child: child),
          ),
        ],
      ),
    );
  }
}

/// Teams down the side and periods across, dragged sideways when a long game
/// (extra innings) doesn't fit.
class _LineScoreTable extends StatelessWidget {
  const _LineScoreTable({
    required this.lineScore,
    required this.sides,
    this.compact = false,
  });

  final SportsLineScore lineScore;
  final _SidePair sides;

  /// Tighter rows, for the scoreboard.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final header = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final cell = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final total = cell?.copyWith(fontWeight: FontWeight.w700);
    Widget box(String text, TextStyle? style, {bool leading = false}) =>
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 8 * scale,
            vertical: (compact ? 1 : 4) * scale,
          ),
          child: Text(
            text,
            style: style,
            textAlign: leading ? TextAlign.start : TextAlign.center,
          ),
        );
    TableRow row(SportsSide side) {
      final scores = side == SportsSide.home ? lineScore.home : lineScore.away;
      return TableRow(
        children: [
          box(sides.shortLabel(side), total, leading: true),
          for (final score in scores) box(score, cell),
          box(sides.competitor(side)?.score ?? '-', total),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        children: [
          TableRow(
            children: [
              box('', header),
              for (final period in lineScore.periods) box(period, header),
              box(l10n.sportsDetailsTotalShort, header),
            ],
          ),
          row(sides.first),
          row(sides.second),
        ],
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events, required this.sides});

  final List<SportsFixtureEvent> events;
  final _SidePair sides;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, event) in events.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 12 * scale),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64 * scale,
                  child: Text(event.time ?? '', style: muted),
                ),
                SizedBox(
                  width: 24 * scale,
                  child: _EventIcon(kind: event.kind),
                ),
                SizedBox(width: 6 * scale),
                if (event.side case final side?) ...[
                  SportsTeamLogo(
                    url: sides.competitor(side)?.team.logoUrl,
                    size: 20 * scale,
                  ),
                  SizedBox(width: 8 * scale),
                ],
                Expanded(
                  child: Text(event.text, style: theme.textTheme.bodyMedium),
                ),
                if (_scoreOf(event) case final score?) ...[
                  SizedBox(width: 10 * scale),
                  Text(
                    score,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// The score after [event], in the league's reading order.
  String? _scoreOf(SportsFixtureEvent event) {
    final home = event.homeScore;
    final away = event.awayScore;
    if (home == null || away == null) return null;
    return sides.first == SportsSide.home ? '$home-$away' : '$away-$home';
  }
}

class _EventIcon extends StatelessWidget {
  const _EventIcon({required this.kind});

  final SportsEventKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    Widget card(Color color) => Align(
      alignment: Alignment.topLeft,
      child: Container(
        width: 11 * scale,
        height: 15 * scale,
        margin: EdgeInsets.only(top: 2 * scale),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    return switch (kind) {
      SportsEventKind.score => Icon(
        Icons.sports_score,
        size: 18 * scale,
        color: theme.colorScheme.primary,
      ),
      SportsEventKind.yellowCard => card(const Color(0xFFFACC15)),
      SportsEventKind.redCard => card(theme.colorScheme.error),
      SportsEventKind.substitution => Icon(
        Icons.swap_horiz,
        size: 18 * scale,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      SportsEventKind.penalty => Icon(
        Icons.gavel,
        size: 18 * scale,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    };
  }
}

/// Each statistic under its label, between both teams' values, with a bar of
/// their shares in the teams' colours when the values are plain numbers.
class _StatList extends StatelessWidget {
  const _StatList({required this.stats, required this.sides});

  final List<SportsTeamStat> stats;
  final _SidePair sides;

  static double? _number(String value) =>
      double.tryParse(value.replaceAll('%', '').trim());

  /// The teams' colours, unless they'd read as one bar.
  (Color, Color) _barColors(ColorScheme scheme) {
    final first = sides.competitor(sides.first)?.team;
    final second = sides.competitor(sides.second)?.team;
    final firstColor = first == null ? null : sportsTeamColor(first);
    final secondColor = second == null ? null : sportsTeamColor(second);
    if (firstColor == null ||
        secondColor == null ||
        firstColor == secondColor) {
      return (scheme.primary, scheme.secondary);
    }
    return (firstColor, secondColor);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final colors = _barColors(theme.colorScheme);
    final value = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, stat) in stats.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 12 * scale),
            child: () {
              final first = sides.first == SportsSide.home
                  ? stat.home
                  : stat.away;
              final second = sides.first == SportsSide.home
                  ? stat.away
                  : stat.home;
              final firstNumber = _number(first);
              final secondNumber = _number(second);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(stat.label, style: label, textAlign: TextAlign.center),
                  SizedBox(height: 4 * scale),
                  Row(
                    children: [
                      Text(first, style: value),
                      SizedBox(width: 10 * scale),
                      Expanded(
                        child: _ShareBar(
                          first: firstNumber,
                          second: secondNumber,
                          colors: colors,
                        ),
                      ),
                      SizedBox(width: 10 * scale),
                      Text(second, style: value),
                    ],
                  ),
                ],
              );
            }(),
          ),
      ],
    );
  }
}

/// A plain track when the values can't be compared ("W1", "7-15").
class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.first,
    required this.second,
    required this.colors,
  });

  final double? first;
  final double? second;
  final (Color, Color) colors;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.1);
    Widget part(double share, Color color) => Expanded(
      flex: (share * 1000).round(),
      child: ColoredBox(color: color, child: const SizedBox(height: 6)),
    );
    final first = this.first;
    final second = this.second;
    final comparable =
        first != null &&
        second != null &&
        first >= 0 &&
        second >= 0 &&
        first + second > 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Row(
        children: [
          if (!comparable)
            part(1, track)
          else ...[
            if (first > 0) part(first / (first + second), colors.$1),
            if (first > 0 && second > 0) const SizedBox(width: 2),
            if (second > 0) part(second / (first + second), colors.$2),
          ],
        ],
      ),
    );
  }
}

class _LeaderList extends StatelessWidget {
  const _LeaderList({required this.categories, required this.sides});

  final List<SportsLeaderCategory> categories;
  final _SidePair sides;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    SportsLeader? leaderOf(SportsLeaderCategory category, SportsSide side) =>
        side == SportsSide.home ? category.home : category.away;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, category) in categories.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  category.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 6 * scale),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LeaderTile(
                        leader: leaderOf(category, sides.first),
                        team: sides.competitor(sides.first)?.team,
                      ),
                    ),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: _LeaderTile(
                        leader: leaderOf(category, sides.second),
                        team: sides.competitor(sides.second)?.team,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LeaderTile extends StatelessWidget {
  const _LeaderTile({required this.leader, required this.team});

  final SportsLeader? leader;
  final SportsTeam? team;

  @override
  Widget build(BuildContext context) {
    final leader = this.leader;
    if (leader == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final size = 48 * scale;
    final team = this.team;
    final teamColor = team == null ? null : sportsTeamColor(team);
    final fallback = Center(
      child: Icon(
        Icons.person,
        size: size * 0.6,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final photo = leader.photoUrl;
    final value = leader.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Headshots are cut-outs, so the team's colour fills in behind them
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (teamColor ?? theme.colorScheme.onSurface).withValues(
              alpha: 0.2,
            ),
            border: Border.all(
              color: teamColor ?? theme.colorScheme.outlineVariant,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: photo == null
              ? fallback
              : CachedMediaThumbnail(
                  url: photo,
                  fallback: fallback,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
        ),
        SizedBox(width: 10 * scale),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                leader.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (value != null)
                Text(
                  value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100 * scale,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          SizedBox(width: 10 * scale),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
