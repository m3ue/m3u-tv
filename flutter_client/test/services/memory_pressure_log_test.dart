// ignore_for_file: cascade_invocations

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/memory_pressure_log.dart';

/// Minimal [ImageCache] stand-in: the log only reads [currentSizeBytes],
/// [currentSize] and [liveImageCount]; [clear] stands in for the framework's
/// own memory-pressure handling.
class _FakeImageCache implements ImageCache {
  int sizeBytes = 96 << 20;
  int size = 240;

  @override
  int get currentSizeBytes => sizeBytes;

  @override
  int get currentSize => size;

  @override
  int get liveImageCount => 12;

  @override
  void clear() {
    sizeBytes = 0;
    size = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeImageCache cache;
  late DateTime now;
  late List<String> lines;
  late int dispatches;

  MemoryPressureLog build({int Function()? currentRss}) => MemoryPressureLog(
    clock: () => now,
    currentRss: currentRss ?? () => 700 << 20,
    maxRss: () => 900 << 20,
    log: lines.add,
  );

  void dispatch() {
    dispatches++;
    cache.clear();
  }

  setUp(() {
    cache = _FakeImageCache();
    now = DateTime(2026, 10, 21);
    lines = [];
    dispatches = 0;
  });

  test('logs RSS and the image cache before and after the dispatch', () {
    build().handle(cache, dispatch);

    expect(dispatches, 1);
    expect(
      lines.single,
      '[MemoryPressure] rss=700MB maxRss=900MB cache=240img/96MB live=12 '
      'cacheAfter=0img/0MB liveAfter=12',
    );
  });

  test('folds signals inside the interval into the next line', () {
    final log = build();
    log.handle(cache, dispatch);
    now = now.add(const Duration(seconds: 1));
    log.handle(cache, dispatch);
    log.handle(cache, dispatch);

    expect(dispatches, 3);
    expect(lines, hasLength(1));

    now = now.add(MemoryPressureLog.interval);
    log.handle(cache, dispatch);

    expect(dispatches, 4);
    expect(lines, hasLength(2));
    expect(lines.last, endsWith('suppressed=2'));
  });

  test('a clock set backwards does not silence the log', () {
    final log = build();
    log.handle(cache, dispatch);
    now = now.subtract(const Duration(minutes: 5));
    log.handle(cache, dispatch);

    expect(lines, hasLength(2));
  });

  test('a failed RSS read drops its field, not the dispatch', () {
    build(currentRss: () => throw StateError('nope')).handle(
      cache,
      dispatch,
    );

    expect(dispatches, 1);
    expect(lines.single, startsWith('[MemoryPressure] maxRss=900MB '));
  });
}
