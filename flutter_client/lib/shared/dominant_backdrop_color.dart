import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

/// Extracts a single dominant tone from an image so an immersive detail
/// page can bleed it past the backdrop's edge (Nuvio-style). Shared by
/// every detail screen that wants the color-match treatment (Series, VOD)
/// so the extraction + tone-shaping logic doesn't drift between them.
/// Returns null on any failure - callers fall back to the theme surface.
Future<Color?> resolveDominantBackdropColor(String? url) async {
  if (url == null || url.isEmpty) return null;
  try {
    final palette = await PaletteGeneratorMaster.fromImageProvider(
      CachedNetworkImageProvider(url, cacheManager: MediaImageCacheManager()),
      size: const Size(220, 124),
      maximumColorCount: 8,
    );
    final swatch =
        palette.darkMutedColor ??
        palette.darkVibrantColor ??
        palette.dominantColor;
    return swatch == null ? null : deepBackdropTone(swatch.color);
  } on Object catch (_) {
    return null;
  }
}

/// Forces an extracted swatch down to a deep tone: a light-backdrop still
/// (e.g. a near-white kitchen shot) would otherwise bleed a pale colour
/// behind the page and make the light body text unreadable. Hue is kept so
/// the colour wash still reads as "extracted from this art".
Color deepBackdropTone(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness(hsl.lightness.clamp(0.06, 0.20))
      .withSaturation((hsl.saturation * 0.85).clamp(0.0, 0.55))
      .toColor();
}
