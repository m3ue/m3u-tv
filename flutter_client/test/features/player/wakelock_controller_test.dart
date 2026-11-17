import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';

class _RecordingWakelock implements WakelockController {
  final List<String> calls = <String>[];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');
}

void main() {
  group('RefCountedWakelock', () {
    late _RecordingWakelock platform;
    late RefCountedWakelock wakelock;

    setUp(() {
      platform = _RecordingWakelock();
      wakelock = RefCountedWakelock(platform);
    });

    test('only the first holder turns the platform wakelock on', () async {
      await wakelock.enable();
      await wakelock.enable();

      expect(platform.calls, ['enable']);
    });

    test('stays on until the last holder releases it', () async {
      await wakelock.enable();
      await wakelock.enable();

      await wakelock.disable();
      expect(platform.calls, ['enable']);

      await wakelock.disable();
      expect(platform.calls, ['enable', 'disable']);
    });

    test('full-screen player closing over Multiview keeps it on', () async {
      await wakelock.enable(); // Multiview grid opens
      await wakelock.enable(); // full-screen player opens over it
      await wakelock.disable(); // full-screen player closes

      expect(platform.calls, ['enable']);
    });

    test('an unbalanced release does not corrupt the count', () async {
      await wakelock.disable();
      expect(platform.calls, isEmpty);

      await wakelock.enable();
      expect(platform.calls, ['enable']);

      await wakelock.disable();
      expect(platform.calls, ['enable', 'disable']);
    });

    test('can be re-acquired after being fully released', () async {
      await wakelock.enable();
      await wakelock.disable();
      await wakelock.enable();

      expect(platform.calls, ['enable', 'disable', 'enable']);
    });
  });
}
