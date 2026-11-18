import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, {List<String> artwork = const []}) {
    tester.view
      ..physicalSize = const Size(1920, 1080)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: MediaPreviewSection.builder(
            title: 'DVR',
            emptyLabel: 'None',
            itemCount: 1,
            baseCardWidth: MediaBrowsingMetrics.landscapeCardWidth,
            baseCardHeight: MediaBrowsingMetrics.landscapeCardHeight,
            itemBuilder: (context, index, size, {required autofocus}) =>
                PreviewEntryTile(
                  item: MediaPreviewItem(
                    title: 'DVR Recordings',
                    subtitle: '12 recordings',
                    fallbackIcon: Icons.video_library,
                    onTap: () {},
                  ),
                  width: size.width,
                  artworkUrls: artwork,
                ),
          ),
        ),
      ),
    );
  }

  testWidgets('an entry tile is a Continue Watching card in size', (
    tester,
  ) async {
    await pumpRow(tester);

    final tile = tester.getSize(find.byType(PreviewEntryTile));
    expect(tile.width, MediaBrowsingMetrics.landscapeCardWidth);
    expect(tester.takeException(), isNull);
    expect(find.text('DVR Recordings'), findsOneWidget);
    expect(find.text('12 recordings'), findsOneWidget);
  });

  testWidgets('an entry tile with posters lays out without overflow', (
    tester,
  ) async {
    await pumpRow(tester, artwork: const ['', 'a', 'b', 'c', 'd']);

    expect(tester.takeException(), isNull);
    expect(find.byType(ResilientMediaImage), findsNWidgets(3));
  });
}
