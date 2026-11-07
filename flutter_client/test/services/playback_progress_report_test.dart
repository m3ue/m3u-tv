import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://editor.example',
  username: 'user',
  password: 'secret',
);

Progress _progress(int position) => Progress(
  viewerId: 'viewer',
  contentType: ContentType.vod,
  streamId: 7,
  positionSeconds: position,
);

class _HeldProgressTransport {
  final pending = <Completer<Object?>>[];
  final positions = <Object?>[];

  Future<Object?> call(XtreamRequest request) {
    if (request.action == 'update_progress') {
      positions.add(request.body['position_seconds']);
      final reply = Completer<Object?>();
      pending.add(reply);
      return reply.future;
    }
    return Future.value(<String, Object?>{
      'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
      'server_info': <String, Object?>{'timezone': 'UTC'},
      'm3u_editor': <String, Object?>{'version': '0.13.0'},
    });
  }
}

void main() {
  late _HeldProgressTransport transport;
  late XtreamService service;

  setUp(() async {
    transport = _HeldProgressTransport();
    service = XtreamService(transport: transport.call);
    await service.authenticate(_credentials);
  });

  test(
    'queues only the latest report while the previous one is pending',
    () async {
      final first = service.reportPlaybackProgress(_progress(10));
      expect(await service.reportPlaybackProgress(_progress(20)), isFalse);
      expect(await service.reportPlaybackProgress(_progress(25)), isFalse);
      expect(transport.positions, ['10']);

      transport.pending.single.complete(null);
      await pumpEventQueue();
      expect(transport.positions, ['10', '25']);

      final settled = service.playbackProgressSettled();
      transport.pending.last.complete(null);
      expect(await first, isTrue);
      await settled;

      final next = service.reportPlaybackProgress(_progress(30));
      expect(transport.positions, ['10', '25', '30']);
      transport.pending.last.complete(null);
      expect(await next, isTrue);
    },
  );

  test('a failed report still sends the queued one', () async {
    final failed = service.reportPlaybackProgress(_progress(10));
    unawaited(service.reportPlaybackProgress(_progress(20)));
    transport.pending.single.completeError(StateError('editor down'));
    await pumpEventQueue();
    expect(transport.positions, ['10', '20']);
    transport.pending.last.complete(null);
    await expectLater(failed, throwsStateError);
  });

  test('reports again after a failed playback report', () async {
    final failed = service.reportPlaybackProgress(_progress(10));
    transport.pending.single.completeError(StateError('editor down'));
    await expectLater(failed, throwsStateError);

    final next = service.reportPlaybackProgress(_progress(20));
    expect(transport.positions, ['10', '20']);
    transport.pending.last.complete(null);
    expect(await next, isTrue);
  });

  test('explicit updateProgress is never skipped', () async {
    unawaited(service.reportPlaybackProgress(_progress(10)));
    unawaited(service.updateProgress(_progress(0)));
    expect(transport.positions, ['10', '0']);
    for (final reply in transport.pending) {
      reply.complete(null);
    }
  });
}
