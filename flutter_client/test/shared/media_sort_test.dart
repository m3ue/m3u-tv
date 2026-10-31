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
        nameOf: (item) => item.$1,
        ratingOf: (_) => null,
        yearOf: (_) => null,
        recencyOf: (item) => item.$2,
      );
      expect(sorted.map((item) => item.$1), ['New', 'Old', 'Undated']);
    }
  });

  test('title options sort in SQL by the natural name key', () {
    expect(catalogSortFor(MediaSortOption.titleAsc), CatalogSort.nameNatural);
    expect(
      catalogSortFor(MediaSortOption.titleDesc),
      CatalogSort.nameNaturalDesc,
    );
  });

  test('sortMediaItems orders favorites by title in natural order', () {
    final items = ['Zodiac', '10 Things', 'alien', '2 Fast'];

    List<String> sortedBy(MediaSortOption option) => sortMediaItems(
      items,
      option,
      nameOf: (item) => item,
      ratingOf: (_) => null,
      yearOf: (_) => null,
      recencyOf: (_) => null,
    );

    expect(sortedBy(MediaSortOption.titleAsc), [
      '2 Fast',
      '10 Things',
      'alien',
      'Zodiac',
    ]);
    expect(sortedBy(MediaSortOption.titleDesc), [
      'Zodiac',
      'alien',
      '10 Things',
      '2 Fast',
    ]);
    expect(items, ['Zodiac', '10 Things', 'alien', '2 Fast']);
  });

  test('persisted title values round-trip through fromValue', () {
    expect(MediaSortOption.fromValue('titleAsc'), MediaSortOption.titleAsc);
    expect(MediaSortOption.fromValue('titleDesc'), MediaSortOption.titleDesc);
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
