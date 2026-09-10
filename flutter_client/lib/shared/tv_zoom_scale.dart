import 'package:flutter/widgets.dart';

/// The extra scale factor `_TvZoom` (in `main.dart`) applies on top of the
/// real screen's devicePixelRatio. Image cache-dimension widgets
/// (`CachedBackdropImage`, `CachedMediaThumbnail`, `ResilientMediaImage`)
/// multiply `MediaQuery.devicePixelRatioOf(context)` by this when sizing their
/// `ResizeImage`, since they compute cache dimensions from local widget
/// size/constraints in the shrunk virtual canvas, unlike code that reads
/// devicePixelRatio together with `localToGlobal()`, which already lands in
/// real-space coordinates via the FittedBox's paint transform and needs no
/// correction. Defaults to 1 outside the TV zoom (non-TV devices, or any
/// context above `_TvZoom` in the tree).
class TvZoomScale extends InheritedWidget {
  const TvZoomScale({required this.scale, required super.child, super.key});

  final double scale;

  static double of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvZoomScale>()?.scale ??
        1;
  }

  @override
  bool updateShouldNotify(TvZoomScale oldWidget) => scale != oldWidget.scale;
}
