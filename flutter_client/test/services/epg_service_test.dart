import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
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

    now = now.add(EpgService.retryBackoff);
    expect(service.shouldFetchDataForChannel(channel), isTrue);
  });
}
