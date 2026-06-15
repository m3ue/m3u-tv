import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/continue_watching/continue_watching_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';

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
      await tester.pumpWidget(
        _TestApp(
          progressList: testProgress,
          vodItems: const [
            VodItem(
              id: 10,
              name: 'The Matrix',
              streamUrl: 'http://example.com/10.mp4',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [
            Series(id: 5, name: 'Breaking Bad'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('shows progress bar for items', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          progressList: testProgress,
          vodItems: const [
            VodItem(
              id: 10,
              name: 'The Matrix',
              streamUrl: 'http://example.com/10.mp4',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [
            Series(id: 5, name: 'Breaking Bad'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Should find LinearProgressIndicator for progress bars
      expect(find.byType(LinearProgressIndicator), findsAtLeast(1));
    });

    testWidgets('shows empty state when no progress items', (tester) async {
      await tester.pumpWidget(
        const _TestApp(
          progressList: [],
          vodItems: [],
          seriesList: [],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No continue watching items'), findsOneWidget);
    });

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          progressList: testProgress,
          vodItems: const [],
          seriesList: const [],
          isConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('tapping item triggers onResume callback', (tester) async {
      Progress? selectedProgress;
      await tester.pumpWidget(
        _TestApp(
          progressList: testProgress,
          vodItems: const [
            VodItem(
              id: 10,
              name: 'The Matrix',
              streamUrl: 'http://example.com/10.mp4',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [],
          onResume: (progress) => selectedProgress = progress,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('The Matrix'));
      await tester.pumpAndSettle();

      expect(selectedProgress, isNotNull);
      expect(selectedProgress!.streamId, 10);
    });

    testWidgets('only shows items with position > 30 seconds', (tester) async {
      final shortProgress = [
        const Progress(
          viewerId: 'v1',
          contentType: ContentType.vod,
          streamId: 10,
          positionSeconds: 10, // Less than 30 seconds
          durationSeconds: 3600,
        ),
      ];
      await tester.pumpWidget(
        _TestApp(
          progressList: shortProgress,
          vodItems: const [
            VodItem(
              id: 10,
              name: 'The Matrix',
              streamUrl: 'http://example.com/10.mp4',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [],
        ),
      );
      await tester.pumpAndSettle();

      // Should show empty state since position < 30 seconds
      expect(find.text('No continue watching items'), findsOneWidget);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.progressList,
    required this.vodItems,
    required this.seriesList,
    this.isConfigured = true,
    this.onResume,
  });

  final List<Progress> progressList;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Progress)? onResume;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: ContinueWatchingScreen(
        progressList: progressList,
        vodItems: vodItems,
        seriesList: seriesList,
        isConfigured: isConfigured,
        onResume: onResume ?? (_) {},
      ),
    );
  }
}
