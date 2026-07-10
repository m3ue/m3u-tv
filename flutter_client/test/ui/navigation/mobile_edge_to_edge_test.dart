import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
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
      final contentRect = tester.getRect(
        find.text('Please connect to your service in Settings'),
      );

      expect(routePaint, findsOneWidget);
      expect(tester.getTopLeft(routePaint).dx, 0);
      expect(tester.getTopRight(routePaint).dx, 800);
      expect(contentRect.left, greaterThanOrEqualTo(36));
      expect(contentRect.right, lessThanOrEqualTo(748));
    },
  );
}

Future<void> _pumpPhoneApp(
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Finder _routeGradient() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).gradient is LinearGradient,
  );
}
