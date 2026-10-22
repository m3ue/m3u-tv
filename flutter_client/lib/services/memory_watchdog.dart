import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:m3u_tv/services/device_performance.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// RSS-based image-cache eviction backstop.
///
/// The decoded-bitmap [ImageCache] ceiling raised in `main._configureImageCache`
/// keeps recently browsed art resident, but on a 1-2 GB Android TV box the
/// system low-memory killer sits well below that ceiling and can kill the
/// process without ever delivering a trim callback. This watchdog samples the
/// process RSS on a timer and clears the image caches when it climbs past a
/// device-scaled threshold.
///
/// The platform memory-pressure signal needs nothing from it: Flutter's own
/// `PaintingBinding.handleMemoryPressure` empties the image cache before any
/// observer runs, and `MemoryPressureLog` records what was held. The RSS poll
/// runs on desktop and Android, where `ProcessInfo.currentRss` is meaningful
/// and trim callbacks are unreliable; iOS / tvOS rely on the signal alone.
class MemoryWatchdog {
  MemoryWatchdog({
    ImageCache? imageCache,
    int Function()? currentRss,
    DateTime Function()? clock,
  }) : _imageCacheOverride = imageCache,
       _currentRss = currentRss ?? (() => ProcessInfo.currentRss),
       _clock = clock ?? DateTime.now;

  final ImageCache? _imageCacheOverride;
  final int Function() _currentRss;
  final DateTime Function() _clock;

  static const Duration _cooldown = Duration(seconds: 60);
  static const int _cacheFloorBytes = 8 << 20;

  Timer? _timer;
  Timer? _diagnosticsTimer;

  /// Opt-in image-cache logging for memory investigations, enabled with
  /// `--dart-define=MEM_DIAG=true`. Lands in logcat / the Xcode console and
  /// in the Logs & Diagnostics screen.
  static const bool _diagnosticsEnabled = bool.fromEnvironment('MEM_DIAG');
  DateTime _lastEviction = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastEvictionRss = 0;

  ImageCache get _imageCache =>
      _imageCacheOverride ?? PaintingBinding.instance.imageCache;

  /// Begin periodic RSS sampling. No-op on iOS / tvOS and under `flutter test`.
  void start() {
    if (_timer != null) return;
    if (HostPlatform.environment['FLUTTER_TEST'] == 'true') return;
    if (_diagnosticsEnabled) {
      _diagnosticsTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _logDiagnostics(),
      );
    }
    final (threshold, period) = _thresholdAndPeriod();
    if (threshold == null || period == null) return;
    _timer = Timer.periodic(period, (_) => _sample(threshold));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _diagnosticsTimer?.cancel();
    _diagnosticsTimer = null;
  }

  void _logDiagnostics() {
    final cache = _imageCache;
    debugPrint(
      '[MemDiag] rss=${_currentRss() >> 20}MB '
      'cache=${cache.currentSize}img/${cache.currentSizeBytes >> 20}MB '
      'max=${cache.maximumSize}img/${cache.maximumSizeBytes >> 20}MB '
      'live=${cache.liveImageCount} pending=${cache.pendingImageCount}',
    );
  }

  /// Exposed for tests: run one sample against [thresholdBytes].
  @visibleForTesting
  void sampleForTest(int thresholdBytes) => _sample(thresholdBytes);

  (int?, Duration?) _thresholdAndPeriod() {
    if (_isDesktop) {
      return (1536 << 20, const Duration(seconds: 30));
    }
    if (HostPlatform.isAndroid) {
      final totalMem = DevicePerformance.totalMemBytes;
      final threshold = totalMem != null
          ? (totalMem * 0.45).round().clamp(512 << 20, 1536 << 20)
          : 1 << 30;
      final period = DevicePerformance.isLowEndHardware
          ? const Duration(seconds: 15)
          : const Duration(seconds: 30);
      return (threshold, period);
    }
    return (null, null); // iOS / tvOS: pressure signal only.
  }

  void _sample(int thresholdBytes) {
    final rss = _currentRss();
    if (rss <= thresholdBytes) return;
    // Clearing an already-small cache buys nothing and its refetch churn is
    // its own jank source. Inside the cooldown, re-evict only if RSS kept
    // climbing past the last eviction.
    if (_imageCache.currentSizeBytes < _cacheFloorBytes) return;
    final now = _clock();
    final inCooldown = now.difference(_lastEviction) < _cooldown;
    if (inCooldown && rss <= _lastEvictionRss) return;
    _lastEviction = now;
    _lastEvictionRss = rss;
    debugPrint(
      '[MemoryWatchdog] RSS ${rss >> 20}MB > ${thresholdBytes >> 20}MB, '
      'evicting image caches (${_imageCache.currentSizeBytes >> 20}MB / '
      '${_imageCache.currentSize} images)',
    );
    _evict();
  }

  void _evict() {
    _imageCache
      ..clear()
      ..clearLiveImages();
  }

  static bool get _isDesktop => HostPlatform.isDesktop;
}
