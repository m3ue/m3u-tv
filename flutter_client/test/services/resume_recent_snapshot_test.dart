import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';

Progress _episode(String viewerId, int streamId, {bool upNext = false}) =>
    Progress(
      viewerId: viewerId,
      contentType: ContentType.episode,
      streamId: streamId,
      positionSeconds: upNext ? 0 : 600,
      seriesId: 7,
      upNext: upNext,
    );

void main() {
  for (final fileBacked in [false, true]) {
    group(fileBacked ? 'file-backed store' : 'in-memory store', () {
      late ResumeService service;

      setUp(() {
        PersistentJsonStore? store;
        if (fileBacked) {
          final dir = Directory.systemTemp.createTempSync('resume_recent_');
          addTearDown(() => dir.deleteSync(recursive: true));
          store = PersistentJsonStore(file: File('${dir.path}/state.json'));
        }
        service = ResumeService(store: store);
      });

      test('recent is null until a list has been stored', () async {
        await service.save(_episode('a', 1));
        expect(await service.recent('a'), isNull);
      });

      test(
        'recent returns the stored list in order, up-next included',
        () async {
          await service.saveRecent('a', [
            _episode('a', 3),
            _episode('a', 9, upNext: true),
            _episode('a', 1),
          ]);

          final recent = await service.recent('a');
          expect(recent!.map((p) => p.streamId), [3, 9, 1]);
          expect(recent[1].upNext, isTrue);
        },
      );

      test('recent overlays newer saved positions onto the list', () async {
        await service.saveRecent('a', [_episode('a', 3), _episode('a', 1)]);
        await service.save(
          const Progress(
            viewerId: 'a',
            contentType: ContentType.episode,
            streamId: 1,
            positionSeconds: 900,
            seriesId: 7,
          ),
        );

        final recent = await service.recent('a');
        expect(recent!.map((p) => p.streamId), [3, 1]);
        expect(recent.map((p) => p.positionSeconds), [600, 900]);
      });

      test(
        "prune drops this viewer's resume entries missing from the list",
        () async {
          // Same episode stored under the stream ids of two earlier library
          // flushes, plus the current one.
          await service.save(_episode('a', 213275));
          await service.save(_episode('a', 215134));
          await service.save(_episode('a', 216957));
          await service.save(_episode('b', 213275));

          await service.saveRecent('a', [
            _episode('a', 216957),
            _episode('a', 300, upNext: true),
          ], prune: true);

          expect((await service.all('a')).map((p) => p.streamId), [216957]);
          // Other viewers are untouched.
          expect((await service.all('b')).map((p) => p.streamId), [213275]);
        },
      );

      test('without prune, existing resume entries are kept', () async {
        await service.save(_episode('a', 1));
        await service.save(_episode('a', 2));

        await service.saveRecent('a', [_episode('a', 2)]);

        expect(
          (await service.all('a')).map((p) => p.streamId).toSet(),
          {1, 2},
        );
      });

      test('remove drops a single resume entry', () async {
        await service.save(_episode('a', 1));
        await service.save(_episode('a', 2));

        await service.remove(_episode('a', 1));

        expect((await service.all('a')).map((p) => p.streamId), [2]);
      });

      test('a rejected commit stores nothing', () async {
        await service.save(_episode('a', 1));

        final saved = await service.saveRecent(
          'a',
          [_episode('a', 2)],
          prune: true,
          shouldCommit: () => false,
        );

        expect(saved, isFalse);
        expect(await service.recent('a'), isNull);
        expect((await service.all('a')).map((p) => p.streamId), [1]);
      });
    });
  }
}
