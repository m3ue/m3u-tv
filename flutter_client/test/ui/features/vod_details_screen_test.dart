import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('VodDetailsScreen', () {
    testWidgets('fetches and renders real VOD metadata', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          service: _VodDetailsXtreamService(
            info: const VodInfo(
              id: 201,
              name: 'Big Buck Bunny',
              plot: 'A rabbit gets serious about defending his meadow.',
              genre: 'Animation',
              director: 'Sacha Goedegebure',
              cast: 'Bunny, Frank, Rinky',
              year: '2008',
              duration: '9m',
              rating: 4.5,
              coverUrl: 'https://img.example/bunny.jpg',
              containerExtension: 'mkv',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Big Buck Bunny'), findsWidgets);
      expect(
        find.text('A rabbit gets serious about defending his meadow.'),
        findsOneWidget,
      );
      expect(find.text('Animation'), findsOneWidget);
      expect(find.text('2008'), findsOneWidget);
      expect(find.text('9m'), findsOneWidget);
      expect(find.text('★ 4.5'), findsOneWidget);
      expect(find.text('MKV'), findsOneWidget);
      expect(find.text('Movie details'), findsNothing);
      expect(find.text('Ready to play in-app.'), findsNothing);
      expect(find.text('Play movie'), findsOneWidget);

      // Flush the palette-generator timeout timer the cover kicks off.
      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('keeps play action in app with metadata fallback', (
      tester,
    ) async {
      PlayerArgs? playerArgs;
      await tester.pumpWidget(
        _TestApp(
          service: _VodDetailsXtreamService(
            info: const VodInfo(
              id: 201,
              name: '',
              plot: 'Server synopsis',
              containerExtension: 'mkv',
            ),
          ),
          onPlay: (args) => playerArgs = args,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Play movie'));
      await tester.pump();

      expect(playerArgs?.streamUrl, 'http://example.com/movie/201.mp4');
      expect(playerArgs?.type, 'vod');
      expect(playerArgs?.metadata['container_extension'], 'mkv');
    });

    testWidgets('shows resume action and progress for started movies', (
      tester,
    ) async {
      PlayerArgs? playerArgs;
      await tester.pumpWidget(
        _TestApp(
          service: _VodDetailsXtreamService(
            info: const VodInfo(
              id: 201,
              name: 'Big Buck Bunny',
              plot: 'Server synopsis',
              duration: '01:40:00',
              containerExtension: 'mkv',
            ),
          ),
          progressList: const <Progress>[
            Progress(
              viewerId: 'viewer-admin',
              contentType: ContentType.vod,
              streamId: 201,
              positionSeconds: 1500,
              durationSeconds: 6000,
            ),
          ],
          onPlay: (args) => playerArgs = args,
        ),
      );
      await tester.pumpAndSettle();

      // Remaining time: 6000s total - 1500s watched = 4500s = 75 min.
      expect(find.text('1h 15m left'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Start from Beginning'), findsOneWidget);

      await tester.tap(find.text('1h 15m left'));
      await tester.pump();

      // The button resumes directly - no intermediate resume/start-over
      // modal on this screen, since "Start from Beginning" is its own
      // button right next to it.
      expect(playerArgs?.startPosition, 1500.0);

      await tester.tap(find.text('Start from Beginning'));
      await tester.pump();

      expect(playerArgs?.startPosition, 0.0);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.service,
    this.progressList = const <Progress>[],
    this.onPlay,
  });

  final XtreamService service;
  final List<Progress> progressList;
  final void Function(PlayerArgs)? onPlay;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: VodDetailsScreen(
        item: const VodItem(
          id: 201,
          name: 'Fixture Movie',
          streamUrl: 'http://example.com/movie/201.mp4',
          containerExtension: 'mp4',
          rating: 3.5,
        ),
        xtreamService: service,
        progressList: progressList,
        onPlay: onPlay,
      ),
    );
  }
}

class _VodDetailsXtreamService extends XtreamService {
  _VodDetailsXtreamService({required this.info});

  final VodInfo info;

  @override
  Future<VodInfo> getVodInfo(int vodId) async => info;
}
