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
/// The platform wakelock is a single on/off switch, but holders overlap:
/// "Full screen" from Multiview pops the grid and opens the player in the
/// same frame, and the grid's route is only disposed after its exit
/// transition, by which point the player has already taken the wakelock.
/// Without counting, the grid's release would let the screensaver and sleep
/// timer run over the player.
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
