import 'package:wakelock_plus/wakelock_plus.dart';

/// Thin abstraction over the wakelock_plus platform channel so widget code
/// can be unit-tested without touching the real platform side.
///
/// Production code uses `PlatformWakelockController`; tests inject a fake
/// implementation that records calls.
abstract class WakelockController {
  Future<void> enable();
  Future<void> disable();
}

/// Counts holders and only reaches [inner] when the first one arrives or the
/// last one leaves.
///
/// The platform wakelock is a single on/off switch, but more than one screen
/// can be playing at once: the full-screen player opens over the Multiview
/// grid, and closing it must not let the Apple TV screensaver or sleep timer
/// kick in while the grid is still playing underneath.
class RefCountedWakelock implements WakelockController {
  RefCountedWakelock(this.inner);

  final WakelockController inner;
  int _holders = 0;

  @override
  Future<void> enable() async {
    if (_holders++ == 0) await inner.enable();
  }

  @override
  Future<void> disable() async {
    if (_holders == 0) return;
    if (--_holders == 0) await inner.disable();
  }
}

class _WakelockPlusPlatform implements WakelockController {
  const _WakelockPlusPlatform();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

class PlatformWakelockController implements WakelockController {
  const PlatformWakelockController();

  // Shared by every instance, so independent screens count against the same
  // platform switch.
  static final RefCountedWakelock _shared = RefCountedWakelock(
    const _WakelockPlusPlatform(),
  );

  @override
  Future<void> enable() => _shared.enable();

  @override
  Future<void> disable() => _shared.disable();
}
