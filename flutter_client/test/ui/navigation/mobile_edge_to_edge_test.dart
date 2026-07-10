import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/viewer_service.dart';

void main() {
  testWidgets(
    'phone route paints behind portrait top inset while content stays safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPhoneApp(tester, const EdgeInsets.only(top: 48));

      final routePaint = _routeGradient();
      final content = find.text('Please connect to your service in Settings');

      expect(routePaint, findsOneWidget);
      expect(tester.getTopLeft(routePaint), Offset.zero);
      expect(tester.getTopRight(routePaint).dx, 400);
      expect(tester.getTopLeft(content).dy, greaterThanOrEqualTo(48));
      _expectSafeAreaPadding(tester, routePaint, top: 48);
    },
  );

  testWidgets(
    'phone route paints behind landscape side insets while content stays safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _pumpPhoneApp(
        tester,
        const EdgeInsets.only(left: 36, right: 52),
      );

      final routePaint = _routeGradient();
      expect(routePaint, findsOneWidget);
      expect(tester.getTopLeft(routePaint).dx, 0);
      expect(tester.getTopRight(routePaint).dx, 800);
      // Verify the SafeArea translated side insets into a Padding with exact
      // values — a short centered text widget would satisfy a simple bounds
      // check even without SafeArea, so we inspect the Padding node directly.
      _expectSafeAreaPadding(tester, routePaint, left: 36, right: 52);
    },
  );

  testWidgets(
    'slide-in detail route background paints behind top inset while content stays safe',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final router = await _pumpPhoneApp(tester, const EdgeInsets.only(top: 48));

      router.go(
        '/vod/details/1',
        extra: const VodItem(
          id: 1,
          name: 'Test Movie',
          streamUrl: '',
          containerExtension: 'mp4',
        ),
      );
      await tester.pumpAndSettle();

      final bg = _routeDarkBox();
      expect(bg, findsAtLeastNWidgets(1));
      expect(tester.getTopLeft(bg.first), Offset.zero);
      _expectSafeAreaPadding(tester, bg.first, top: 48);
    },
  );
}

/// Asserts that the [SafeArea] inside [ancestor] inserted a [Padding] widget
/// whose insets match the expected values. Using the Padding node directly
/// proves the SafeArea is wired up regardless of where content happens to
/// render on screen.
void _expectSafeAreaPadding(
  WidgetTester tester,
  Finder ancestor, {
  double top = 0,
  double left = 0,
  double right = 0,
}) {
  final matches = tester
      .widgetList<Padding>(
        find.descendant(of: ancestor, matching: find.byType(Padding)),
      )
      .where(
        (p) =>
            p.padding is EdgeInsets &&
            (p.padding as EdgeInsets).top >= top &&
            (p.padding as EdgeInsets).left >= left &&
            (p.padding as EdgeInsets).right >= right,
      )
      .toList();
  expect(
    matches,
    isNotEmpty,
    reason:
        'Expected a SafeArea-inserted Padding with '
        'top>=$top left>=$left right>=$right within the route background',
  );
  final insets = matches.first.padding as EdgeInsets;
  if (top > 0) expect(insets.top, top);
  if (left > 0) expect(insets.left, left);
  if (right > 0) expect(insets.right, right);
}

Future<GoRouter> _pumpPhoneApp(
  WidgetTester tester,
  EdgeInsets padding,
) async {
  final memory = <String, Object?>{};
  final appState = AppStateController(
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
    deviceTypeOverride: DeviceType.phone,
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [overrideAppState(appState)],
      child: MaterialApp.router(
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: Colors.transparent,
        ),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(padding: padding),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _routeGradient() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).gradient is LinearGradient,
  );
}

Finder _routeDarkBox() {
  return find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == const Color(0xFF09090b),
  );
}
