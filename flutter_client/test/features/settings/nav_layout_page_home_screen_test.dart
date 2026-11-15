import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/nav_layout_page.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/client_config.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:material_ui/material_ui.dart';

ClientConfig _config({required String mode}) => ClientConfig.fromJson({
  'revision': 'rev',
  'settings': const <String, Object?>{},
  'home_screen': {
    'mode': mode,
    'sections': const [
      {
        'section': 'series',
        'nav': true,
        'home': true,
        'rows': [
          {'id': 'default', 'kind': 'default'},
          {
            'id': 'xmas',
            'kind': 'category',
            'title': 'Christmas Movies',
            'params': {'category_id': '812'},
          },
        ],
      },
    ],
  },
});

void main() {
  Future<ViewSettingsService> pumpPage(
    WidgetTester tester, {
    required String mode,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = ViewSettingsService();
    await service.applyClientConfig(_config(mode: mode));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          availableMainRoutesProvider.overrideWith(
            (_) => RouteNames.mainRoutes,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: NavLayoutPage(service: service, usesRemote: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets('lists a server row under its section with a Home switch', (
    tester,
  ) async {
    final service = await pumpPage(tester, mode: 'default');

    expect(find.text('Christmas Movies'), findsOneWidget);
    final seriesTop = tester.getTopLeft(find.text('Series')).dy;
    expect(
      tester.getTopLeft(find.text('Christmas Movies')).dy,
      greaterThan(seriesTop),
    );

    final rowSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Christmas Movies'),
        matching: find.byType(IntrinsicHeight),
      ),
      matching: find.byType(AppSwitch),
    );
    await tester.tap(rowSwitch);
    await tester.pumpAndSettle();

    expect(service.hiddenHomeRowIds, contains('xmas'));
    expect(find.byType(AppButton), findsOneWidget, reason: 'reset is offered');
  });

  testWidgets('an enforced layout is read-only', (tester) async {
    await pumpPage(tester, mode: 'enforced');

    final l = AppLocalizations.of(tester.element(find.byType(NavLayoutPage)));
    expect(find.text(l.settingsManagedByServer), findsOneWidget);
    expect(find.text('Christmas Movies'), findsOneWidget);
    expect(find.byType(AppButton), findsNothing);
    for (final element in find.byType(AppSwitch).evaluate()) {
      expect((element.widget as AppSwitch).onChanged, isNull);
    }
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });
}
