import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/storage_page.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/services/storage_usage.dart';

const _sports = SavedPlaylist(
  id: 'sports',
  credentials: UserCredentials(
    server: 'https://sports.invalid',
    username: 'owner-login',
    password: 'sports-secret',
  ),
);
const _movies = SavedPlaylist(
  id: 'movies',
  credentials: UserCredentials(
    server: 'https://movies.invalid',
    username: 'owner-login',
    password: 'movies-secret',
  ),
);

/// Stands in for the app: what is stored, and what each action did.
class _FakeStorage {
  final Map<String, CatalogSourceUsage> stored = {
    'sports': const CatalogSourceUsage(
      channels: 1200,
      movies: 300,
      bytes: 3 * 1024 * 1024,
    ),
    'movies': const CatalogSourceUsage(movies: 40, bytes: 1024 * 1024),
  };
  int limit = 3;
  Duration interval = const Duration(hours: 6);
  final List<String> clearedPlaylists = [];
  final List<CacheClearScope> cleared = [];

  StorageManagement get management => StorageManagement(
    loadUsage: () async => StorageUsage(
      playlists: [
        for (final playlist in [_sports, _movies])
          PlaylistStorage(
            playlist: playlist,
            usage: stored[playlist.id],
            updatedAt: null,
            isShown: playlist.id == 'sports',
            bytesOnDisk: stored[playlist.id]?.bytes ?? 0,
          ),
      ],
      guideProgrammes: 5000,
      guideBytes: 2 * 1024 * 1024,
      catalogBytes: 6 * 1024 * 1024,
      artworkBytes: null,
    ),
    onClearPlaylist: (id) async {
      clearedPlaylists.add(id);
      stored.remove(id);
    },
    onClear: (scope) async => cleared.add(scope),
    cachedPlaylistLimit: () => limit,
    cachedPlaylistLimitOptions: const [1, 2, 3, 5],
    onCachedPlaylistLimitChanged: (value) async => limit = value,
    epgRefreshInterval: () => interval,
    epgRefreshOptions: const [Duration(hours: 1), Duration(hours: 6)],
    onEpgRefreshIntervalChanged: (value) async => interval = value,
  );
}

void main() {
  late _FakeStorage storage;

  setUp(() => storage = _FakeStorage());

  Future<void> openPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoragePage(storage: storage.management),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows what each playlist, the guide and artwork take', (
    tester,
  ) async {
    await openPage(tester);

    expect(find.text('6 MB'), findsOneWidget); // Total (no artwork size)
    expect(find.text('4 MB'), findsOneWidget); // Playlists
    expect(find.text('sports.invalid'), findsOneWidget);
    expect(find.text('1,500 items'), findsOneWidget);
    expect(find.text('3 MB'), findsOneWidget);
    expect(find.text('movies.invalid'), findsOneWidget);
    expect(find.text('40 items'), findsOneWidget);
    // The active playlist is marked by a check next to its name.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(Row, 'sports.invalid'),
        matching: find.byIcon(Icons.check),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(Row, 'movies.invalid'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
    expect(find.text('2 MB · 5,000 programmes'), findsOneWidget);
    expect(find.text('The 3 most recent'), findsOneWidget);
    // Never credentials.
    expect(find.textContaining('owner-login'), findsNothing);
  });

  testWidgets('clearing another playlist frees it after asking', (
    tester,
  ) async {
    await openPage(tester);

    await tester.tap(find.text('movies.invalid'));
    await tester.pumpAndSettle();
    expect(find.text('Clear stored content?'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    expect(storage.clearedPlaylists, ['movies']);
    expect(find.text('Not stored on this device'), findsOneWidget);
    expect(find.text('Stored content cleared.'), findsOneWidget);
  });

  testWidgets('a playlist with nothing stored has nothing to clear', (
    tester,
  ) async {
    storage.stored.remove('movies');
    await openPage(tester);

    await tester.tap(find.text('movies.invalid'));
    await tester.pumpAndSettle();

    expect(find.text('Clear stored content?'), findsNothing);
    expect(storage.clearedPlaylists, isEmpty);
  });

  testWidgets('how many playlists are kept can be changed', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Playlists kept on this device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only the active playlist'));
    await tester.pumpAndSettle();

    expect(storage.limit, 1);
    expect(find.text('Only the active playlist'), findsOneWidget);
  });

  testWidgets('the guide refreshes after asking', (tester) async {
    await openPage(tester);

    await tester.tap(find.text('Guide data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear & Refresh'));
    await tester.pumpAndSettle();

    expect(storage.cleared, [CacheClearScope.epg]);
  });
}
