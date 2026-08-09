import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Guards the positional coupling between [RouteNames.mainRoutes] and the
/// router's [StatefulShellRoute] branches.
///
/// `AppShell._navigateTo` turns a sidebar position into a branch index with
/// `RouteNames.mainRoutes.indexOf(...)`, so branch N *must* serve
/// `mainRoutes[N]`. Adding or removing a destination in only one of the two
/// places shifts every later branch: the sidebar then silently navigates to the
/// wrong screen. The analyzer cannot see it and no other test covers it — a
/// Shows destination was moved into the DVR tabs and both lists had to be
/// edited together to avoid exactly that.
void main() {
  testWidgets('shell branch order matches RouteNames.mainRoutes positionally', (
    tester,
  ) async {
    final memory = <String, Object?>{};
    final appState = AppStateController(
      xtreamService: XtreamService(),
      secureStorage: InMemorySecureStorage(),
      cacheService: CacheService(memory: <String, Object?>{}),
      favoritesService: FavoritesService(memory: memory),
      resumeService: ResumeService(memory: memory),
      viewerService: ViewerService(memory: memory),
    );
    addTearDown(appState.dispose);

    final router = createGoRouter(
      appState: appState,
      nativeTelevisionHint: false,
    );
    addTearDown(router.dispose);

    final shell = router.configuration.routes
        .whereType<StatefulShellRoute>()
        .single;

    final branchPaths = shell.branches
        .map((branch) => (branch.routes.first as GoRoute).path)
        .toList(growable: false);

    expect(
      branchPaths,
      RouteNames.mainRoutes,
      reason:
          'Shell branch order drifted from RouteNames.mainRoutes. AppShell maps '
          'a sidebar position to a branch index via mainRoutes.indexOf, so '
          'branch N must serve mainRoutes[N]. Add or remove a destination in '
          'BOTH places, in the same position.',
    );
  });
}
