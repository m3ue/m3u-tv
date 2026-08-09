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

class PlatformWakelockController implements WakelockController {
  const PlatformWakelockController();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}
