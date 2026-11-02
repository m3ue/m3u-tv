import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/playlists_page.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _sports = UserCredentials(
  server: 'https://editor.invalid',
  username: 'owner-login',
  password: 'sports-secret',
);
const _movies = UserCredentials(
  server: 'https://editor.invalid',
  username: 'owner-login',
  password: 'movies-secret',
);

void main() {
  late InMemorySecureStorage storage;
  late SavedPlaylistsService service;
  late AuthNotifier auth;

  setUp(() async {
    storage = InMemorySecureStorage();
    service = SavedPlaylistsService(storage: storage);
    await service.remember(_sports);
    await service.remember(_movies);
    await storage.write(
      'm3ue_tv_credentials',
      jsonEncode(<String, String>{
        'server': _sports.server,
        'username': _sports.username,
        'password': _sports.password,
      }),
    );
    auth = AuthNotifier(
      xtreamService: XtreamService(
        transport: (_) => throw StateError('no network in this test'),
      ),
      secureStorage: storage,
    );
    await auth.loadSavedCredentialsOffline();
  });

  PlaylistManagement management({
    Future<String?> Function(UserCredentials credentials)? onSwitch,
  }) => PlaylistManagement(
    service: service,
    onSwitch: onSwitch ?? (_) async => null,
    onRename: service.rename,
    onRemove: (id) async {
      await service.remove(id);
    },
  );

  Future<void> openPage(
    WidgetTester tester,
    PlaylistManagement playlists, {
    VoidCallback? onSwitched,
    Listenable? appState,
  }) async {
    await tester.pumpWidget(
      ListenableBuilder(
        // Stands in for the app shell, which rebuilds on app state changes.
        listenable: appState ?? Listenable.merge(const []),
        builder: (_, child) => child!,
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openPlaylistsPage(
                  context,
                  playlists: playlists,
                  authNotifier: auth,
                  onSwitched: onSwitched,
                ),
                child: const Text('Open playlists'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open playlists'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists playlists by host and marks the active one', (
    tester,
  ) async {
    await openPage(tester, management());

    expect(find.text('editor.invalid (1)'), findsOneWidget);
    expect(find.text('editor.invalid (2)'), findsOneWidget);
    expect(find.text('Active playlist'), findsOneWidget);
    expect(find.text('Add Playlist'), findsOneWidget);
    expect(find.textContaining('owner-login'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('switching runs behind a blocking dialog, then closes', (
    tester,
  ) async {
    final result = Completer<String?>();
    UserCredentials? requested;
    var switched = 0;
    await openPage(
      tester,
      management(
        onSwitch: (credentials) {
          requested = credentials;
          return result.future;
        },
      ),
      onSwitched: () => switched += 1,
    );

    await tester.tap(find.text('editor.invalid (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to Playlist'));
    await tester.pump();
    await tester.pump();

    expect(requested?.password, _movies.password);
    expect(find.text('Connecting...'), findsOneWidget);

    result.complete(null);
    await tester.pumpAndSettle();

    expect(switched, 1);
    expect(find.text('Open playlists'), findsOneWidget);
    expect(find.text('editor.invalid (2)'), findsNothing);
  });

  testWidgets('the switch starts only once the dialog has been built', (
    tester,
  ) async {
    // connectXtream notifies app state before its first await; starting it
    // while the dialog builds marked the shell dirty mid-build.
    final appState = ValueNotifier<int>(0);
    addTearDown(appState.dispose);
    await openPage(
      tester,
      management(
        onSwitch: (_) {
          appState.value += 1;
          return Future<String?>.value();
        },
      ),
      appState: appState,
    );

    await tester.tap(find.text('editor.invalid (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to Playlist'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(appState.value, 1);
    expect(find.text('Open playlists'), findsOneWidget);
  });

  testWidgets('a failed switch stays on the page and shows the error', (
    tester,
  ) async {
    var switched = 0;
    await openPage(
      tester,
      management(onSwitch: (_) async => 'Server unreachable'),
      onSwitched: () => switched += 1,
    );

    await tester.tap(find.text('editor.invalid (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to Playlist'));
    await tester.pumpAndSettle();

    expect(switched, 0);
    expect(
      find.text("Couldn't switch playlists: Server unreachable"),
      findsOneWidget,
    );
    expect(find.text('editor.invalid (2)'), findsOneWidget);
  });

  testWidgets('renaming shows the new name with the default beneath', (
    tester,
  ) async {
    await openPage(tester, management());

    await tester.tap(find.text('editor.invalid (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename Playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Movies');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('editor.invalid (2)'), findsOneWidget);
  });

  testWidgets('the connect screen offers saved playlists first', (
    tester,
  ) async {
    UserCredentials? connected;
    final pairing = DevicePairingService();
    addTearDown(pairing.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SettingsScreen(
            authNotifier: auth,
            traktService: TraktService(storage: InMemorySecureStorage()),
            devicePairingService: pairing,
            isConfiguredOverride: false,
            onConnect: (credentials) async {
              connected = credentials;
              return false;
            },
            playlists: management(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved Playlists'), findsOneWidget);

    await tester.tap(find.text('editor.invalid (2)'));
    await tester.pumpAndSettle();

    expect(connected?.password, _movies.password);
  });
}
