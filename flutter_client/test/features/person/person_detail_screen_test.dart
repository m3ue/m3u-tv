import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/person/person_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('PersonDetailScreen', () {
    testWidgets('renders person bio/photo and filmography credits', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          service: _PersonDetailXtreamService(
            filmography: const ActorFilmography(
              person: PersonDetails(
                name: 'Idris Elba',
                bio: 'A famous test actor.',
                photo: 'https://example.com/idris.jpg',
              ),
              credits: [
                FilmographyCredit(
                  tmdbId: 550,
                  title: 'Fight Club',
                  mediaType: 'movie',
                  year: '1999',
                  inLibrary: true,
                  localId: 42,
                ),
                FilmographyCredit(
                  tmdbId: 1399,
                  title: 'Game of Thrones',
                  mediaType: 'tv',
                  year: '2011',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A famous test actor.'), findsOneWidget);
      expect(find.text('Fight Club'), findsOneWidget);
      expect(find.text('Game of Thrones'), findsOneWidget);
    });

    testWidgets('tapping an in-library credit fires onOpenCredit', (
      tester,
    ) async {
      // Taller than the default 800x600 test surface - the wide/non-mobile
      // layout's horizontal filmography strip sits below the header and
      // library-filter switch, past the default viewport's bottom edge.
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FilmographyCredit? opened;
      await tester.pumpWidget(
        _TestApp(
          service: _PersonDetailXtreamService(
            filmography: const ActorFilmography(
              credits: [
                FilmographyCredit(
                  tmdbId: 550,
                  title: 'Fight Club',
                  mediaType: 'movie',
                  inLibrary: true,
                  localId: 42,
                ),
              ],
            ),
          ),
          onOpenCredit: (credit) => opened = credit,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fight Club'));
      await tester.pump();
      expect(opened?.localId, 42);
    });

    testWidgets('a credit not in the library does not fire onOpenCredit', (
      tester,
    ) async {
      FilmographyCredit? opened;
      await tester.pumpWidget(
        _TestApp(
          service: _PersonDetailXtreamService(
            filmography: const ActorFilmography(
              credits: [
                FilmographyCredit(
                  tmdbId: 1399,
                  title: 'Game of Thrones',
                  mediaType: 'tv',
                ),
              ],
            ),
          ),
          onOpenCredit: (credit) => opened = credit,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Game of Thrones'));
      await tester.pump();
      expect(opened, isNull);
    });

    testWidgets('renders the empty state when there are no credits', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          service: _PersonDetailXtreamService(
            filmography: const ActorFilmography(credits: []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l = AppLocalizations.of(
        tester.element(find.byType(PersonDetailScreen)),
      );
      expect(find.text(l.personDetailsEmpty), findsOneWidget);
    });

    testWidgets('shows the actor name as the title immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          service: _PersonDetailXtreamService(
            filmography: const ActorFilmography(credits: []),
          ),
        ),
      );
      // Before the future resolves - title comes from the widget, not the
      // fetch.
      expect(find.text('Idris Elba'), findsOneWidget);
    });

    group('library filter toggle', () {
      const filmography = ActorFilmography(
        credits: [
          FilmographyCredit(
            tmdbId: 550,
            title: 'Fight Club',
            mediaType: 'movie',
            inLibrary: true,
            localId: 42,
          ),
          FilmographyCredit(
            tmdbId: 1399,
            title: 'Game of Thrones',
            mediaType: 'tv',
          ),
        ],
      );

      testWidgets('shows both credits by default (switch off)', (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            service: _PersonDetailXtreamService(filmography: filmography),
          ),
        );
        await tester.pumpAndSettle();

        final l = AppLocalizations.of(
          tester.element(find.byType(PersonDetailScreen)),
        );
        expect(find.text(l.personDetailsFilterInLibrary), findsOneWidget);
        expect(
          tester.widget<Switch>(find.byType(Switch)).value,
          isFalse,
        );
        expect(find.text('Fight Club'), findsOneWidget);
        expect(find.text('Game of Thrones'), findsOneWidget);
      });

      testWidgets(
        'tapping "In Library" hides credits that are not in the library',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              service: _PersonDetailXtreamService(filmography: filmography),
            ),
          );
          await tester.pumpAndSettle();

          final l = AppLocalizations.of(
            tester.element(find.byType(PersonDetailScreen)),
          );
          await tester.tap(find.text(l.personDetailsFilterInLibrary));
          await tester.pumpAndSettle();

          expect(find.text('Fight Club'), findsOneWidget);
          expect(find.text('Game of Thrones'), findsNothing);
        },
      );

      testWidgets(
        'shows a dedicated empty state when the library filter matches nothing',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              service: _PersonDetailXtreamService(
                filmography: const ActorFilmography(
                  credits: [
                    FilmographyCredit(
                      tmdbId: 1399,
                      title: 'Game of Thrones',
                      mediaType: 'tv',
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final l = AppLocalizations.of(
            tester.element(find.byType(PersonDetailScreen)),
          );
          await tester.tap(find.text(l.personDetailsFilterInLibrary));
          await tester.pumpAndSettle();

          expect(find.text(l.personDetailsNoLibraryMatches), findsOneWidget);
        },
      );

      testWidgets('hidden entirely when includeLibraryFilter is false', (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            service: _PersonDetailXtreamService(filmography: filmography),
            includeLibraryFilter: false,
          ),
        );
        await tester.pumpAndSettle();

        final l = AppLocalizations.of(
          tester.element(find.byType(PersonDetailScreen)),
        );
        expect(find.text(l.personDetailsFilterInLibrary), findsNothing);
        expect(find.byType(Switch), findsNothing);
        // Both still render, unfiltered.
        expect(find.text('Fight Club'), findsOneWidget);
        expect(find.text('Game of Thrones'), findsOneWidget);
      });
    });

    testWidgets(
      'with includeLibraryFilter false (AIOStreams), a credit not marked '
      'in_library still fires onOpenCredit',
      (tester) async {
        // Taller than the default 800x600 test surface - see the other
        // tap test above for why.
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        FilmographyCredit? opened;
        await tester.pumpWidget(
          _TestApp(
            service: _PersonDetailXtreamService(
              filmography: const ActorFilmography(
                credits: [
                  FilmographyCredit(
                    tmdbId: 1399,
                    title: 'Game of Thrones',
                    mediaType: 'tv',
                  ),
                ],
              ),
            ),
            includeLibraryFilter: false,
            onOpenCredit: (credit) => opened = credit,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Game of Thrones'));
        await tester.pump();
        expect(opened?.tmdbId, 1399);
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.service,
    this.onOpenCredit,
    this.includeLibraryFilter = true,
  });

  final XtreamService service;
  final ValueChanged<FilmographyCredit>? onOpenCredit;
  final bool includeLibraryFilter;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PersonDetailScreen(
        name: 'Idris Elba',
        personId: 12345,
        xtreamService: service,
        onOpenCredit: onOpenCredit,
        includeLibraryFilter: includeLibraryFilter,
      ),
    );
  }
}

class _PersonDetailXtreamService extends XtreamService {
  _PersonDetailXtreamService({required this.filmography});

  final ActorFilmography filmography;

  @override
  Future<ActorFilmography> fetchActorFilmography({
    int? personId,
    String? name,
  }) async => filmography;
}
