import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/media_sort.dart';

void main() {
  test('both recency options sort in SQL by the recency column', () {
    expect(
      catalogSortFor(MediaSortOption.recentlyAdded),
      CatalogSort.recentDesc,
    );
    expect(
      catalogSortFor(MediaSortOption.recentlyUpdated),
      CatalogSort.recentDesc,
    );
  });

  test('sortMediaItems orders favorites newest first, undated last', () {
    final items = [('Old', 100), ('Undated', null), ('New', 900)];

    for (final option in [
      MediaSortOption.recentlyAdded,
      MediaSortOption.recentlyUpdated,
    ]) {
      final sorted = sortMediaItems(
        items,
        option,
        ratingOf: (_) => null,
        yearOf: (_) => null,
        recencyOf: (item) => item.$2,
      );
      expect(sorted.map((item) => item.$1), ['New', 'Old', 'Undated']);
    }
  });

  test('persisted recency values round-trip through fromValue', () {
    expect(
      MediaSortOption.fromValue('recentlyAdded'),
      MediaSortOption.recentlyAdded,
    );
    expect(
      MediaSortOption.fromValue('recentlyUpdated'),
      MediaSortOption.recentlyUpdated,
    );
  });
}
