import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/sports/sports_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:material_ui/material_ui.dart';

const _eventChannel = Channel(
  id: 5,
  name: 'NHL 05: Mammoth @ Maple Leafs',
  streamUrl: 'http://example.com/5',
);
const _otherChannel = Channel(
  id: 6,
  name: 'News 24',
  streamUrl: 'http://example.com/6',
);

const _capability = SportsCapability(
  leagues: [
    SportsLeague(
      id: 'hockey/nhl',
      name: 'NHL',
      abbreviation: 'NHL',
      isDefault: true,
    ),
  ],
);

Map<String, Object?> _team(String id, String name, String nickname) => {
  'id': id,
  'display_name': name,
  'short_name': nickname,
  'nickname': nickname,
  'abbreviation': id.toUpperCase(),
};

/// An editor serving one live NHL game (no crest URLs, so nothing reaches
/// the image cache).
Future<XtreamService> _editor() async {
  final service = XtreamService(
    transport: (request) async {
      if (request.action == null) {
        return {
          'user_info': {'auth': 1, 'status': 'Active'},
          'server_info': {'timezone': 'UTC'},
          'm3u_editor': {
            'version': '0.14.0',
            'features': ['sports'],
          },
        };
      }
      return {
        'fixtures': [
          {
            'id': '401',
            'league_id': 'hockey/nhl',
            'start': DateTime.now().toUtc().toIso8601String(),
            'state': 'live',
            'status_detail': '1st - 15:00',
            'home': {
              'score': '1',
              'team': _team('tor', 'Toronto Maple Leafs', 'Maple Leafs'),
            },
            'away': {
              'score': '0',
              'team': _team('uta', 'Utah Mammoth', 'Mammoth'),
            },
          },
        ],
      };
    },
  );
  await service.authenticate(
    const UserCredentials(
      server: 'https://editor.example',
      username: 'user',
      password: 'pass',
    ),
  );
  return service;
}

Future<CatalogRepository> _buildRepo(WidgetTester tester) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.defaultSource,
      kind: kCatalogKindLive,
      items: const [_eventChannel, _otherChannel],
    );
    return repo;
  });
  return repo!;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required CatalogRepository repo,
  required SportsSettings settings,
  required SportsCapability? capability,
  XtreamService? editor,
  List<Channel>? opened,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => true),
        catalogRepositoryProvider.overrideWith((_) => repo),
        shownPlaylistKeyProvider.overrideWith((_) => null),
        epgServiceProvider.overrideWith((_) => EpgService()),
        sportsSettingsProvider.overrideWith((_) => settings),
        sportsCapabilityProvider.overrideWith((_) => capability),
        if (editor != null)
          sportsServiceProvider.overrideWith((_) => SportsService(editor)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SportsScreen(
          onChannelSelect: (channel) => opened?.add(channel),
          useSidebarLayout: true,
        ),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets(
    'lists a live game with its channel, plays it, and follows a team',
    (tester) async {
      final repo = await _buildRepo(tester);
      final editor = (await tester.runAsync(_editor))!;
      final settings = SportsSettings();
      final opened = <Channel>[];

      await _pumpScreen(
        tester,
        repo: repo,
        settings: settings,
        capability: _capability,
        editor: editor,
        opened: opened,
      );

      expect(find.text('Live Now'), findsOneWidget);
      expect(find.text('Toronto Maple Leafs'), findsOneWidget);
      expect(find.text('1 channel'), findsOneWidget);

      // One channel carries it, so a press plays it straight away.
      await tester.tap(find.text('Toronto Maple Leafs'));
      await _settle(tester);
      expect(opened.map((channel) => channel.id), [_eventChannel.id]);

      await tester.longPress(find.text('Utah Mammoth'));
      await _settle(tester);
      await tester.tap(find.text('Follow Utah Mammoth'));
      await _settle(tester);
      expect(settings.isFollowing('hockey/nhl:uta'), isTrue);

      // "My Teams" now lists the game.
      await tester.tap(find.text('My Teams'));
      await _settle(tester);
      expect(find.text('Toronto Maple Leafs'), findsOneWidget);

      // Unmount so the live-score refresh timer is cancelled.
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('explains when the editor has Sports turned off', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);

    await _pumpScreen(
      tester,
      repo: repo,
      settings: SportsSettings(),
      capability: null,
    );

    expect(
      find.textContaining('Settings > Integrations > Sports'),
      findsOneWidget,
    );
  });
}
