// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:m3u_tv/services/async_lifecycle.dart';

/// Fetches one page of rows from the backing store.
typedef CatalogPageFetcher<T> = Future<List<T>> Function(int offset, int limit);

/// Fetches the total row count for the current slice.
typedef CatalogCountFetcher = Future<int> Function();

/// Sparse, page-loaded view over a large ordered catalog that lives in SQLite.
///
/// The Plezy `PaginatedItemLoader` idea (see `plezy/lib/mixins/
/// paginated_item_loader.dart`) minus the network: a grid renders
/// [totalCount] slots, asks for the indices it is about to show via
/// [ensureVisible], and reads them back with [itemAt]. Pages resolve from the
/// local database in well under a frame, and [evictAround] keeps only a window
/// of rows resident so a 100k-item library costs a few hundred objects instead
/// of all of them.
///
/// Re-point it at a different slice (category tab, search text) with
/// [configure]; a generation counter discards any page still in flight from
/// the previous configuration.
class CatalogWindow<T> extends ChangeNotifier {
  CatalogWindow({
    required CatalogPageFetcher<T> fetchPage,
    required CatalogCountFetcher fetchCount,
    this.pageSize = 60,
    this.keepWindow = 600,
    this.evictThreshold = 800,
  }) : _fetchPage = fetchPage,
       _fetchCount = fetchCount;

  CatalogPageFetcher<T> _fetchPage;
  CatalogCountFetcher _fetchCount;

  /// Rows per database fetch.
  final int pageSize;

  /// Rows kept resident, centered on the last [evictAround] index.
  final int keepWindow;

  /// [evictAround] only trims once more than this many rows are resident.
  final int evictThreshold;

  final Map<int, T> _items = <int, T>{};
  final Set<int> _pagesInFlight = <int>{};
  final Generation _generation = Generation();
  final SerialQueue _queue = SerialQueue();

  int _totalCount = 0;
  bool _loadingCount = false;
  bool _loadedOnce = false;
  Object? _error;

  int get totalCount => _totalCount;
  bool get isLoadingCount => _loadingCount;

  /// True once a [load] has successfully returned a count. Callers use this to
  /// stay on a fallback UI until the window is demonstrably working (a hung or
  /// failed database must not strand them on a spinner).
  bool get hasLoadedOnce => _loadedOnce;
  Object? get error => _error;
  int get residentCount => _items.length;

  /// The row at [index], or null when it has not been fetched yet (or was
  /// evicted). A null result is a cue for the caller to render a placeholder;
  /// [ensureVisible] is what actually schedules the fetch.
  T? itemAt(int index) => _items[index];

  /// Swap the underlying query (new category / search text), then [load].
  Future<void> configure({
    required CatalogPageFetcher<T> fetchPage,
    required CatalogCountFetcher fetchCount,
  }) {
    _fetchPage = fetchPage;
    _fetchCount = fetchCount;
    return load();
  }

  /// Load (or reload) from the start: refresh [totalCount] and fetch the first
  /// page. Discards any page still in flight from a previous call.
  Future<void> load() async {
    final generation = _generation.advance();
    _items.clear();
    _pagesInFlight.clear();
    _error = null;
    _loadingCount = true;
    notifyListeners();

    try {
      final count = await _fetchCount();
      if (_generation.isStale(generation)) return;
      _totalCount = count;
      _loadingCount = false;
      _loadedOnce = true;
      notifyListeners();
      await _fetchPageAt(0, generation);
    } on Object catch (error) {
      if (_generation.isStale(generation)) return;
      _error = error;
      _loadingCount = false;
      notifyListeners();
    }
  }

  /// Ensure every index in `[firstIndex - buffer, firstIndex + visibleCount +
  /// buffer)` is loaded (or being loaded). Cheap to call from an item builder
  /// or scroll listener every frame.
  void ensureVisible(int firstIndex, int visibleCount, {int buffer = 40}) {
    if (_totalCount == 0) return;
    final start = (firstIndex - buffer).clamp(0, _totalCount - 1);
    final end = (firstIndex + visibleCount + buffer).clamp(0, _totalCount);
    final firstPage = start ~/ pageSize;
    final lastPage = (end - 1) ~/ pageSize;
    final generation = _generation.current;
    for (var page = firstPage; page <= lastPage; page++) {
      final offset = page * pageSize;
      if (_pagesInFlight.contains(page) || _items.containsKey(offset)) continue;
      unawaited(_fetchPageAt(offset, generation));
    }
  }

  Future<void> _fetchPageAt(int offset, int generation) {
    final page = offset ~/ pageSize;
    if (_pagesInFlight.contains(page)) return Future<void>.value();
    _pagesInFlight.add(page);
    return _queue.run(() async {
      if (_generation.isStale(generation)) {
        _pagesInFlight.remove(page);
        return;
      }
      try {
        final rows = await _fetchPage(offset, pageSize);
        if (_generation.isStale(generation)) return;
        for (var i = 0; i < rows.length; i++) {
          _items[offset + i] = rows[i];
        }
        _error = null;
        notifyListeners();
      } on Object catch (error) {
        if (_generation.isStale(generation)) return;
        _error = error;
        notifyListeners();
      } finally {
        _pagesInFlight.remove(page);
      }
    });
  }

  /// Drop rows far from [centerIndex] once more than [evictThreshold] are
  /// resident, keeping a [keepWindow]-wide band centered on it.
  void evictAround(int centerIndex) {
    if (_items.length <= evictThreshold) return;
    final half = keepWindow ~/ 2;
    _items.removeWhere(
      (index, _) => index < centerIndex - half || index > centerIndex + half,
    );
  }

  /// Retry after an [error] without disturbing the resident rows.
  Future<void> retry() => load();
}
