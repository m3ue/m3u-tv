import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_strip.dart';

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
      expect(find.text('Trailer'), findsNothing);

      // Flush the palette-generator timeout timer the cover kicks off.
      await tester.pump(const Duration(seconds: 16));
    });

    testWidgets('shows a trailer button when the movie has one', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          service: _VodDetailsXtreamService(
            info: const VodInfo(
              id: 201,
              name: 'Big Buck Bunny',
              containerExtension: 'mkv',
              trailerUrl: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play movie'), findsOneWidget);
      expect(find.text('Trailer'), findsOneWidget);
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

  group('VodDetailsScreen - rich cast', () {
    testWidgets(
      'renders rich cast row when richCast is populated',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            service: _VodDetailsXtreamService(
              info: const VodInfo(
                id: 201,
                name: 'Big Buck Bunny',
                cast: 'Bunny, Frank, Rinky',
                richCast: <CastMember>[
                  CastMember(name: 'Bunny', character: 'Frank'),
                  CastMember(name: 'Big Buck', character: 'The Squirrel'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Wide layout: the shared scrollable CastStrip, not the compact chip.
        expect(find.byType(CastStrip), findsOneWidget);
        expect(find.byType(CastMemberRow), findsNothing);
        // Names also render as the resilient-image placeholder, so allow >1.
        expect(find.text('Bunny'), findsWidgets);
        expect(find.text('Big Buck'), findsWidgets);
        expect(find.text('Frank'), findsOneWidget);
        expect(find.text('The Squirrel'), findsOneWidget);
      },
    );

    testWidgets(
      'hides rich cast row when richCast is null (unpatched server)',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            service: _VodDetailsXtreamService(
              info: const VodInfo(
                id: 201,
                name: 'Big Buck Bunny',
                cast: 'Bunny, Frank, Rinky',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
        // Existing string-cast MetaCreditLine is preserved - RichText with
        // the "Cast:" label is present in the tree.
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is RichText &&
                w.text.toPlainText().contains('Cast:') &&
                w.text.toPlainText().contains('Bunny, Frank, Rinky'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'hides rich cast row when richCast is empty list',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            service: _VodDetailsXtreamService(
              info: const VodInfo(
                id: 201,
                name: 'Big Buck Bunny',
                richCast: <CastMember>[],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
      },
    );

    testWidgets(
      'narrow layout: rich cast picker chip opens bottom sheet listing all members',
      (tester) async {
        // Phone width (below the 600px wide breakpoint).
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final richCast = <CastMember>[
          const CastMember(name: 'Bryan Cranston', character: 'Walter White'),
          const CastMember(name: 'Aaron Paul', character: 'Jesse Pinkman'),
          const CastMember(name: 'Anna Gunn', character: 'Skyler White'),
          const CastMember(name: 'Dean Norris', character: 'Hank Schrader'),
          const CastMember(name: 'Betsy Brandt', character: 'Marie Schrader'),
        ];
        await tester.pumpWidget(
          _TestApp(
            service: _VodDetailsXtreamService(
              info: VodInfo(
                id: 201,
                name: 'Big Buck Bunny',
                richCast: richCast,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Compact layout renders a single picker chip: the localized
        // "Cast" label + a count badge. Member names live in the sheet.
        final l = AppLocalizations.of(
          tester.element(find.byType(CastMemberRow)),
        );
        expect(find.text(l.vodCast), findsOneWidget);
        expect(find.text('Bryan Cranston'), findsNothing);

        await tester.tap(find.text(l.vodCast));
        await tester.pumpAndSettle();

        // Sheet lists all 5 members with their characters.
        expect(find.text(l.castShowAll), findsOneWidget);
        expect(find.text('Bryan Cranston'), findsOneWidget);
        expect(find.text('Aaron Paul'), findsOneWidget);
        expect(find.text('Anna Gunn'), findsOneWidget);
        expect(find.text('Dean Norris'), findsOneWidget);
        expect(find.text('Betsy Brandt'), findsOneWidget);
        expect(find.text('Marie Schrader'), findsOneWidget);
      },
    );

    testWidgets(
      'wide layout: renders the scrollable CastStrip with no show-all '
      'affordance (every member is reachable by scrolling)',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final richCast = <CastMember>[
          for (var i = 1; i <= 12; i++)
            CastMember(name: 'Cast Member $i', character: 'Role $i'),
        ];
        await tester.pumpWidget(
          _TestApp(
            service: _VodDetailsXtreamService(
              info: VodInfo(
                id: 201,
                name: 'Big Buck Bunny',
                richCast: richCast,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastStrip), findsOneWidget);
        expect(find.byType(CastMemberRow), findsNothing);
        final l = AppLocalizations.of(tester.element(find.byType(CastStrip)));
        // No "+N / show all" tile, no dialog - the wide row just scrolls.
        expect(find.text(l.castShowAll), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Cast Member 1'), findsWidgets);
        expect(find.text('Role 1'), findsOneWidget);
      },
    );
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
