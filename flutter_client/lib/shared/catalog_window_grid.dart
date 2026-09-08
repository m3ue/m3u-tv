import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/catalog_window.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// A [ScrollbarGridView] driven by a [CatalogWindow]: it renders
/// `window.totalCount` slots, asks the window to load the indices it is about
/// to build, and evicts rows that scroll far out of view. Unresolved slots
/// render [placeholderBuilder] at the same geometry as a real card so focus
/// and layout do not shift when the row lands a frame later.
///
/// Loading is driven from [ScrollbarGridView.itemBuilder] rather than a scroll
/// listener: `GridView.builder` only builds indices near the viewport, so
/// calling [CatalogWindow.ensureVisible] there covers the visible band plus a
/// look-ahead buffer without needing the (private) scroll controller.
class CatalogWindowGrid<T> extends StatefulWidget {
  const CatalogWindowGrid({
    required this.window,
    required this.gridDelegate,
    required this.crossAxisCount,
    required this.itemBuilder,
    required this.placeholderBuilder,
    this.padding = const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
    this.lookAheadRows = 6,
    super.key,
  });

  final CatalogWindow<T> window;
  final SliverGridDelegate gridDelegate;

  /// Column count of [gridDelegate]; used to size the look-ahead band.
  final int crossAxisCount;

  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final Widget Function(BuildContext context, int index) placeholderBuilder;
  final EdgeInsetsGeometry padding;

  /// Rows of extra items to keep loaded ahead of / behind the viewport.
  final int lookAheadRows;

  @override
  State<CatalogWindowGrid<T>> createState() => _CatalogWindowGridState<T>();
}

class _CatalogWindowGridState<T> extends State<CatalogWindowGrid<T>> {
  @override
  void initState() {
    super.initState();
    widget.window.addListener(_onWindowChanged);
  }

  @override
  void didUpdateWidget(CatalogWindowGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.window != widget.window) {
      oldWidget.window.removeListener(_onWindowChanged);
      widget.window.addListener(_onWindowChanged);
    }
  }

  @override
  void dispose() {
    widget.window.removeListener(_onWindowChanged);
    super.dispose();
  }

  void _onWindowChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    final band = widget.crossAxisCount * widget.lookAheadRows;

    return ScrollbarGridView(
      gridDelegate: widget.gridDelegate,
      padding: widget.padding,
      itemCount: window.totalCount,
      itemBuilder: (context, index) {
        window.ensureVisible(index, band, buffer: band);
        // Trim once per page boundary so a long scroll can't accumulate the
        // whole catalog in memory.
        if (index % window.pageSize == 0) window.evictAround(index);
        final item = window.itemAt(index);
        return item == null
            ? widget.placeholderBuilder(context, index)
            : widget.itemBuilder(context, index, item);
      },
    );
  }
}
