import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/sync_offset_store.dart';

PersistentJsonStore _tempStore() {
  final dir = Directory.systemTemp.createTempSync('sync_offsets_test');
  addTearDown(() => dir.deleteSync(recursive: true));
  return PersistentJsonStore(file: File('${dir.path}/state.json'));
}

void main() {
  group('syncOffsetKeyFor', () {
    test('live and catch-up share the channel; episodes share the series', () {
      expect(syncOffsetKeyFor(type: 'live', streamId: 7), 'live:7');
      expect(syncOffsetKeyFor(type: 'catchup', streamId: 7), 'live:7');
      expect(syncOffsetKeyFor(type: 'vod', streamId: 9), 'vod:9');
      expect(
        syncOffsetKeyFor(type: 'series', streamId: 101, seriesId: 3),
        'series:3',
      );
      expect(syncOffsetKeyFor(type: 'series', streamId: 101), 'episode:101');
      expect(syncOffsetKeyFor(type: 'live'), isNull);
      expect(syncOffsetKeyFor(type: 'dvr', streamId: 1), isNull);
    });
  });

  group('SyncOffsetStore', () {
    test('round-trips offsets and forgets ones back at zero', () async {
      final store = SyncOffsetStore(store: _tempStore());

      await store.write('live:7', (
        audio: const Duration(milliseconds: 120),
        subtitle: const Duration(milliseconds: -1500),
      ));
      final read = await store.read('live:7');
      expect(read.audio, const Duration(milliseconds: 120));
      expect(read.subtitle, const Duration(milliseconds: -1500));

      await store.write('live:7', zeroSyncOffsets);
      expect(await store.read('live:7'), zeroSyncOffsets);
    });

    test('keeps each playlist apart', () async {
      var scope = 'a';
      final store = SyncOffsetStore(store: _tempStore())
        ..playlistScope = () => scope;

      await store.write('live:7', (
        audio: const Duration(milliseconds: 80),
        subtitle: Duration.zero,
      ));
      scope = 'b';

      expect(await store.read('live:7'), zeroSyncOffsets);
    });

    test('drops the oldest entries past the cap', () async {
      final store = SyncOffsetStore(store: _tempStore());
      const offsets = (
        audio: Duration(milliseconds: 10),
        subtitle: Duration.zero,
      );

      for (var i = 0; i <= SyncOffsetStore.maxEntries; i++) {
        await store.write('vod:$i', offsets);
      }

      expect(await store.read('vod:0'), zeroSyncOffsets);
      expect(await store.read('vod:${SyncOffsetStore.maxEntries}'), offsets);
    });
  });
}
