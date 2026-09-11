import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/media_image_cache_manager.dart';

/// Full-bleed backdrop image for detail screens, disk-cached via
/// [MediaImageCacheManager] (the same cache posters use) so revisiting a
/// title doesn't refetch its backdrop from network every time.
///
/// Always used inside a `Stack(fit: StackFit.expand)`, which gives this
/// widget tight layout constraints — [LayoutBuilder] reads those to decode
/// the image at its actual on-screen pixel size instead of the source
/// resolution (backdrops are frequently 1920x1080+ while these render as a
/// 200-220dp strip), which is a meaningful decode-cost and memory saving.
///
/// [onLoaded] fires once (post-frame) as soon as the image has produced its
/// first frame - synchronously from cache or after an async decode. The
/// detail hero uses it to hold a flat background until the art *and* its
/// colour-match are both ready, then fade the whole composite in as one.
class CachedBackdropImage extends StatefulWidget {
  const CachedBackdropImage(
    this.url, {
    this.fit = BoxFit.cover,
    this.onLoaded,
    super.key,
  });

  final String url;
  final BoxFit fit;
  final VoidCallback? onLoaded;

  @override
  State<CachedBackdropImage> createState() => _CachedBackdropImageState();
}

class _CachedBackdropImageState extends State<CachedBackdropImage> {
  bool _notifiedLoaded = false;

  @override
  void didUpdateWidget(CachedBackdropImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _notifiedLoaded = false;
  }

  void _handleFrame(bool hasFrame) {
    if (_notifiedLoaded || !hasFrame) return;
    _notifiedLoaded = true;
    final callback = widget.onLoaded;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final provider = CachedNetworkImageProvider(
          widget.url,
          cacheManager: MediaImageCacheManager(),
        );
        final cacheWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth * devicePixelRatio).round()
            : null;
        final cacheHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight * devicePixelRatio).round()
            : null;
        return Image(
          image: cacheWidth == null && cacheHeight == null
              ? provider
              : ResizeImage(
                  provider,
                  width: cacheWidth,
                  height: cacheHeight,
                  policy: ResizeImagePolicy.fit,
                ),
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            _handleFrame(wasSynchronouslyLoaded || frame != null);
            return child;
          },
        );
      },
    );
  }
}
