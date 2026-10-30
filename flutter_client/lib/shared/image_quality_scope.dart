import 'package:flutter/material.dart';
import 'package:m3u_tv/services/device_performance.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

/// Provides image quality settings (oversample factor and filter quality)
/// to the widget tree based on the user's [OptimizeFor] preference.
///
/// Wrap the app in this widget inside the [MaterialApp.builder] so all
/// image widgets can read the current quality settings without needing
/// direct access to [ViewSettingsService].
class ImageQualityScope extends InheritedWidget {
  const ImageQualityScope({
    required this.optimizeFor,
    required super.child,
    super.key,
  });

  final OptimizeFor optimizeFor;

  /// Oversample factor for image decoding.
  ///
  /// Quality mode uses 2× for sharp logos; Speed mode uses 1× to reduce
  /// GPU memory.
  double get oversample => switch (optimizeFor) {
    OptimizeFor.quality => 2,
    OptimizeFor.speed => 1,
  };

  /// Filter quality for image rendering.
  ///
  /// Quality mode uses [FilterQuality.high]; Speed mode uses
  /// [FilterQuality.medium] for faster rendering.
  FilterQuality get filterQuality => switch (optimizeFor) {
    OptimizeFor.quality => FilterQuality.high,
    OptimizeFor.speed => FilterQuality.medium,
  };

  static ImageQualityScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ImageQualityScope>();
  }

  /// Returns the oversample factor from the nearest [ImageQualityScope].
  /// Falls back to 2 (quality) if no scope is found.
  static double oversampleOf(BuildContext context) =>
      of(context)?.oversample ?? 2;

  /// Returns the filter quality from the nearest [ImageQualityScope].
  /// Falls back to [FilterQuality.high] if no scope is found.
  static FilterQuality filterQualityOf(BuildContext context) =>
      of(context)?.filterQuality ?? FilterQuality.high;

  /// Whether live blur effects (`BackdropFilter`, `ImageFilter.blur`) are
  /// worth their cost: each forces an offscreen layer and re-blurs whatever
  /// is behind it every frame, which low-end TV GPUs feel. Off on
  /// reduced-tier hardware and in Speed mode; callers fall back to a more
  /// opaque tint.
  static bool allowsBlurOf(BuildContext context) =>
      !DevicePerformance.isReduced &&
      (of(context)?.optimizeFor ?? OptimizeFor.quality) == OptimizeFor.quality;

  @override
  bool updateShouldNotify(ImageQualityScope oldWidget) =>
      optimizeFor != oldWidget.optimizeFor;
}

/// Provides the current [AppFontSize] scale to the widget tree so child
/// widgets can adjust sizing (e.g. logo dimensions) based on the user's
/// font size preference.
class FontSizeScope extends InheritedWidget {
  const FontSizeScope({
    required this.fontSize,
    required super.child,
    super.key,
  });

  final AppFontSize fontSize;

  /// The text scale factor (1.0 for normal, 1.2 for large, 1.5 for very
  /// large).
  double get scale => fontSize.scale;

  /// Whether the user has selected large or very large (i.e. anything above
  /// the normal default).
  bool get isLarge => fontSize != AppFontSize.normal;

  static FontSizeScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<FontSizeScope>();
  }

  /// Returns the font size scale from the nearest [FontSizeScope].
  /// Falls back to 1.0 (normal) if no scope is found.
  static double scaleOf(BuildContext context) => of(context)?.scale ?? 1.0;

  /// Returns whether large (or very large) font size is active.
  static bool isLargeOf(BuildContext context) => of(context)?.isLarge ?? false;

  @override
  bool updateShouldNotify(FontSizeScope oldWidget) =>
      fontSize != oldWidget.fontSize;
}

/// Tells descendant image widgets (`ResilientMediaImage`) to skip resolving
/// and decoding new images while true - set by `ScrollbarGridView` while
/// `ScrollPosition.recommendDeferredLoading` says the enclosing scroll view
/// is moving fast enough that decode work should wait.
///
/// A fast fling over a poster grid can otherwise queue dozens of
/// near-simultaneous native bitmap decodes; on a low-RAM Android TV box that
/// burst can outrun the image-cache ceiling and the polling `MemoryWatchdog`
/// backstop, causing a native OOM before either ever reacts. Deferring
/// during the fling and letting cells resolve normally once it settles
/// avoids the burst instead of trying to survive it.
class DeferImageLoadingScope extends InheritedWidget {
  const DeferImageLoadingScope({
    required this.defer,
    required super.child,
    super.key,
  });

  final bool defer;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DeferImageLoadingScope>()
          ?.defer ??
      false;

  @override
  bool updateShouldNotify(DeferImageLoadingScope oldWidget) =>
      defer != oldWidget.defer;
}
