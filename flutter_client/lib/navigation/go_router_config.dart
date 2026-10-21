import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart'
    show AppShell, AppShellState, DeviceType;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_detail_screen.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_search_screen.dart';
import 'package:m3u_tv/features/continue_watching/continue_watching_screen.dart';
import 'package:m3u_tv/features/person/person_detail_screen.dart';
import 'package:m3u_tv/features/requests/request_detail_screen.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/content_actions.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_background.dart';
import 'package:m3u_tv/shared/host_platform.dart';

Widget _withGradient(Widget screen) => DecoratedBox(
  decoration: kAppGradientBg,
  child: SafeArea(bottom: false, child: screen),
);

/// tvOS reports its overscan-safe area as real [MediaQuery] padding on every
/// edge, same as a phone's notch/status-bar insets. Screens still nested
/// inside `AppShell`'s own subtree never see that padding - its TV/sidebar
/// layout already strips it via `MediaQuery.removePadding` (`_buildTvLayout`
/// in app_shell.dart) - but the top-level immersive routes below (VOD,
/// Series, AIOStreams/Shows detail) live as siblings of AppShell in the root
/// Navigator, outside that treatment, so `SafeArea` there was honoring the
/// real overscan inset and shrinking the whole screen inward on tvOS only
/// (other platforms report ~0 padding in a sidebar layout, so `SafeArea` was
/// effectively a no-op there). Mirrors the same "strip it on tvOS" rule
/// AppShell applies to its own content.
bool get _isTvOS => HostPlatform.isTvOS;

Widget _topLevelSafeArea(Widget screen) => Builder(
  builder: (context) => _isTvOS
      ? MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: screen,
        )
      : SafeArea(bottom: false, child: screen),
);

CustomTransitionPage<void> _slidePage(Widget screen) =>
    CustomTransitionPage<void>(
      child: ColoredBox(
        color: const Color(0xFF09090b),
        child: _topLevelSafeArea(screen),
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );

/// Hardware Back/Escape for the top-level VOD/Series detail routes.
///
/// AppShell wires its own Escape/GoBack -> pop handling via `Shortcuts` +
/// `Actions` around its own subtree (see `_BackIntent`/`_handleShortcutBack`
/// in app_shell.dart) - Flutter resolves a `Shortcuts` key press against the
/// *nearest* enclosing `Actions` for that intent, found by walking up from
/// the focused widget. A top-level route (a sibling of AppShell in the root
/// Navigator, not a descendant) is outside that ancestor chain entirely, so
/// pressing Escape here would silently do nothing without this - a duplicate
/// `Shortcuts`/`Actions` pair, scoped to just these routes.
///
/// This delegates to `AppShellState.handleBackFromTopLevelRoute` rather than
/// popping directly: a single Android TV hardware Back is delivered on two
/// paths (this key event, and a platform `popRoute` message AppShell's
/// `WidgetsBindingObserver` always receives regardless of focus), and
/// AppShell dedupes the pair by tracking which path handled the last one. An
/// independent pop here would never update that shared state, so the
/// platform message's echo goes undetected and falls through to activating
/// the sidebar as a spurious second back press - exactly the bug this caused
/// before routing through AppShell's own handler instead.
class _TopLevelPopIntent extends Intent {
  const _TopLevelPopIntent();
}

Widget _withTopLevelBackHandling(
  GlobalKey<AppShellState> appShellKey,
  Widget child,
) {
  return Shortcuts(
    shortcuts: <LogicalKeySet, Intent>{
      LogicalKeySet(LogicalKeyboardKey.escape): const _TopLevelPopIntent(),
      LogicalKeySet(LogicalKeyboardKey.goBack): const _TopLevelPopIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _TopLevelPopIntent: CallbackAction<_TopLevelPopIntent>(
          onInvoke: (_) {
            appShellKey.currentState?.handleBackFromTopLevelRoute();
            return null;
          },
        ),
      },
      child: child,
    ),
  );
}

/// Wraps `actions.onOpenPlayer` for the top-level VOD/Series detail routes:
/// the player itself is not a route at all - it is state internal to
/// AppShell (`_playerArgs`/`_playerOrchestrator`), rendered as a `Positioned
/// .fill` inside AppShell's own build - so activating it while this detail
/// route is still on top of the root Navigator would set the state correctly
/// but render it *behind* this still-pushed page, invisible. Popping this
/// route first (or, in practice, in the same frame - `onOpenPlayer` reaches
/// its `setState` synchronously whenever there is no resume-progress dialog
/// in the way) puts AppShell back on top so its player overlay is actually
/// seen.
void Function(PlayerArgs) _playOnTopLevelRoute(
  BuildContext context,
  AppShellActions actions,
) {
  return (args) {
    actions.onOpenPlayer(args);
    if (context.mounted && context.canPop()) context.pop();
  };
}

