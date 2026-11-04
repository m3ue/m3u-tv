import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/sports/sports_fixture_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/desktop_fullscreen_service.dart';
import 'package:m3u_tv/services/sports_matcher.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/app_top_bar.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';
import 'package:material_ui/material_ui.dart';

bool get _isMacDesktopWindow => HostPlatform.isMacOS;
const double _kMacTrafficLightInset = 72;

class _SportsTeamsPopIntent extends Intent {
  const _SportsTeamsPopIntent();
}

/// Opens the team browser as an immersive page: pushed on the root Navigator,
/// it paints over AppShell's sidebar instead of AppShell resizing around it,
/// the same treatment as VOD/Series detail and Settings sub-pages.
///
/// A root route is outside AppShell's own back handling, so Escape/GoBack call
/// [onBack] (`AppShellState.handleBackFromTopLevelRoute`), which dedupes
/// Android TV's double delivery of one hardware Back; they fall back to a plain
/// pop when it's absent. tvOS's overscan padding, which AppShell otherwise
/// strips, is removed here too.
Future<void> openSportsTeams(
  BuildContext context, {
  required bool useSidebarLayout,
  String? initialLeagueId,
  bool Function()? onBack,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    appPageRoute<void>(
      builder: (context) {
        final screen = Shortcuts(
          shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.escape):
                const _SportsTeamsPopIntent(),
            LogicalKeySet(LogicalKeyboardKey.goBack):
                const _SportsTeamsPopIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _SportsTeamsPopIntent: CallbackAction<_SportsTeamsPopIntent>(
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
            child: SportsTeamsScreen(
              useSidebarLayout: useSidebarLayout,
              initialLeagueId: initialLeagueId,
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

/// Every team of each competition, to pick "My Teams" from: a league strip
/// beside a grid of crests, each a press away from following.
///
/// Teams come from M3U Editor (it reads its providers' team lists); follows go
/// through [sportsSettingsProvider], which also syncs them per viewer.
class SportsTeamsScreen extends ConsumerStatefulWidget {
  const SportsTeamsScreen({
    super.key,
    required this.useSidebarLayout,
    this.initialLeagueId,
  });

  /// TV/desktop: the league strip sits beside the grid; mobile: above it.
  final bool useSidebarLayout;

  /// The league shown first; the editor's first league otherwise.
  final String? initialLeagueId;

  @override
  ConsumerState<SportsTeamsScreen> createState() => _SportsTeamsScreenState();
}

class _SportsTeamsScreenState extends ConsumerState<SportsTeamsScreen> {
  final FocusScopeNode _gridFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();

  /// Each league's teams, loaded the first time it is shown.
  final Map<String, Future<List<SportsTeam>>> _teams = {};
  late String _leagueId = _initialLeagueId();
  String _query = '';

  /// The editor's leagues, the ones the Sports screen shows first: with
  /// every ESPN league offered, the viewer's own would be far down the list.
  late final List<SportsLeague> _leagues = () {
    final available = ref.read(sportsCapabilityProvider)?.leagues ?? const [];
    final settings = ref.read(sportsSettingsProvider);
    return [
      ...available.where(settings.isLeagueEnabled),
      ...available.where((league) => !settings.isLeagueEnabled(league)),
    ];
  }();

  @override
  void initState() {
    super.initState();
    // Out on the root Navigator, Back only reaches this page's handling from
    // focus inside it, so start on the league strip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _navKey.currentState?.requestFocus();
    });
  }

  String _initialLeagueId() {
    final leagues = _leagues;
    final wanted = widget.initialLeagueId;
    if (wanted != null && leagues.any((league) => league.id == wanted)) {
      return wanted;
    }
    return leagues.isEmpty ? '' : leagues.first.id;
  }

  @override
  void dispose() {
    _gridFocusNode.dispose();
    super.dispose();
  }

  Future<List<SportsTeam>> _teamsFor(String leagueId) =>
      _teams[leagueId] ??= _loadTeams(leagueId);

  Future<List<SportsTeam>> _loadTeams(String leagueId) async {
    final capability = ref.read(sportsCapabilityProvider);
    final league = capability?.leagueById(leagueId);
    if (capability == null || league == null) return const [];
    try {
      return await ref.read(sportsServiceProvider).teams(capability, league);
    } on Object catch (error) {
      debugPrint('[Sports] teams load for $leagueId failed: $error');
      // Forget the failure, so choosing the league again retries.
      unawaited(_teams.remove(leagueId));
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(sportsSettingsProvider);
    final scale = FontSizeScope.scaleOf(context);
    final useSidebarLayout = widget.useSidebarLayout;

    final nav = MediaCategoryNav(
      key: _navKey,
      useSidebarLayout: useSidebarLayout,
      query: _query,
      onQueryChanged: (value) => setState(() => _query = value),
      searchHint: l10n.sportsSearchHint,
      tabs: [
        for (final league in _leagues)
          CategoryTabData(id: league.id, name: league.name),
      ],
      selectedId: _leagueId,
      onSelected: (id) => setState(() => _leagueId = id),
      filterButtonLabel: l10n.mediaCategoryFilterButton,
      filterScreenTitle: l10n.mediaCategoryFilterScreenTitle,
      gridFocusScopeNode: _gridFocusNode,
      memoryKeyPrefix: 'sports-teams',
    );

    final content = Expanded(
      child: FutureBuilder<List<SportsTeam>>(
        key: ValueKey(_leagueId),
        future: _teamsFor(_leagueId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppLoadingIndicator());
          }
          final query = SportsMatcher.normalize(_query).trim();
          final teams = [
            for (final team in snapshot.data ?? const <SportsTeam>[])
              if (query.isEmpty ||
                  SportsMatcher.normalize(team.displayName).contains(query))
                team,
          ];
          if (snapshot.hasError || teams.isEmpty) {
            return Center(
              child: Text(
                snapshot.hasError
                    ? l10n.sportsTeamsLoadFailed
                    : l10n.sportsNoTeams,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          return FocusScope(
            node: _gridFocusNode,
            child: DpadRegion(
              memoryKey: 'sports-teams/grid',
              horizontalEdge: DpadEdgeBehavior.stop,
              onEdge: (direction) {
                if (direction == TraversalDirection.left) {
                  _navKey.currentState?.requestFocus();
                }
              },
              child: ScrollbarGridView(
                padding: const EdgeInsets.all(
                  MediaBrowsingMetrics.pagePadding,
                ),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200 * scale,
                  mainAxisExtent: 150 * scale,
                  mainAxisSpacing: MediaBrowsingMetrics.itemGap,
                  crossAxisSpacing: MediaBrowsingMetrics.itemGap,
                ),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  return _TeamTile(
                    team: team,
                    following: settings.isFollowing(team.key),
                    onTap: () => unawaited(settings.toggleFollow(team)),
                  );
                },
              ),
            ),
          );
        },
      ),
    );

    return Scaffold(
      appBar: AppTopBar(
        title: Text(l10n.sportsTeamsTitle),
        scale: scale,
        leadingInset:
            _isMacDesktopWindow &&
                !DesktopFullscreenScope.isFullscreenOf(context)
            ? _kMacTrafficLightInset
            : 0.0,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: useSidebarLayout
          ? Row(children: [nav, content])
          : Column(children: [nav, content]),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.following,
    required this.onTap,
  });

  final SportsTeam team;
  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return DpadInkWell(
      onTap: onTap,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(12 * scale),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SportsTeamLogo(url: team.logoUrl, size: 56 * scale),
                SizedBox(height: 10 * scale),
                Text(
                  team.displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
          Positioned(
            top: 8 * scale,
            right: 8 * scale,
            child: Icon(
              following ? Icons.star : Icons.star_border,
              size: 22 * scale,
              color: following
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
