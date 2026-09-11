import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:m3u_tv/shared/tv_zoom_scale.dart';

/// Thumbnail (channel logo, episode/video preview, favorites tile, poster
/// grid cell, ...) disk-cached via [MediaImageCacheManager] and decoded at
/// its actual display size instead of source resolution. Sizes the decode
/// from the explicit [width]/[height] when given, otherwise from the bounded
/// layout constraints.
///
/// For the full-bleed hero image on detail screens, use `CachedBackdropImage`
/// instead: it always sizes from layout and adds frame/load callbacks.
class CachedMediaThumbnail extends StatelessWidget {
  const CachedMediaThumbnail({
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit,
    this.oversample = 1,
    super.key,
  });

  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit? fit;

  /// Decode multiplier on top of the display's raw pixel density. Leave at 1
  /// (decode at display size) for photographic content: on a 4K TV a 2x
  /// oversample makes each decoded bitmap ~4x larger in memory, so a poster
  /// grid can't keep a screenful resident in the image cache and thrashes on
  /// every navigation. Pass 2 only for small fixed-size logos with thin
  /// text/wordmarks, where the box is tiny (so the memory cost is negligible)
  /// but a display-size decode of a large source looks blocky and aliased.
  /// [ResizeImage] never upscales past the source's intrinsic size.
  final double oversample;

  @override
  Widget build(BuildContext context) {
    final oversample =
        ImageQualityScope.oversampleOf(context) * this.oversample;
    final filterQuality = ImageQualityScope.filterQualityOf(context);
    final devicePixelRatio =
        MediaQuery.devicePixelRatioOf(context) *
        oversample *
        TvZoomScale.of(context);
    final provider = CachedNetworkImageProvider(
      url,
      cacheManager: MediaImageCacheManager(),
    );
    // Decode dimensions come from the explicit [width]/[height] when given,
    // otherwise from the bounded layout constraints - so a thumbnail dropped
    // into an Expanded/Flexible slot (e.g. a poster grid cell) still decodes
    // at display size instead of at full source resolution.
    return LayoutBuilder(
      builder: (context, constraints) {
        final decodeWidth =
            width ??
            (constraints.hasBoundedWidth ? constraints.maxWidth : null);
        final decodeHeight =
            height ??
            (constraints.hasBoundedHeight ? constraints.maxHeight : null);
        final cacheWidth = decodeWidth == null
            ? null
            : (decodeWidth * devicePixelRatio).round();
        final cacheHeight = decodeHeight == null
            ? null
            : (decodeHeight * devicePixelRatio).round();
        return Image(
          image: cacheWidth == null && cacheHeight == null
              ? provider
              : ResizeImage(
                  provider,
                  width: cacheWidth,
                  height: cacheHeight,
                  policy: ResizeImagePolicy.fit,
                ),
          width: width,
          height: height,
          fit: fit,
          filterQuality: filterQuality,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}
