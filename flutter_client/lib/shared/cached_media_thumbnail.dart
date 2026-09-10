import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/main.dart' show TvZoomScale;
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';

/// Fixed-size thumbnail (channel logo, episode/video preview, favorites
/// tile, ...) disk-cached via [MediaImageCacheManager] and decoded at its
/// actual display size instead of source resolution.
///
/// For the full-bleed hero image on detail screens, use
/// `CachedBackdropImage` instead — it derives its size from layout rather
/// than fixed [width]/[height].
class CachedMediaThumbnail extends StatelessWidget {
  const CachedMediaThumbnail({
    required this.url,
    required this.fallback,
    this.width,
    this.height,
    this.fit,
    super.key,
  });

  final String url;
  final Widget fallback;
  final double? width;
  final double? height;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    final oversample = ImageQualityScope.oversampleOf(context);
    final filterQuality = ImageQualityScope.filterQualityOf(context);
    final devicePixelRatio =
        MediaQuery.devicePixelRatioOf(context) *
        oversample *
        TvZoomScale.of(context);
    final provider = CachedNetworkImageProvider(
      url,
      cacheManager: MediaImageCacheManager(),
    );
    final cacheWidth = width == null
        ? null
        : (width! * devicePixelRatio).round();
    final cacheHeight = height == null
        ? null
        : (height! * devicePixelRatio).round();
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
  }
}
