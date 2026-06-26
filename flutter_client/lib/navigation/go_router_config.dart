import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show AppShell, DeviceType;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/features/dvr/dvr_recordings_screen.dart';
import 'package:m3u_tv/features/requests/request_screen.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/content_actions.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';

const BoxDecoration _kGradientBg = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF1a1528),
      Color(0xFF09090b),
      Color(0xFF09090b),
    ],
    stops: [0.0, 0.45, 1.0],
  ),
);

Widget _withGradient(Widget screen) =>
    DecoratedBox(decoration: _kGradientBg, child: screen);

CustomTransitionPage<void> _slidePage(Widget screen) =>
    CustomTransitionPage<void>(
      child: ColoredBox(color: const Color(0xFF09090b), child: screen),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );

GoRouter createGoRouter({
  required AppStateController appState,
  required bool nativeTelevisionHint,
  PlaybackOrchestrator Function()? playbackOrchestratorBuilder,
  Widget Function(PlayerArgs args)? playerRouteBuilder,
  DeviceType? deviceTypeOverride,
}) {
  return GoRouter(
    initialLocation: RouteNames.home,
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
            navigationShell: navigationShell,
            deviceType: deviceType,
            appState: appState,
            playbackOrchestratorBuilder: playbackOrchestratorBuilder,
            playerRouteBuilder: playerRouteBuilder,
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
          // Branch 3: VOD with nested details
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.vod,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.vod)),
                ),
                routes: [
                  GoRoute(
                    path: 'details/:vodId',
                    pageBuilder: (context, state) {
                      final vodId = int.parse(state.pathParameters['vodId']!);
                      final actions = ContentActions.of(context);
                      final item =
                          state.extra as VodItem? ??
                          actions.appState.vodItems.firstWhereOrNull(
                            (v) => v.id == vodId,
                          );
                      if (item == null) {
                        return NoTransitionPage(
                          child: Scaffold(
                            body: Center(
                              child: Text('VOD #$vodId not found'),
                            ),
                          ),
                        );
                      }
                      return _slidePage(
                        ListenableBuilder(
                          listenable: actions.appState,
                          builder: (ctx, _) => VodDetailsScreen(
                            item: item,
                            xtreamService: actions.xtreamService,
                            onPlay: actions.onOpenPlayer,
                            progressList: actions.progressList,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Series with nested details
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.series,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.series)),
                ),
                routes: [
                  GoRoute(
                    path: 'details/:seriesId',
                    pageBuilder: (context, state) {
                      final seriesId = int.parse(
                        state.pathParameters['seriesId']!,
                      );
                      final actions = ContentActions.of(context);
                      final series =
                          state.extra as Series? ??
                          actions.appState.seriesList.firstWhereOrNull(
                            (s) => s.id == seriesId,
                          );
                      if (series == null) {
                        return NoTransitionPage(
                          child: Scaffold(
                            body: Center(
                              child: Text('Series #$seriesId not found'),
                            ),
                          ),
                        );
                      }
                      return _slidePage(
                        ListenableBuilder(
                          listenable: actions.appState,
                          builder: (ctx, _) => SeriesDetailsScreen(
                            seriesId: series.id,
                            seriesName: series.name,
                            xtreamService: actions.xtreamService,
                            onPlay: actions.onOpenPlayer,
                            progressList: actions.progressList,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 5: DVR
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.dvr,
                pageBuilder: (context, state) {
                  final actions = ContentActions.of(context);
                  return NoTransitionPage(
                    child: _withGradient(
                      ListenableBuilder(
                        listenable: actions.appState,
                        builder: (context, _) => DvrRecordingsScreen(
                          recordings: actions.appState.dvrRecordings,
                          isLoading: actions.appState.isLoadingContent,
                          isConfigured: actions.appState.isConfigured,
                          onPlay: actions.onOpenPlayer,
                          onSidebarActivate: actions.onSidebarActivate,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // Branch 6: Requests
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.requests,
                pageBuilder: (context, state) {
                  final actions = ContentActions.of(context);
                  return NoTransitionPage(
                    child: _withGradient(
                      ListenableBuilder(
                        listenable: actions.appState,
                        builder: (context, _) => RequestScreen(
                          isConfigured: actions.appState.isConfigured,
                          onSidebarActivate: actions.onSidebarActivate,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          // Branch 7: Notifications
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
          // Branch 8: Settings
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
    ],
  );
}

Widget _tabScreen(BuildContext context, String routeName) =>
    ContentActions.of(context).buildTabScreen(routeName);

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
