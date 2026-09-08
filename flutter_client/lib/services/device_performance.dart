import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Override for the auto-detected performance tier. `auto` defers to hardware
/// detection; `full` / `reduced` force it. Passed to [DevicePerformance
/// .ensureDetected]; there is no user-facing setting wired to it yet, so
/// production always passes `auto`. Tests use it to exercise both tiers.
enum PerformanceTierSetting { auto, full, reduced }

/// Detects whether the current device is too weak for the full memory /
/// visual-effects budget and exposes a single sync gate ([isReduced]) that
/// chokepoints (image-cache ceilings, decode concurrency, the RSS watchdog
/// threshold) consult.
///
/// The reduced tier auto-triggers only on low-end Android hardware: a 32-bit
/// process (cheap TV boxes and sticks run 32-bit userspace), the platform
/// low-RAM flag, or <= ~2.2 GiB total memory. Every other platform is full
/// tier unless [ensureDetected] is passed an explicit `reduced` override.
///
/// Call [ensureDetected] once during app start (before the image cache is
/// configured). The sync getters are safe before that completes - they report
/// the full tier until detection lands.
class DevicePerformance {
  DevicePerformance._();

  static const MethodChannel _channel = MethodChannel('m3u_tv/device_info');

  /// ~2.2 GiB: above what 2 GB boxes report (<= ~1.95 GiB after kernel
  /// reservations), below 3 GB Shield-class devices (~2.8 GiB).
  static const int _lowMemThresholdBytes = 2252 << 20;

  static bool _detected = false;
  static bool _autoReduced = false;
  static PerformanceTierSetting _override = PerformanceTierSetting.auto;

  static bool? _is64Bit;
  static bool? _isLowRam;
  static int? _totalMemBytes;

  /// Detect the hardware signals. Idempotent; a second call is a no-op unless
  /// [force] is set (used by tests). Pass [override] again on every call - it
  /// is applied even when detection is skipped, so a later preference change
  /// takes effect without re-hitting the platform channel.
  static Future<void> ensureDetected({
    PerformanceTierSetting override = PerformanceTierSetting.auto,
    bool force = false,
  }) async {
    _override = override;
    if (_detected && !force) return;
    _detected = true;
    if (!_isAndroid) return; // tvOS / iOS / desktop: always full tier.
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'getPerformanceSignals',
      );
      if (result == null) return;
      _is64Bit = result['is64Bit'] == true;
      _isLowRam = result['isLowRamDevice'] == true;
      _totalMemBytes = (result['totalMemBytes'] as num?)?.toInt();
      _autoReduced =
          _is64Bit == false ||
          _isLowRam == true ||
          (_totalMemBytes != null && _totalMemBytes! <= _lowMemThresholdBytes);
    } on MissingPluginException {
      // Stale native build - stay on the full tier.
    } on PlatformException {
      // Signal query failed - stay on the full tier.
    }
  }

  static bool get _isAndroid =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      Platform.isAndroid;

  /// Total device RAM as reported by the platform, or null off-Android /
  /// before [ensureDetected]. Used to scale the RSS-watchdog threshold.
  static int? get totalMemBytes => _totalMemBytes;

  /// Auto-detected low-end hardware (32-bit process / low-RAM flag /
  /// <= 2.2 GiB), independent of the user override. Use for decisions tied to
  /// the hardware itself. Safe before detection (returns false).
  static bool get isLowEndHardware => _autoReduced;

  /// Primary gate for memory / effect chokepoints. Safe before detection
  /// (full tier).
  static bool get isReduced => switch (_override) {
    PerformanceTierSetting.auto => _autoReduced,
    PerformanceTierSetting.full => false,
    PerformanceTierSetting.reduced => true,
  };

  /// One-line summary for the startup log.
  static String describe() =>
      'DevicePerformance(reduced: $isReduced, auto: $_autoReduced, '
      '64bit: $_is64Bit, lowRam: $_isLowRam, '
      'totalMem: ${_totalMemBytes == null ? "?" : "${_totalMemBytes! >> 20}MB"})';

  @visibleForTesting
  static void debugSet({
    bool? autoReduced,
    int? totalMemBytes,
    PerformanceTierSetting override = PerformanceTierSetting.auto,
    bool detected = true,
  }) {
    _detected = detected;
    if (autoReduced != null) _autoReduced = autoReduced;
    _totalMemBytes = totalMemBytes;
    _override = override;
  }

  @visibleForTesting
  static void debugReset() {
    _detected = false;
    _autoReduced = false;
    _override = PerformanceTierSetting.auto;
    _is64Bit = null;
    _isLowRam = null;
    _totalMemBytes = null;
  }
}
