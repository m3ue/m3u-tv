import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/catalog_window.dart';

/// Row-indexed access to the channels a Live TV view (list, grid or guide)
/// shows. A row can be null while its page is still loading; views render a
/// placeholder for it and call [ensureLoaded] from their item builders.
///
/// A view treats a new instance as new content, so implementations hand out
/// a fresh one whenever their rows change.
abstract interface class ChannelRows {
  int get length;

  /// The channel at [index], or null while it is loading.
  Channel? operator [](int index);

  /// Asks for the [count] rows from [index] (plus any look-ahead the
  /// implementation keeps) to be loaded. Cheap to call on every build.
  void ensureLoaded(int index, int count);

  /// The deepest catchup retention, in days, across every row.
  int get maxCatchupDays;
}

/// [ChannelRows] over a [CatalogWindow] paged from the SQLite catalog.
///
/// A snapshot: the owner hands out a new instance each time the window
/// notifies (a page landed, the slice changed), so views see new content.
class WindowChannelRows implements ChannelRows {
  WindowChannelRows(this.window, {required this.maxCatchupDays})
    : length = window.totalCount;

  final CatalogWindow<Channel> window;

  @override
  final int length;

  @override
  final int maxCatchupDays;

  @override
  Channel? operator [](int index) => window.itemAt(index);

  @override
  void ensureLoaded(int index, int count) {
    window.ensureVisible(index, count);
    // Trim once per page boundary so a long scroll can't accumulate the
    // whole lineup in memory.
    if (index % window.pageSize == 0) window.evictAround(index);
  }
}
