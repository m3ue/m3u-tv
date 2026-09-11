import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';

Progress _p(
  int streamId, {
  ContentType type = ContentType.episode,
  int position = 120,
  String? aioItemId,
}) => Progress(
  viewerId: 'v1',
  contentType: type,
  streamId: streamId,
  positionSeconds: position,
  durationSeconds: 1500,
  aioItemId: aioItemId,
);

void main() {
  test('updateProgressEntry moves the touched item to the front', () {
    final controller = AppStateController();
    addTearDown(controller.dispose);

    controller
      ..updateProgressEntry(_p(1))
      ..updateProgressEntry(_p(2))
      ..updateProgressEntry(_p(3));
    expect(controller.progressList.map((p) => p.streamId), [3, 2, 1]);

    // Resuming an item already in the list (here #1, at the back) must promote
    // it to the front, not update it in place.
    controller.updateProgressEntry(_p(1, position: 300));
    expect(controller.progressList.map((p) => p.streamId), [1, 3, 2]);
    expect(controller.progressList.first.positionSeconds, 300);
    expect(controller.progressList.length, 3); // no duplicate row for #1
  });

  test('updateProgressEntry matches AIO items by aioItemId, not streamId', () {
    final controller = AppStateController();
    addTearDown(controller.dispose);

    controller
      ..updateProgressEntry(
        _p(0, type: ContentType.aiostreams, aioItemId: 'tt111'),
      )
      ..updateProgressEntry(
        _p(0, type: ContentType.aiostreams, aioItemId: 'tt222'),
      );
    expect(controller.progressList.length, 2);

    controller.updateProgressEntry(
      _p(0, type: ContentType.aiostreams, aioItemId: 'tt111', position: 999),
    );
    expect(
      controller.progressList.map((p) => p.aioItemId),
      ['tt111', 'tt222'],
    );
    expect(controller.progressList.length, 2);
  });
}
