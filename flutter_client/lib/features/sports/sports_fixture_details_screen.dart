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

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _readingKey = GlobalKey();
  bool _isReading = false;
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
    _scrollController.dispose();
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

  /// Whether the top of the sections below the buttons is on screen, so Up
  /// has nothing left to read and can move to those buttons.
  bool get _readingTopVisible {
    final box = _readingKey.currentContext?.findRenderObject();
    if (box == null || !_scrollController.hasClients) return true;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    return _scrollController.position.pixels <= top + 0.5;
  }

  // The sections can't hold focus themselves, so one focus target covers them
  // and Up and Down read through them.
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
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final canWatch = _canWatch;
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
              title: Text(l10n.sportsDetailsTitle),
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
              child: Scrollbar(
                controller: _scrollController,
                // While reading, nothing else shows a remote user where focus is.
                thumbVisibility: _isReading,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    MediaBrowsingMetrics.pagePadding,
                    8,
                    MediaBrowsingMetrics.pagePadding,
                    24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 860 * scale),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Matchup(
                            fixture: _fixture,
                            sides: _SidePair.of(_fixture),
                            details: _details,
                          ),
                          if (canWatch)
                            _Section(
                              title: l10n.sportsDetailsOnYourChannels,
                              child: _ChannelList(
                                matches: widget.matches,
                                onWatch: _watch,
                              ),
                            ),
                          DpadFocusable(
                            key: _readingKey,
                            autofocus: !canWatch,
                            // Only here for D-pad scrolling; the scrollbar shows
                            // focus, as a border around the whole page would look
                            // selected on touch.
                            effects: const [],
                            // It can be taller than the page; revealing it would
                            // jump past the top.
                            autoScroll: false,
                            // Nothing to activate; a tap should just scroll (touch).
                            tapToSelect: false,
                            onDirection: _onReadingDirection,
                            onFocusChange: (focused) =>
                                setState(() => _isReading = focused),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _buildSections(l10n, _details),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSections(
    AppLocalizations l10n,
    SportsFixtureDetails? details,
  ) {
    final sides = _SidePair.of(_fixture);
    final isUpcoming = _fixture.state == SportsFixtureState.scheduled;
    final lineScore = details?.lineScore;
    final infoRows = _infoRows(l10n, details);
    final sections = <Widget>[
      if (lineScore != null)
        _Section(
          title: l10n.sportsDetailsLineScore,
          child: _LineScoreTable(lineScore: lineScore, sides: sides),
        ),
      if (details != null && details.events.isNotEmpty)
        _Section(
          title: l10n.sportsDetailsEvents,
          child: _EventList(events: details.events, sides: sides),
        ),
      if (details != null && details.stats.isNotEmpty)
        _Section(
          // Before a game, the provider's numbers are its season so far
          title: isUpcoming
              ? l10n.sportsDetailsSeasonStats
              : l10n.sportsDetailsStats,
          child: _StatList(stats: details.stats, sides: sides),
        ),
      if (details != null && details.leaders.isNotEmpty)
        _Section(
          title: isUpcoming
              ? l10n.sportsDetailsSeasonLeaders
              : l10n.sportsDetailsLeaders,
          child: _LeaderList(categories: details.leaders, sides: sides),
        ),
      if (infoRows.isNotEmpty)
        _Section(
          title: l10n.sportsDetailsInfo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: infoRows,
          ),
        ),
    ];
    final message = _loadFailed
        ? l10n.sportsDetailsLoadFailed
        : !_isLoading && details == null
        ? l10n.sportsDetailsUnavailable
        : null;
    return [
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
      ...sections,
    ];
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
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final leagueLogo = fixture.leagueLogoUrl;
    final record = {
      SportsSide.home: details?.homeRecord,
      SportsSide.away: details?.awayRecord,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leagueLogo != null) ...[
              SportsTeamLogo(url: leagueLogo, size: 22 * scale),
              SizedBox(width: 8 * scale),
            ],
            Flexible(
              child: Text(
                fixture.league.name,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

/// The start time before a game; the score and status once it's under way.
class _MatchupCenter extends StatelessWidget {
  const _MatchupCenter({required this.fixture, required this.sides});

  final SportsFixture fixture;
  final _SidePair sides;

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
    return Column(
      children: [
        if (firstScore != null && secondScore != null) ...[
          headline('$firstScore - $secondScore'),
          SizedBox(height: 6 * scale),
        ],
        SportsFixtureStatus(
          fixture: fixture,
          showLeague: false,
          alignment: CrossAxisAlignment.center,
        ),
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
  const _FollowChip({required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return DpadInkWell(
      onTap: onTap,
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
  const _ChannelList({required this.matches, required this.onWatch});

  final List<SportsChannelMatch> matches;
  final ValueChanged<SportsChannelMatch> onWatch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, match) in matches.indexed)
          _ChannelRow(
            match: match,
            autofocus: index == 0,
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
    required this.onTap,
  });

  final SportsChannelMatch match;
  final bool autofocus;
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
    return DpadInkWell(
      onTap: onTap,
      autofocus: autofocus,
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
  const _LineScoreTable({required this.lineScore, required this.sides});

  final SportsLineScore lineScore;
  final _SidePair sides;

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
            vertical: 4 * scale,
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
