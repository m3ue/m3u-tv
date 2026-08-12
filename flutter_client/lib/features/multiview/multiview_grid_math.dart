import 'package:flutter/widgets.dart' show TraversalDirection;

/// Column count for the Multiview grid at a given stream count: 1 stream is
/// full-bleed, 2-4 form a 2-wide grid, 5-9 form a 3-wide grid (with a
/// shorter last row where the count isn't a multiple of 3).
int multiviewGridColumns(int itemCount) {
  if (itemCount <= 1) return 1;
  if (itemCount <= 4) return 2;
  return 3;
}

/// The tile index reorder mode should swap [index] with when the user
/// presses [direction], or `null` if that direction is off the grid (e.g.
/// pressing left from the first column, or down from the last row).
int? multiviewSwapTarget({
  required int index,
  required int itemCount,
  required TraversalDirection direction,
}) {
  final columns = multiviewGridColumns(itemCount);
  final row = index ~/ columns;
  final col = index % columns;
  final rows = (itemCount / columns).ceil();
  final target = switch (direction) {
    TraversalDirection.left when col > 0 => index - 1,
    TraversalDirection.right when col < columns - 1 => index + 1,
    TraversalDirection.up when row > 0 => index - columns,
    TraversalDirection.down when row + 1 < rows => index + columns,
    _ => null,
  };
  if (target == null || target < 0 || target >= itemCount) return null;
  return target;
}