/// Opens a Related-row tap's own detail screen, reusing the same
/// `onVodSelect`/`onSeriesSelect` callbacks every other VOD/series entry
/// point (grids, Continue Watching) already navigates through - a related
/// item is guaranteed to already exist in the user's library, so it only
/// needs resolving to the matching [VodItem]/[Series] by id. The lookup hits
/// the SQLite catalog (fire-and-forget from the tap) rather than an
/// in-memory list, so this is the one entry point in the app with a brief
/// (sub-frame, same-process) gap between tap and navigation.
Future<void> _openRelated(AppShellActions actions, RelatedItem related) async {
  final targetId = int.tryParse(related.id);
  if (targetId == null) {
    debugPrint('_openRelated: unparseable id "${related.id}"');
    return;
  }
  if (related.isSeries) {
    final series = await actions.appState.catalogRepository
        .activeItemById<Series>(kind: kCatalogKindSeries, id: targetId);
    if (series != null) {
      actions.onSeriesSelect(series);
    } else {
      debugPrint('_openRelated: series #$targetId not found in library');
    }
  } else {
    final vod = await actions.appState.catalogRepository
        .activeItemById<VodItem>(kind: kCatalogKindVod, id: targetId);
    if (vod != null) {
      actions.onVodSelect(vod);
    } else {
      debugPrint('_openRelated: VOD #$targetId not found in library');
    }
  }
}

/// Opens a filmography credit already known to exist in the caller's
/// playlist library (`FilmographyCredit.inLibrary`/`localId`, resolved
/// server-side by `get_actor_filmography` - no tmdb-id lookup needed here,
/// unlike [_openRelated]). Pops the person-detail route first so the item's
/// own detail screen replaces it rather than stacking on top, matching how a
/// related-item tap behaves.
Future<void> _openFilmographyCredit(
  BuildContext context,
  AppShellActions actions,
  FilmographyCredit credit,
) async {
  final localId = credit.localId;
  if (!credit.inLibrary || localId == null) return;
  if (credit.isSeries) {
    final series = await actions.appState.catalogRepository
        .activeItemById<Series>(kind: kCatalogKindSeries, id: localId);
    if (series != null) {
      actions.onSeriesSelect(series);
    } else {
      debugPrint(
        '_openFilmographyCredit: series #$localId not found in library',
      );
    }
  } else {
    final vod = await actions.appState.catalogRepository
        .activeItemById<VodItem>(kind: kCatalogKindVod, id: localId);
    if (vod != null) {
      actions.onVodSelect(vod);
    } else {
      debugPrint('_openFilmographyCredit: VOD #$localId not found in library');
    }
  }
}

/// AIOStreams counterpart to [_openFilmographyCredit]. AIOStreams is
/// on-demand (not library-driven), so unlike the Xtream path there is no
/// `inLibrary`/`localId` gate - every credit navigates, using the `tmdb:{id}`
/// meta form AIOStreamsService already builds meta from directly (the same
/// form "related" cards use, see `AIOStreamsService::buildMetaFromTmdb` in
/// m3u-editor). Pushes (not go) so a normal one-level pop on Back matches
/// every other AIOStreams related-item tap.
void _openAIOStreamsFilmographyCredit(
  BuildContext context,
  int integrationId,
  FilmographyCredit credit,
) {
  final type = credit.isSeries ? 'series' : 'movie';
  final id = 'tmdb:${credit.tmdbId}';
  unawaited(
    context.push(
      RouteNames.aiostreamsDetailsFor(integrationId, type, id),
      extra: AIOStreamsItem(
        id: id,
        type: type,
        name: credit.title,
        poster: credit.posterUrl,
      ),
    ),
  );
}

/// Resolves a VOD detail route's `:vodId` against the SQLite catalog when the
/// caller didn't already have the [VodItem] in hand (`state.extra` null - a
/// deep link, push notification, or restored route). Every in-app tap already
/// carries the object via `extra` and never hits this path.
class _AsyncVodDetails extends StatelessWidget {
  const _AsyncVodDetails({
    required this.vodId,
    required this.actions,
    required this.appShellKey,
  });

