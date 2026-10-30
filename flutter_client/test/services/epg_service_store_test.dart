import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
  final base = DateTime.utc(2026, 5, 1, 12);
  late DateTime now;
  late CatalogRepository repo;
  late EpgService service;

  EpgProgram show(String channel, int startHour, {String? title}) => EpgProgram(
    channelId: channel,
    title: title ?? '$channel ${12 + startHour}:00',
    description: '',
    start: base.add(Duration(hours: startHour)),
    end: base.add(Duration(hours: startHour + 1)),
  );
  List<EpgProgram> day(String channel) => [
    for (var h = 0; h < 8; h++) show(channel, h),
  ];
  Channel channel(String epgId) => Channel(
    id: epgId.hashCode,
    name: epgId,
    streamUrl: 'x',
    epgChannelId: epgId,
  );

  /// Lets queued store writes, loads and refills (microtask-scheduled, then
  /// real database futures) finish.
  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await pumpEventQueue();
      await service.flushStore();
    }
    await pumpEventQueue();
  }

  setUp(() {
    now = base.add(const Duration(minutes: 10));
    repo = CatalogRepository(CatalogDatabase.memory());
    service = EpgService(
      clock: () => now,
      store: repo,
      residentCapacity: 2,
    );
  });

  tearDown(() => repo.close());

  test(
    'a full fetch keeps only the hot slice and writes the rest through',
    () async {
      service.applySuccessfulResponse(['a'], day('a'));
      await settle();

      // Now/next read the hot slice.
      final current = service.lookup('a')!;
      expect(current.current.title, 'a 12:00');
      expect(current.next!.title, 'a 13:00');
      expect(service.programsForId('a'), hasLength(3));

      // Everything reached the store.
      expect((await repo.programmesForChannels({'a'}))['a'], hasLength(8));
    },
  );

  test('programsForChannel loads the full schedule on demand', () async {
    service.applySuccessfulResponse(['a'], day('a'));
    await settle();

    var notified = 0;
    service.addListener(() => notified++);
    // First call answers from the hot slice and queues a load.
    expect(service.programsForChannel(channel('a')), hasLength(3));
    await settle();
    expect(notified, greaterThan(0));
    expect(service.programsForChannel(channel('a')), hasLength(8));
  });

  test('a dated merge makes the channel resident immediately', () async {
    service.applySuccessfulResponse(['a'], day('a'));
    await settle();
    final tomorrow = EpgProgram(
      channelId: 'a',
      title: 'tomorrow',
      description: '',
      start: base.add(const Duration(hours: 24)),
      end: base.add(const Duration(hours: 25)),
    );
    service.mergePrograms(
      [tomorrow],
      channelIds: ['a'],
      replaceExisting: false,
      markFresh: false,
    );
    // Visible straight away, before any store read.
    expect(
      service.programsForChannel(channel('a')).map((p) => p.title),
      contains('tomorrow'),
    );
    await settle();
    // Then completed from the store.
    expect(service.programsForChannel(channel('a')), hasLength(9));
  });

  test(
    'evicts the least recently used schedule and reloads it later',
    () async {
      final evicted = <String>[];
      service.onEvicted = evicted.add;
      for (final id in ['a', 'b', 'c']) {
        service.applySuccessfulResponse([id], day(id));
      }
      await settle();
      for (final id in ['a', 'b', 'c']) {
        service.programsForChannel(channel(id));
        await settle();
      }
      expect(evicted, ['a']);
      // Evicted, but now/next still answer from the hot slice.
      expect(service.lookup('a')!.current.title, 'a 12:00');
      // And the full schedule comes back from the store when asked for.
      service.programsForChannel(channel('a'));
      await settle();
      expect(service.programsForChannel(channel('a')), hasLength(8));
    },
  );

  test(
    'refills a non-resident hot slice from the store as it runs out',
    () async {
      service.applySuccessfulResponse(['a'], day('a'));
      await settle();
      // Two hours on, the hot slice (12:00-15:00) has one programme left.
      now = base.add(const Duration(hours: 2, minutes: 10));
      expect(service.lookup('a')!.current.title, 'a 14:00');
      await settle();
      final refilled = service.lookup('a')!;
      expect(refilled.current.title, 'a 14:00');
      expect(refilled.next!.title, 'a 15:00');
    },
  );

  test(
    'restoreFromStore fills hot slices without marking them fresh',
    () async {
      service.applySuccessfulResponse(['a'], day('a'));
      await settle();

      final restored = EpgService(clock: () => now, store: repo);
      await restored.restoreFromStore();
      expect(restored.lookup('a')!.current.title, 'a 12:00');
      expect(restored.programsForId('a'), hasLength(3));
      expect(restored.hasFreshDataForChannel(channel('a')), isFalse);
    },
  );

  test('clear drops queued writes for the old source', () async {
    service
      ..applySuccessfulResponse(['a'], day('a'))
      ..clear();
    await settle();
    expect(await repo.programmesForChannels({'a'}), isEmpty);
  });
}
