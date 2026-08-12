import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 11, 12);

  EpgService serviceAt(DateTime now) => EpgService(clock: () => now);

  Channel channel({
    bool catchupSupported = true,
    int? catchupDays,
    int? catchupRetentionHours,
    String name = 'Test Channel',
  }) => Channel(
    id: 1,
    name: name,
    streamUrl: 'https://streams.example/live/1.m3u8',
    catchupSupported: catchupSupported,
    catchupDays: catchupDays,
    catchupRetentionHours: catchupRetentionHours,
  );

  EpgProgram program(
    String channelId, {
    required DateTime start,
    required DateTime end,
    String title = 'Program',
  }) => EpgProgram(
    channelId: channelId,
    title: title,
    description: '',
    start: start,
    end: end,
  );

  group('EpgService.catchupProgramsForChannel', () {
    test('returns empty when catchup is not supported', () {
      final service = serviceAt(fixedNow);
      final ch = channel(catchupSupported: false, catchupDays: 7);
      service.loadPrograms([
        program(
          ch.name,
          start: fixedNow.subtract(const Duration(days: 1)),
          end: fixedNow.subtract(const Duration(hours: 1)),
        ),
      ]);

      expect(service.catchupProgramsForChannel(ch), isEmpty);
    });

    test('returns empty when no programs have ended yet', () {
      final service = serviceAt(fixedNow);
      final ch = channel(catchupDays: 7);
      service.loadPrograms([
        program(
          ch.name,
          start: fixedNow.subtract(const Duration(hours: 1)),
          end: fixedNow.add(const Duration(hours: 1)),
        ),
      ]);

      expect(service.catchupProgramsForChannel(ch), isEmpty);
    });

    test('excludes a program outside the retention window', () {
      final service = serviceAt(fixedNow);
      final ch = channel(catchupDays: 2);
      // Started 3 days ago, well before the 2-day retention window, and
      // already ended.
      service.loadPrograms([
        program(
          ch.name,
          start: fixedNow.subtract(const Duration(days: 3)),
          end: fixedNow.subtract(
            const Duration(days: 3) - const Duration(hours: 1),
          ),
        ),
      ]);

      expect(service.catchupProgramsForChannel(ch), isEmpty);
    });

    test('includes a program exactly at the retention boundary', () {
      final service = serviceAt(fixedNow);
      final ch = channel(catchupDays: 2);
      // earliest = now with day-of-month shifted back by retentionDays,
      // same time-of-day. A program starting exactly at `earliest` should
      // be included ("!isBefore" treats equal as satisfying the bound).
      final earliest = DateTime(
        fixedNow.year,
        fixedNow.month,
        fixedNow.day - 2,
        fixedNow.hour,
        fixedNow.minute,
        fixedNow.second,
        fixedNow.millisecond,
        fixedNow.microsecond,
      );
      service.loadPrograms([
        program(
          ch.name,
          start: earliest,
          end: earliest.add(const Duration(hours: 1)),
        ),
      ]);

      final results = service.catchupProgramsForChannel(ch);
      expect(results, hasLength(1));
      expect(results.single.start, earliest);
    });

    test('uses precise hour retention when it is available', () {
      final service = serviceAt(fixedNow);
      final ch = channel(catchupDays: 7, catchupRetentionHours: 4);
      final expired = program(
        ch.name,
        title: 'Expired',
        start: fixedNow.subtract(const Duration(hours: 5)),
        end: fixedNow.subtract(const Duration(hours: 4)),
      );
      final available = program(
        ch.name,
        title: 'Available',
        start: fixedNow.subtract(const Duration(hours: 3)),
        end: fixedNow.subtract(const Duration(hours: 2)),
      );
      service.loadPrograms([expired, available]);

      expect(
        service.catchupProgramsForChannel(ch).map((p) => p.title),
        ['Available'],
      );
    });

    test(
      'returns multiple qualifying programs most-recent-first',
      () {
        final service = serviceAt(fixedNow);
        final ch = channel(catchupDays: 7);
        final older = program(
          ch.name,
          title: 'Older',
          start: fixedNow.subtract(const Duration(days: 3)),
          end: fixedNow.subtract(const Duration(days: 3, hours: -1)),
        );
        final newer = program(
          ch.name,
          title: 'Newer',
          start: fixedNow.subtract(const Duration(days: 1)),
          end: fixedNow.subtract(const Duration(days: 1, hours: -1)),
        );
        // Load out of order to prove sorting/reversal, not insertion order.
        service.loadPrograms([older, newer]);

        final results = service.catchupProgramsForChannel(ch);
        expect(results.map((p) => p.title).toList(), ['Newer', 'Older']);
      },
    );

    test('falls back to kCatchupFallbackDays when catchupDays is null', () {
      expect(
        EpgService.effectiveCatchupRetentionDays(true, null),
        EpgService.kCatchupFallbackDays,
      );
      expect(EpgService.kCatchupFallbackDays, 7);

      final service = serviceAt(fixedNow);
      final ch = channel();
      // 5 days ago sits inside the 7-day fallback window.
      service.loadPrograms([
        program(
          ch.name,
          start: fixedNow.subtract(const Duration(days: 5)),
          end: fixedNow.subtract(const Duration(days: 5, hours: -1)),
        ),
      ]);

      expect(service.catchupProgramsForChannel(ch), hasLength(1));
    });
  });

  test('failed EPG fetches retry after a bounded backoff', () {
    var now = DateTime.utc(2026, 7, 30, 12);
    final service = EpgService(clock: () => now);
    const channel = Channel(
      id: 101,
      name: 'BBC One',
      streamUrl: 'https://fixture.example/live/101',
      epgChannelId: 'bbc.one',
    );

    expect(EpgService.retryBackoff, lessThan(const Duration(minutes: 30)));
    expect(service.shouldFetchDataForChannel(channel), isTrue);

    service.markFetchStarted(const <String>['bbc.one']);
    expect(service.shouldFetchDataForChannel(channel), isFalse);

    service.markFetchFailed(const <String>['bbc.one']);
    expect(service.hasFreshDataForChannel(channel), isFalse);
    expect(service.shouldFetchDataForChannel(channel), isFalse);

    now = now.add(
      EpgService.retryBackoff - const Duration(microseconds: 1),
    );
    expect(service.shouldFetchDataForChannel(channel), isFalse);

    now = now.add(const Duration(microseconds: 1));
    expect(service.shouldFetchDataForChannel(channel), isTrue);

    service
      ..markFetchStarted(const <String>['bbc.one'])
      ..markFetchFailed(const <String>['bbc.one']);
    now = now.add(
      EpgService.retryBackoff - const Duration(microseconds: 1),
    );
    expect(service.shouldFetchDataForChannel(channel), isFalse);

    now = now.add(const Duration(microseconds: 1));
    expect(service.shouldFetchDataForChannel(channel), isTrue);
  });

  test('retained EPG failures retry after a backward clock adjustment', () {
    var now = DateTime.utc(2026, 7, 30, 12);
    final fetchedAt = now;
    const channel = Channel(
      id: 101,
      name: 'BBC One',
      streamUrl: 'https://fixture.example/live/101',
      epgChannelId: 'bbc.one',
    );
    final retainedProgram = EpgProgram(
      channelId: 'bbc.one',
      title: 'Retained guide',
      description: '',
      start: now.subtract(const Duration(hours: 2)),
      end: now.add(const Duration(hours: 2)),
    );
    final service = EpgService(clock: () => now)
      ..applySuccessfulResponse(
        const <String>['bbc.one'],
        <EpgProgram>[retainedProgram],
      );

    now = fetchedAt.add(service.cacheTtl);
    service
      ..markFetchStarted(const <String>['bbc.one'])
      ..markFetchFailed(const <String>['bbc.one']);
    expect(service.shouldFetchData('bbc.one'), isFalse);

    now = now.add(
      EpgService.retryBackoff - const Duration(microseconds: 1),
    );
    expect(service.shouldFetchData('bbc.one'), isFalse);

    now = now.add(const Duration(microseconds: 1));
    expect(service.shouldFetchData('bbc.one'), isTrue);

    service
      ..markFetchStarted(const <String>['bbc.one'])
      ..markFetchFailed(const <String>['bbc.one']);

    now = fetchedAt.subtract(const Duration(minutes: 1));

    expect(service.shouldFetchData('bbc.one'), isTrue);
    expect(service.lookup('bbc.one')?.current, same(retainedProgram));
    expect(service.programsForChannel(channel), <EpgProgram>[retainedProgram]);
  });
}
