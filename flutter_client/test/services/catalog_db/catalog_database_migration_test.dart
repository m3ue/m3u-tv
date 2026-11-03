import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_store.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('m3u-tv-catalog-v7-');
    file = File('${directory.path}/catalog.db');
  });

  tearDown(() => directory.delete(recursive: true));

  test('from version 7 the guide starts over and catalogs are kept', () async {
    final old = CatalogDatabase(NativeDatabase(file));
    final oldRepo = CatalogRepository(old);
    await oldRepo.replaceItems(
      sourceKey: 'sports',
      kind: kCatalogKindLive,
      items: const [
        Channel(id: 101, name: 'Sports One', streamUrl: 'http://host/1.ts'),
      ],
    );
    await oldRepo.kvPut('sports/__ts_liveStreams', '');
    await oldRepo.kvPut('__ts_epgGuide', '');
    // The version 7 guide: one table for whichever playlist was shown.
    await old.customStatement('DROP TABLE epg_programmes');
    await old.customStatement(
      'CREATE TABLE epg_programmes (channel_id TEXT NOT NULL, '
      'start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, '
      "title TEXT NOT NULL DEFAULT '', PRIMARY KEY (channel_id, start_ms))",
    );
    await old.customStatement(
      "INSERT INTO epg_programmes VALUES ('a', 0, 1, 'Old guide')",
    );
    await old.customStatement('PRAGMA user_version = 7');
    await old.close();

    final upgraded = CatalogDatabase(NativeDatabase(file));
    addTearDown(upgraded.close);
    final repo = CatalogRepository(upgraded)..shownSource = 'sports';

    expect(
      await repo.countItems(sourceKey: 'sports', kind: kCatalogKindLive),
      1,
    );
    expect(await repo.kvUpdatedAt('sports/__ts_liveStreams'), isNotNull);
    expect(await repo.kvUpdatedAt('__ts_epgGuide'), isNull);
    expect(await repo.programmesForChannels({'a'}), isEmpty);

    final start = DateTime.utc(2026, 4, 1, 12);
    await repo.applyEpgOps([
      EpgReplaceChannels({
        'a': [
          EpgProgram(
            channelId: 'a',
            title: 'New guide',
            description: '',
            start: start,
            end: start.add(const Duration(hours: 1)),
          ),
        ],
      }),
    ]);
    expect(
      (await repo.programmesForChannels({'a'}))['a']!.single.title,
      'New guide',
    );
  });
}