  final int vodId;
  final AppShellActions actions;
  final GlobalKey<AppShellState> appShellKey;

  @override
  Widget build(BuildContext context) {
    return _withTopLevelBackHandling(
      appShellKey,
      FutureBuilder<VodItem?>(
        future: actions.appState.catalogRepository.activeItemById<VodItem>(
          kind: kCatalogKindVod,
          id: vodId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final item = snapshot.data;
          if (item == null) {
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: Center(child: Text('VOD #$vodId not found')),
              ),
            );
          }
          return ListenableBuilder(
            listenable: actions.appState,
            builder: (ctx, _) => VodDetailsScreen(
              item: item,
              xtreamService: actions.xtreamService,
              onPlay: _playOnTopLevelRoute(context, actions),
              progressList: actions.progressList,
              onOpenRelated: (related) => _openRelated(actions, related),
              onTapMember: (member) => context.push(
                RouteNames.personDetailsFor(
                  personId: member.id,
                  name: member.name,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Series counterpart to [_AsyncVodDetails].
class _AsyncSeriesDetails extends StatelessWidget {
  const _AsyncSeriesDetails({
    required this.seriesId,
    required this.actions,
    required this.appShellKey,
  });

  final int seriesId;
  final AppShellActions actions;
  final GlobalKey<AppShellState> appShellKey;

  @override
  Widget build(BuildContext context) {
    return _withTopLevelBackHandling(
      appShellKey,
      FutureBuilder<Series?>(
        future: actions.appState.catalogRepository.activeItemById<Series>(
          kind: kCatalogKindSeries,
          id: seriesId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final series = snapshot.data;
          if (series == null) {
            return Scaffold(
              body: SafeArea(
                bottom: false,
                child: Center(child: Text('Series #$seriesId not found')),
              ),
            );
          }
          return ListenableBuilder(
            listenable: actions.appState,
            builder: (ctx, _) => SeriesDetailsScreen(
              seriesId: series.id,
              seriesName: series.name,
              coverUrl: series.coverUrl,
              xtreamService: actions.xtreamService,
              viewerId: actions.appState.activeViewer?.ulid,
              onPlay: _playOnTopLevelRoute(context, actions),
              progressList: actions.progressList,
              onMarkEpisodeWatched: actions.onMarkEpisodeWatched,
              onOpenRelated: (related) => _openRelated(actions, related),
              onTapMember: (member) => context.push(
                RouteNames.personDetailsFor(
                  personId: member.id,
                  name: member.name,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder for the (in practice unreachable) case a show-details route
/// builds with no `EpgShow` in hand - every in-app entry point always
/// supplies one via `extra`. Split out to a top-level widget so the
/// localized message call sits at a low enough indent for `dart format` to
/// keep it on one line - `show_route_contract_test.dart` scans the raw
/// source for the literal `AppLocalizations.of(context).showNotFound(` text.
class _ShowNotFoundPage extends StatelessWidget {
  const _ShowNotFoundPage({required this.normalizedTitle});

  final String normalizedTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: Text(
            AppLocalizations.of(context).showNotFound(normalizedTitle),
          ),
        ),
      ),
    );
  }
}

GoRouter createGoRouter({
  required AppStateController appState,
  required bool nativeTelevisionHint,
  PlaybackOrchestrator Function()? playbackOrchestratorBuilder,
  Widget Function(PlayerArgs args)? playerRouteBuilder,
  SystemUiPolicy? systemUiPolicy,
  DeviceType? deviceTypeOverride,
  String initialLocation = RouteNames.home,
}) {
  // Lets the top-level VOD/Series detail routes below reach AppShell's
  // navigation callbacks (onOpenPlayer, onVodSelect, ...) without an
  // InheritedWidget ancestor relationship - see AppShellActions' doc comment
  // in content_actions.dart for why those routes are top-level (root
  // Navigator) rather than nested under the shell in the first place.
  final appShellKey = GlobalKey<AppShellState>();

  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final deviceType =
              deviceTypeOverride ??
              resolveDeviceType(
                context,
                nativeTelevisionHint: nativeTelevisionHint,
              );
          return AppShell(
            key: appShellKey,
            navigationShell: navigationShell,
            deviceType: deviceType,
            appState: appState,
            playbackOrchestratorBuilder: playbackOrchestratorBuilder,
            playerRouteBuilder: playerRouteBuilder,
            systemUiPolicy: systemUiPolicy,
          );
        },
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.home,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.home)),
                ),
                routes: [
                  GoRoute(
                    path: 'continue-watching',
                    pageBuilder: (context, state) {
                      final actions = ContentActions.of(context);
                      return _slidePage(
                        ListenableBuilder(
                          listenable: actions.appState,
                          builder: (ctx, _) => ContinueWatchingScreen(
                            progressList: actions.appState.progressList,
                            catalogRepository:
                                actions.appState.catalogRepository,
                            onProgressSelect: actions.onProgressSelect,
                            onSidebarActivate: actions.onSidebarActivate,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.search,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.search)),
                ),
              ),
            ],
          ),
          // Branch 2: Live TV
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.liveTv,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.liveTv)),
                ),
              ),
            ],
          ),
          // Branch 3: VOD (details/:vodId is a top-level route - see below)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.vod,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.vod)),
                ),
              ),
            ],
          ),
          // Branch 4: Series (details/:seriesId is a top-level route - see below)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.series,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.series)),
                ),
              ),
            ],
          ),
          // Branch 5: AIOStreams with nested item detail
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.aiostreams,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.aiostreams),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'search',
                    pageBuilder: (context, state) {
                      final actions = ContentActions.of(context);
                      return _slidePage(
                        AIOStreamsSearchScreen(
                          integrations: actions.appState.aiostreamsIntegrations,
                          apiService: actions.appState.aiostreamsApiService,
                          favoritesService:
                              actions.appState.aioFavoritesService,
                          onItemSelect: (item, integrationId) {
                            unawaited(
                              context.push(
                                RouteNames.aiostreamsDetailsFor(
                                  integrationId,
                                  item.type,
                                  item.id,
                                ),
                                extra: item,
                              ),
                            );
                          },
                          onSidebarActivate: actions.onSidebarActivate,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 6: DVR (show-detail is a top-level route - see below).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.dvr,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.dvr)),
                ),
              ),
            ],
          ),
          // Branch 7: Requests. Its result-detail screen is NOT nested here -
          // see the top-level `RouteNames.requestsDetailsPath` route below,
          // for the same reason VOD/Series/AIOStreams details are top-level.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.requests,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.requests),
                  ),
                ),
              ),
            ],
          ),
          // Branch 8: Notifications
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.notifications,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.notifications),
                  ),
                ),
              ),
            ],
          ),
          // Branch 9: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.settings,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.settings),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      // Top-level (siblings of the shell, not nested under it) so pushing
      // either one covers the entire screen - sidebar included - by
      // painting into the root Navigator above AppShell itself, rather than
      // the branch Navigator AppShell insets by the sidebar's width. AppShell
      // never has to change its own layout for these two pushes/pops, which
      // is what avoids relayouting (and visually re-rendering) the
      // still-mounted screen underneath. `appShellKey` reaches AppShell's
      // navigation callbacks in place of `ContentActions.of(context)`, which
      // can only find an ancestor - AppShell is a sibling from here.
      GoRoute(
        path: RouteNames.vodDetailsPath,
        pageBuilder: (context, state) {
          final vodId = int.parse(state.pathParameters['vodId']!);
          final actions = _topLevelActions(appShellKey, appState);
          final item = state.extra as VodItem?;
          if (item != null) {
            return _slidePage(
              _withTopLevelBackHandling(
                appShellKey,
                ListenableBuilder(
                  listenable: actions.appState,
                  builder: (ctx, _) => VodDetailsScreen(
                    item: item,
                    xtreamService: actions.xtreamService,
                    onPlay: _playOnTopLevelRoute(context, actions),
                    progressList: actions.progressList,
                    onOpenRelated: (related) => _openRelated(actions, related),
                    onTapMember: (member) => context.push(
                      RouteNames.personDetailsFor(
                        personId: member.id,
                        name: member.name,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          // No object in hand (deep link / push notification / restored
          // route) - resolve it from the catalog.
          return _slidePage(
            _AsyncVodDetails(
              vodId: vodId,
              actions: actions,
              appShellKey: appShellKey,
            ),
          );
        },
      ),
      // Top-level for the same reason as VOD/Series above - covers the
      // sidebar by painting into the root Navigator instead of resizing
      // AppShell for it. AIOStreamsDetailScreen fetches its own metadata
      // from `apiService` given integrationId/type/id, so (unlike VOD/Series)
      // there's no async catalog lookup needed when `extra` is absent - the
      // minimal fallback item built from path params is enough to kick off
      // that fetch, matching what the old nested route already did.
      GoRoute(
        path: RouteNames.aiostreamsDetailsPath,
        pageBuilder: (context, state) {
          final integrationId = int.parse(
            state.pathParameters['integrationId']!,
          );
          final type = state.pathParameters['type']!;
          final id = state.pathParameters['id']!;
          final actions = _topLevelActions(appShellKey, appState);
          final item =
              state.extra as AIOStreamsItem? ??
              AIOStreamsItem(id: id, type: type, name: id);
          return _slidePage(
            _withTopLevelBackHandling(
              appShellKey,
              AIOStreamsDetailScreen(
                item: item,
                integrationId: integrationId,
                apiService: actions.appState.aiostreamsApiService,
                appStateController: actions.appState,
                onPlay: _playOnTopLevelRoute(context, actions),
                // push (not go) - a related item lands on the same route
                // pattern this screen is already on, and go() to a
                // same-pattern location updates this State in place rather
                // than creating a fresh one, so the (late final) meta fetch
                // never re-runs. push() gives it a real, freshly-initialized
                // instance and a normal one-level pop on back, matching how
                // VOD/Series related items navigate.
                onOpenRelated: (related) => context.push(
                  RouteNames.aiostreamsDetailsFor(
                    integrationId,
                    related.type,
                    related.id,
                  ),
                  extra: AIOStreamsItem(
                    id: related.id,
                    type: related.type,
                    name: related.title,
                    poster: related.posterUrl,
                  ),
                ),
                onTapMember: (member) => context.push(
                  RouteNames.personDetailsFor(
                    personId: member.id,
                    name: member.name,
                    includeLibraryFilter: false,
                    aiostreamsIntegrationId: integrationId,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      // Top-level for the same reason as VOD/Series/AIOStreams above - covers
      // the sidebar by painting into the root Navigator instead of resizing
      // AppShell for it. Requests is only ever reached in-app from the
      // search tab's results grid, which always supplies the
      // ContentRequestSearchResult via `extra` - no deep-link/async-catalog
      // fallback path exists here, matching how this route already worked
      // before it moved out of the `requests` branch.
      GoRoute(
        path: RouteNames.requestsDetailsPath,
        pageBuilder: (context, state) {
          final result = state.extra! as ContentRequestSearchResult;
          final actions = _topLevelActions(appShellKey, appState);
          final requestOwner = actions.appState.mediaRequestOwner;
          return _slidePage(
            _withTopLevelBackHandling(
              appShellKey,
              ListenableBuilder(
                listenable: actions.appState,
                builder: (ctx, _) => RequestDetailScreen(
                  result: result,
                  isOwnerCurrent:
                      actions.appState.mediaRequestOwner == requestOwner,
                  onSubmit:
                      ({
                        required type,
                        required integrationId,
                        required externalId,
                        seasons,
                      }) => actions.appState.submitContentRequest(
                        type: type,
                        integrationId: integrationId,
                        externalId: externalId,
                        seasons: seasons,
                        requestOwner: requestOwner,
                      ),
                ),
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: RouteNames.seriesDetailsPath,
        pageBuilder: (context, state) {
          final seriesId = int.parse(state.pathParameters['seriesId']!);
          final actions = _topLevelActions(appShellKey, appState);
          final series = state.extra as Series?;
          if (series != null) {
            return _slidePage(
              _withTopLevelBackHandling(
                appShellKey,
                ListenableBuilder(
                  listenable: actions.appState,
                  builder: (ctx, _) => SeriesDetailsScreen(
                    seriesId: series.id,
                    seriesName: series.name,
                    coverUrl: series.coverUrl,
                    xtreamService: actions.xtreamService,
                    viewerId: actions.appState.activeViewer?.ulid,
                    onPlay: _playOnTopLevelRoute(context, actions),
                    progressList: actions.progressList,
                    onMarkEpisodeWatched: actions.onMarkEpisodeWatched,
                    onOpenRelated: (related) => _openRelated(actions, related),
                    onTapMember: (member) => context.push(
                      RouteNames.personDetailsFor(
                        personId: member.id,
                        name: member.name,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          // No object in hand (deep link / push notification / restored
          // route) - resolve it from the catalog.
          return _slidePage(
            _AsyncSeriesDetails(
              seriesId: seriesId,
              actions: actions,
              appShellKey: appShellKey,
            ),
          );
        },
      ),
      // Top-level for the same reason as VOD/Series/AIOStreams above. Shows
      // is reached only in-app (from the Shows tab's search results or a
      // related-episode tap, both of which always carry the `EpgShow` via
      // `extra`), so there's no deep-link/async-catalog-lookup fallback
      // path here the way VOD/Series have - just the pre-existing "not
      // found" placeholder for the (in practice unreachable) case `extra`
      // is missing.
      GoRoute(
        path: RouteNames.showDetailsPath,
        pageBuilder: (context, state) {
          final normalizedTitle = state.pathParameters['normalizedTitle'] ?? '';
          final extra = state.extra;
          final show = extra is EpgShow ? extra : null;
          if (show == null) {
            return NoTransitionPage(
              child: _ShowNotFoundPage(normalizedTitle: normalizedTitle),
            );
          }
          final actions = _topLevelActions(appShellKey, appState);
          return _slidePage(
            _withTopLevelBackHandling(
              appShellKey,
              ShowDetailScreen(
                show: show,
                onRecordSeries: actions.onRecordSeries,
                onDeleteSeriesRule: actions.onDeleteSeriesRule,
                onScheduleEpisode: actions.onScheduleEpisode,
                onScheduleEpisodes: actions.onScheduleEpisodes,
                onHandleTopLevelBack: () =>
                    appShellKey.currentState?.handleBackFromTopLevelRoute() ??
                    false,
              ),
            ),
          );
        },
      ),
      // Top-level for the same reason as VOD/Series/AIOStreams above - a
      // person can be reached from any of those three detail screens (they
      // all share the same cast widgets), so this needs its own route rather
      // than nesting under one of them. `personId`/`name` are query params
      // (not a path segment) - mirrors m3u-editor's own `ActorFilmography`
      // Filament page, which reads the same two params off the query string.
      GoRoute(
        path: RouteNames.personDetails,
        pageBuilder: (context, state) {
          final actions = _topLevelActions(appShellKey, appState);
          final personIdParam = state.uri.queryParameters['personId'];
          final name = state.uri.queryParameters['name'] ?? '';
          final includeLibraryFilter =
              state.uri.queryParameters['includeLibraryFilter'] != 'false';
          final aiostreamsIntegrationIdParam =
              state.uri.queryParameters['aiostreamsIntegrationId'];
          final aiostreamsIntegrationId = aiostreamsIntegrationIdParam == null
              ? null
              : int.tryParse(aiostreamsIntegrationIdParam);
          return _slidePage(
            _withTopLevelBackHandling(
              appShellKey,
              PersonDetailScreen(
                name: name,
                personId: personIdParam == null
                    ? null
                    : int.tryParse(personIdParam),
                xtreamService: actions.xtreamService,
                includeLibraryFilter: includeLibraryFilter,
                onOpenCredit: aiostreamsIntegrationId == null
                    ? (credit) =>
                          _openFilmographyCredit(context, actions, credit)
                    : (credit) => _openAIOStreamsFilmographyCredit(
                        context,
                        aiostreamsIntegrationId,
                        credit,
                      ),
              ),
            ),
          );
        },
      ),
    ],
  );
}

/// [AppShellState.actionsForTopLevelRoutes], with a fallback for the
/// vanishingly unlikely case a top-level detail route somehow builds before
/// AppShell has ever mounted (AppShell is the app's permanent root UI once
/// running, so in practice `key.currentState` is always set by the time a
/// route push could reach here). The fallback drops player/select behavior
/// rather than crashing - the screen still renders with real catalog data.
AppShellActions _topLevelActions(
  GlobalKey<AppShellState> key,
  AppStateController appState,
) {
  final state = key.currentState;
  if (state != null) return state.actionsForTopLevelRoutes;
  debugPrint(
    '_topLevelActions: AppShell not mounted yet - navigation actions '
    'from this screen will be no-ops',
  );
  return AppShellActions(
    appState: appState,
    onOpenPlayer: (_) {},
    onVodSelect: (_) {},
    onSeriesSelect: (_) {},
  );
}

Widget _tabScreen(BuildContext context, String routeName) =>
    ContentActions.of(context).buildTabScreen(routeName);
