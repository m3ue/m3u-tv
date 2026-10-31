import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/natural_sort.dart';

/// Maps a persisted/UI [MediaSortOption] to the [CatalogSort] the windowed
/// SQL query should order by. Kept separate from [MediaSortOption] itself
/// because the two enums serve different layers - [MediaSortOption] is the
/// UI/persistence-facing choice, [CatalogSort] is what the repository can
/// express in SQL - and a future UI-only option (e.g. an "A-Z" alias for the
/// provider order) shouldn't have to grow a matching SQL case.
CatalogSort catalogSortFor(MediaSortOption option) => switch (option) {
  MediaSortOption.defaultOrder => CatalogSort.providerOrder,
  MediaSortOption.ratingDesc => CatalogSort.ratingDesc,
  MediaSortOption.releaseDateDesc => CatalogSort.yearDesc,
  MediaSortOption.releaseDateAsc => CatalogSort.yearAsc,
  MediaSortOption.recentlyAdded ||
  MediaSortOption.recentlyUpdated => CatalogSort.recentDesc,
  MediaSortOption.titleAsc => CatalogSort.nameNatural,
  MediaSortOption.titleDesc => CatalogSort.nameNaturalDesc,
};

/// The sort button's label: generic "Sort" at the default order (matching
/// the static "Filter" button beside it), otherwise the active option's own
/// name so the button doubles as a status indicator.
String mediaSortButtonLabel(AppLocalizations l, MediaSortOption option) =>
    switch (option) {
      MediaSortOption.defaultOrder => l.mediaCategorySortButton,
      MediaSortOption.ratingDesc => l.mediaSortRating,
      MediaSortOption.releaseDateDesc => l.mediaSortReleaseDateNewest,
      MediaSortOption.releaseDateAsc => l.mediaSortReleaseDateOldest,
      MediaSortOption.recentlyAdded => l.mediaSortRecentlyAdded,
      MediaSortOption.recentlyUpdated => l.mediaSortRecentlyUpdated,
      MediaSortOption.titleAsc => l.mediaSortTitleAsc,
      MediaSortOption.titleDesc => l.mediaSortTitleDesc,
    };

/// Sorts a small, fully-materialized list (e.g. a Favorites tab) per
/// [option]. The windowed catalog tabs sort in SQL via
/// [CatalogRepository.pageActiveItems]/[catalogSortFor] instead - this is
/// only for lists too small to be worth a windowed query.
///
/// [nameOf]/[ratingOf]/[yearOf]/[recencyOf] extract the comparison fields from [T] (`VodItem` and
/// `Series` share no common interface for these, so callers supply the
/// accessors rather than this being generic over a shared base type).
List<T> sortMediaItems<T>(
  List<T> items,
  MediaSortOption option, {
  required String Function(T item) nameOf,
  required double? Function(T item) ratingOf,
  required int? Function(T item) yearOf,
  required int? Function(T item) recencyOf,
}) {
  if (option == MediaSortOption.defaultOrder) return items;
  final list = items.toList(growable: false);
  switch (option) {
    case MediaSortOption.defaultOrder:
      break;
    case MediaSortOption.ratingDesc:
      // Unrated items sink below every rated one - keeps the grid visually
      // anchored on the best-rated titles and treats missing data as "less
      // informative" rather than "zero stars".
      list.sort((a, b) => (ratingOf(b) ?? -1).compareTo(ratingOf(a) ?? -1));
    case MediaSortOption.releaseDateDesc:
      // Same sink-unknowns-to-the-bottom treatment as ratingDesc, applied to
      // year instead.
      list.sort((a, b) => (yearOf(b) ?? -1).compareTo(yearOf(a) ?? -1));
    case MediaSortOption.releaseDateAsc:
      // Oldest first, but unknown years still sink last rather than
      // sorting first as the smallest possible value would - "unknown" is
      // not the same claim as "oldest".
      list.sort((a, b) {
        final ay = yearOf(a);
        final by = yearOf(b);
        if (ay == null) return by == null ? 0 : 1;
        if (by == null) return -1;
        return ay.compareTo(by);
      });
    case MediaSortOption.recentlyAdded || MediaSortOption.recentlyUpdated:
      list.sort((a, b) => (recencyOf(b) ?? -1).compareTo(recencyOf(a) ?? -1));
    case MediaSortOption.titleAsc:
      sortByNatural(list, nameOf);
    case MediaSortOption.titleDesc:
      sortByNatural(list, nameOf, descending: true);
  }
  return list;
}
