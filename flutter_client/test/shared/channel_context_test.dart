import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

Channel _channel(int id, String name, {String? category}) => Channel(
  id: id,
  name: name,
  streamUrl: 'http://host/live/$id.m3u8',
  categoryId: category,
);

void main() {
  group('ListChannelContext', () {
    final context = ListChannelContext([
      _channel(1, 'One'),
      _channel(2, 'Two'),
      _channel(3, 'Three'),
    ]);

    test('steps and wraps around both ends', () async {
      expect((await context.neighbour(2, 1))!.id, 3);
      expect((await context.neighbour(3, 1))!.id, 1);
      expect((await context.neighbour(1, -1))!.id, 3);
    });

    test('an unknown channel has no neighbour', () async {
      expect(await context.neighbour(9, 1), isNull);
      expect(await context.byId(9), isNull);
      expect((await context.byId(2))!.name, 'Two');
    });
  });

  group('CatalogChannelContext', () {
    late CatalogRepository repo;

    setUp(() async {
      repo = CatalogRepository(CatalogDatabase.memory());
      await repo.replaceItems(
        sourceKey: CatalogRepository.activeSource,
        kind: kCatalogKindLive,
        items: [
          _channel(1, 'Delta', category: 'news'),
          _channel(2, 'Alpha', category: 'sport'),
          _channel(3, 'Charlie', category: 'news'),
          _channel(4, 'Bravo', category: 'news'),
        ],
      );
    });

    tearDown(() => repo.close());

    test('moves through the query order, wrapping', () async {
      final context = CatalogChannelContext(
        repository: repo,
        query: const LiveChannelQuery(
          categoryId: 'news',
          sort: CatalogSort.nameNatural,
        ),
        length: 3,
        indexHint: 0,
      );
      // News, A-Z: Bravo (4), Charlie (3), Delta (1).
      expect((await context.neighbour(4, 1))!.id, 3);
      expect((await context.neighbour(3, 1))!.id, 1);
      expect((await context.neighbour(1, 1))!.id, 4);
      expect((await context.neighbour(4, -1))!.id, 1);
    });

    test('finds the channel without a hint, or with a stale one', () async {
      for (final hint in [null, 3]) {
        final context = CatalogChannelContext(
          repository: repo,
          length: 4,
          indexHint: hint,
        );
        expect((await context.neighbour(2, 1))!.id, 3, reason: 'hint $hint');
      }
    });

    test('a channel outside the query has no neighbour', () async {
      final context = CatalogChannelContext(
        repository: repo,
        query: const LiveChannelQuery(categoryId: 'news'),
        length: 3,
      );
      expect(await context.neighbour(2, 1), isNull);
    });

    test('byId resolves any active channel', () async {
      final context = CatalogChannelContext(repository: repo, length: 0);
      expect((await context.byId(4))!.name, 'Bravo');
      expect(await context.byId(99), isNull);
    });
  });
}
