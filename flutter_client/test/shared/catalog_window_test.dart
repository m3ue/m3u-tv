// ignore_for_file: avoid_redundant_argument_values, only_throw_errors
// ignore_for_file: library_private_types_in_public_api

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/catalog_window.dart';

/// An in-memory ordered list the window pages over, with a hit counter and an
/// optional forced error.
class _FakeSource {
  _FakeSource(int size) : items = List<int>.generate(size, (i) => i * 10);

  final List<int> items;
  int pageFetches = 0;
  Object? failWith;

  Future<List<int>> page(int offset, int limit) async {
    pageFetches++;
    if (failWith != null) throw failWith!;
    final end = (offset + limit).clamp(0, items.length);
    if (offset >= items.length) return const [];
    return items.sublist(offset, end);
  }

  Future<int> count() async {
    if (failWith != null) throw failWith!;
    return items.length;
  }
}

CatalogWindow<int> windowFor(
  _FakeSource source, {
  int pageSize = 10,
  int keepWindow = 20,
  int evictThreshold = 30,
}) => CatalogWindow<int>(
  fetchPage: source.page,
  fetchCount: source.count,
  pageSize: pageSize,
  keepWindow: keepWindow,
  evictThreshold: evictThreshold,
);

void main() {
  test('load fetches the count and the first page', () async {
    final source = _FakeSource(125);
    final window = windowFor(source);

    await window.load();

    expect(window.totalCount, 125);
    expect(window.itemAt(0), 0);
    expect(window.itemAt(9), 90);
    expect(window.itemAt(10), isNull); // second page not fetched yet
    expect(source.pageFetches, 1);
  });

  test(
    'ensureVisible pulls the pages covering the range plus buffer',
    () async {
      final source = _FakeSource(500);
      final window = windowFor(source, pageSize: 10);
      await window.load();

      window.ensureVisible(100, 20, buffer: 10);
      await Future<void>.delayed(Duration.zero);

      // Range [90, 130) -> pages 9..12.
      expect(window.itemAt(95), 950);
      expect(window.itemAt(129), 1290);
      expect(window.itemAt(140), isNull);
    },
  );

  test('a resident page is not re-fetched', () async {
    final source = _FakeSource(100);
    final window = windowFor(source, pageSize: 10);
    await window.load();
    final afterLoad = source.pageFetches;

    window
      ..ensureVisible(0, 5, buffer: 0)
      ..ensureVisible(0, 5, buffer: 0);
    await Future<void>.delayed(Duration.zero);

    expect(source.pageFetches, afterLoad);
  });

  test(
    'configure swaps the slice and discards stale in-flight pages',
    () async {
      final source = _FakeSource(300);
      final window = windowFor(source, pageSize: 10);
      await window.load();

      final smaller = _FakeSource(15);
      await window.configure(
        fetchPage: smaller.page,
        fetchCount: smaller.count,
      );

      expect(window.totalCount, 15);
      expect(window.itemAt(0), 0);
      // Old rows are gone.
      expect(window.itemAt(250), isNull);
    },
  );

  test(
    'evictAround trims rows outside the keep window past the threshold',
    () async {
      final source = _FakeSource(1000);
      final window = windowFor(
        source,
        pageSize: 10,
        keepWindow: 20,
        evictThreshold: 30,
      );
      await window.load();

      // Load pages 0..9 -> 100 resident rows.
      window.ensureVisible(0, 100, buffer: 0);
      await Future<void>.delayed(Duration.zero);
      expect(window.residentCount, greaterThan(30));

      window.evictAround(50);

      expect(window.residentCount, lessThanOrEqualTo(21));
      expect(window.itemAt(50), 500);
      expect(window.itemAt(5), isNull);
    },
  );

  test('captures a fetch error and recovers on retry', () async {
    final source = _FakeSource(50)..failWith = StateError('boom');
    final window = windowFor(source);

    await window.load();
    expect(window.error, isA<StateError>());

    source.failWith = null;
    await window.retry();

    expect(window.error, isNull);
    expect(window.totalCount, 50);
    expect(window.itemAt(0), 0);
  });
}
