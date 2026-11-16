import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_catalog_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

class _FakeAioApi extends AIOStreamsApiService {
  _FakeAioApi() : super(xtreamService: XtreamService());

  @override
  Future<List<AIOStreamsItem>> getCatalog(
    int integrationId,
    String type,
    String catalogId, {
    int skip = 0,
    String? search,
    String? genre,
  }) async => [
    for (var i = 0; i < 6; i++)
      AIOStreamsItem(id: '$catalogId-$i', type: type, name: 'Item $i'),
  ];
}

void main() {
  testWidgets(
    'moving between search and the top row never scrolls away from the top',
    (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Dpad(child: child!),
          home: AIOStreamsHomeScreen(
            integrations: const [
              AIOStreamsIntegration(
                id: 1,
                name: 'AIO',
                catalogs: [
                  AIOStreamsCatalog(
                    id: 'a',
                    type: 'movie',
                    name: 'A',
                    searchable: true,
                  ),
                  AIOStreamsCatalog(id: 'b', type: 'movie', name: 'B'),
                  AIOStreamsCatalog(id: 'c', type: 'movie', name: 'C'),
                ],
              ),
            ],
            apiService: _FakeAioApi(),
            onItemSelect: (_, _) {},
            onPlay: (_) {},
            onSearchSelect: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final seen = <double>[];
      position.addListener(() => seen.add(position.pixels));

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      String? focusedRow() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<MediaPreviewSection>()
          ?.title;

      // Focus starts on a top-row card; go up to search, then back down.
      await press(LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), isNull);
      expect(position.pixels, 0);
      seen.clear();
      await press(LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), 'A Movies');
      expect(seen.where((pixels) => pixels > 0.5), isEmpty);
      expect(position.pixels, 0);

      // Down a row scrolls away; back up to the top row returns to the top.
      await press(LogicalKeyboardKey.arrowDown);
      expect(focusedRow(), 'B Movies');
      expect(position.pixels, greaterThan(0));
      await press(LogicalKeyboardKey.arrowUp);
      expect(focusedRow(), 'A Movies');
      expect(position.pixels, 0);
    },
  );
}
