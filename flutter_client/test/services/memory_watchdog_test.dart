// ignore_for_file: cascade_invocations

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/memory_watchdog.dart';

/// Minimal [ImageCache] stand-in: the watchdog only touches [currentSizeBytes],
/// [currentSize], [clear] and [clearLiveImages].
class _FakeImageCache implements ImageCache {
  _FakeImageCache({this.sizeBytes = 64 << 20});

  int sizeBytes;
  int clears = 0;
  int liveClears = 0;

  @override
  int get currentSizeBytes => sizeBytes;

  @override
  int get currentSize => 100;

  @override
  void clear() {
    clears += 1;
    sizeBytes = 0;
  }

  @override
  void clearLiveImages() => liveClears += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('evicts when RSS is over threshold and cache is above the floor', () {
    final cache = _FakeImageCache();
    var now = DateTime(2026);
    final watchdog = MemoryWatchdog(
      imageCache: cache,
      currentRss: () => 900 << 20,
      clock: () => now,
    );

    watchdog.sampleForTest(800 << 20);

    expect(cache.clears, 1);
    expect(cache.liveClears, 1);

    cache.sizeBytes = 64 << 20;
    now = now.add(const Duration(seconds: 61));
    watchdog.sampleForTest(800 << 20);
    expect(cache.clears, 2);
  });

  test('does not evict below threshold', () {
    final cache = _FakeImageCache();
    final watchdog = MemoryWatchdog(
      imageCache: cache,
      currentRss: () => 100 << 20,
      clock: () => DateTime(2026),
    );

    watchdog.sampleForTest(800 << 20);

    expect(cache.clears, 0);
  });

  test('does not evict an already-small cache', () {
    final cache = _FakeImageCache(sizeBytes: 4 << 20);
    final watchdog = MemoryWatchdog(
      imageCache: cache,
      currentRss: () => 900 << 20,
      clock: () => DateTime(2026),
    );

    watchdog.sampleForTest(800 << 20);

    expect(cache.clears, 0);
  });

  test('holds off inside the cooldown unless RSS keeps climbing', () {
    final cache = _FakeImageCache();
    var now = DateTime(2026);
    var rss = 900 << 20;
    final watchdog = MemoryWatchdog(
      imageCache: cache,
      currentRss: () => rss,
      clock: () => now,
    );

    watchdog.sampleForTest(800 << 20);
    expect(cache.clears, 1);

    cache.sizeBytes = 64 << 20;
    now = now.add(const Duration(seconds: 10));
    rss = 850 << 20;
    watchdog.sampleForTest(800 << 20);
    expect(cache.clears, 1);

    rss = 950 << 20;
    watchdog.sampleForTest(800 << 20);
    expect(cache.clears, 2);
  });

  test('notifyMemoryPressure always evicts', () {
    final cache = _FakeImageCache(sizeBytes: 1 << 20);
    final watchdog = MemoryWatchdog(
      imageCache: cache,
      currentRss: () => 0,
      clock: () => DateTime(2026),
    );

    watchdog.notifyMemoryPressure();

    expect(cache.clears, 1);
    expect(cache.liveClears, 1);
  });
}
