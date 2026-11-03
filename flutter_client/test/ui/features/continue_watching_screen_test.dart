import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/continue_watching/continue_watching_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Builds a fresh in-memory catalog repository populated with [vodItems]/
/// [seriesList], via `tester.runAsync` since drift's real I/O does not
/// resolve under flutter_test's default fakeAsync zone.
Future<CatalogRepository> _buildRepo(
  WidgetTester tester, {
  List<VodItem> vodItems = const [],
  List<Series> seriesList = const [],
}) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.defaultSource,
      kind: kCatalogKindVod,
      items: vodItems,
    );
    await repo.replaceItems(
      sourceKey: CatalogRepository.defaultSource,
      kind: kCatalogKindSeries,
      items: seriesList,
    );
    return repo;
  });
  return repo!;
}

void main() {
  group('ContinueWatchingScreen', () {
    late List<Progress> testProgress;

    setUp(() {
      testProgress = [
        const Progress(
          viewerId: 'v1',
          contentType: ContentType.vod,
          streamId: 10,
          positionSeconds: 300,
          durationSeconds: 3600,
        ),
        const Progress(
          viewerId: 'v1',
          contentType: ContentType.episode,
          streamId: 20,
          positionSeconds: 600,
          durationSeconds: 2700,
          seriesId: 5,
          seasonNumber: 2,
        ),
      ];
    });

    testWidgets('renders continue watching items', (tester) async {
      final repo = await _buildRepo(
        tester,
        vodItems: const [
          VodItem(
            id: 10,
            name: 'The Matrix',
            streamUrl: 'http://example.com/10.mp4',
            containerExtension: 'mp4',
          ),
        ],
        seriesList: const [Series(id: 5, name: 'Breaking Bad')],
      );
      await tester.pumpWidget(
        _TestApp(progressList: testProgress, catalogRepository: repo),
      );
      await tester.pumpAndSettle();

      // Untestable network images fall back to an icon tile that also shows
      // the title text, so the title legitimately appears more than once.
      expect(find.text('The Matrix'), findsAtLeastNWidgets(1));
      expect(find.text('Breaking Bad'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows progress bar for items', (tester) async {
      final repo = await _buildRepo(
        tester,
        vodItems: const [
          VodItem(
            id: 10,
            name: 'The Matrix',
            streamUrl: 'http://example.com/10.mp4',
            containerExtension: 'mp4',
          ),
        ],
        seriesList: const [Series(id: 5, name: 'Breaking Bad')],
      );
      await tester.pumpWidget(
        _TestApp(progressList: testProgress, catalogRepository: repo),
      );
      await tester.pumpAndSettle();

      // Should find LinearProgressIndicator for progress bars
      expect(find.byType(LinearProgressIndicator), findsAtLeast(1));
    });

    testWidgets('shows empty state when no progress items', (tester) async {
      final repo = await _buildRepo(tester);
      await tester.pumpWidget(
        _TestApp(progressList: const [], catalogRepository: repo),
      );
      await tester.pumpAndSettle();

      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l.homeNoContinueWatching), findsOneWidget);
    });

    testWidgets('tapping item triggers onProgressSelect callback', (
      tester,
    ) async {
      Progress? selectedProgress;
      final repo = await _buildRepo(
        tester,
        vodItems: const [
          VodItem(
            id: 10,
            name: 'The Matrix',
            streamUrl: 'http://example.com/10.mp4',
            containerExtension: 'mp4',
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(
          progressList: testProgress,
          catalogRepository: repo,
          onProgressSelect: (progress) => selectedProgress = progress,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.ancestor(
          of: find.text('The Matrix').first,
          matching: find.byType(DpadInkWell),
        ),
      );
      await tester.pumpAndSettle();

      expect(selectedProgress, isNotNull);
      expect(selectedProgress!.streamId, 10);
    });

    testWidgets('only shows items with position > 30 seconds', (
      tester,
    ) async {
      final shortProgress = [
        const Progress(
          viewerId: 'v1',
          contentType: ContentType.vod,
          streamId: 10,
          positionSeconds: 10, // Less than 30 seconds
          durationSeconds: 3600,
        ),
      ];
      final repo = await _buildRepo(
        tester,
        vodItems: const [
          VodItem(
            id: 10,
            name: 'The Matrix',
            streamUrl: 'http://example.com/10.mp4',
            containerExtension: 'mp4',
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(progressList: shortProgress, catalogRepository: repo),
      );
      await tester.pumpAndSettle();

      final l = AppLocalizations.of(tester.element(find.byType(Scaffold)));
      expect(find.text(l.homeNoContinueWatching), findsOneWidget);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.progressList,
    required this.catalogRepository,
    this.onProgressSelect,
  });

  final List<Progress> progressList;
  final CatalogRepository catalogRepository;
  final void Function(Progress)? onProgressSelect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ContinueWatchingScreen(
        progressList: progressList,
        catalogRepository: catalogRepository,
        onProgressSelect: onProgressSelect ?? (_) {},
      ),
    );
  }
}
