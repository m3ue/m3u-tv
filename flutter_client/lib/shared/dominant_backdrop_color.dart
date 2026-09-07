import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:palette_generator_master/palette_generator_master.dart';

/// Extracts the dominant swatch from an image so an immersive detail page
/// can bleed a matching colour past the backdrop's edge (Nuvio-style).
/// Shared by every detail screen that wants the colour-match treatment
/// (Series, VOD) so the extraction stays consistent between them.
///
/// Returns the raw swatch colour (or null on any failure - callers fall
/// back to the theme surface). Callers pass it through [deepBackdropTone]
/// themselves once they know the layout, because the tone that reads well
/// full-bleed on a TV (very deep) just looks black on a phone, where the
/// wash sits behind a short band with the page scrolling over it.
///
/// The result is memoized per URL: detail screens re-run this on every visit,
/// and without the cache, revisiting a title (the common in/out-of-detail
/// navigation pattern) re-decodes the backdrop a second time just for palette
/// extraction. The `null` sentinel is cached too so known failures don't retry.
// Bounded so a long browsing session can't grow the map without limit.
const int _maxCachedSwatches = 128;
final Map<String, Color?> _swatchCache = <String, Color?>{};

/// In-flight extractions keyed by URL, so two screens (or a fast back/forward
/// on the same title) that ask before the first decode resolves share one
/// palette computation instead of both running it.
final Map<String, Future<Color?>> _pendingSwatches = <String, Future<Color?>>{};

Future<Color?> resolveDominantBackdropColor(String? url) {
  if (url == null || url.isEmpty) return Future<Color?>.value();
  if (_swatchCache.containsKey(url)) {
    return Future<Color?>.value(_swatchCache[url]);
  }
  final pending = _pendingSwatches[url];
  if (pending != null) return pending;
  final future = _extractSwatch(url);
  _pendingSwatches[url] = future;
  return future;
}

Future<Color?> _extractSwatch(String url) async {
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
    _rememberSwatch(url, swatch?.color);
    return swatch?.color;
  } on Object catch (_) {
    _rememberSwatch(url, null);
    return null;
  } finally {
    // remove() hands back the stored Future; nothing awaits it here.
    // ignore: unawaited_futures
    _pendingSwatches.remove(url);
  }
}

void _rememberSwatch(String url, Color? color) {
  if (_swatchCache.length >= _maxCachedSwatches) {
    _swatchCache.remove(_swatchCache.keys.first);
  }
  _swatchCache[url] = color;
}

/// Shapes an extracted swatch into a background wash. Hue is always kept so
/// the colour still reads as "pulled from this art"; lightness and
/// saturation are clamped so a near-white still (e.g. a bright kitchen shot)
/// can't bleed a pale colour behind the light body text.
///
/// [vivid] loosens both clamps for phone layouts: the backdrop there is a
/// short band with solid colour filling the rest of the (portrait) page, so
/// the default deep tone reads as flat black instead of "a red/green wash".
/// A slightly lighter, more saturated tone still clears text-contrast while
/// actually looking like a colour on a small screen.
Color deepBackdropTone(Color color, {bool vivid = false}) {
  final hsl = HSLColor.fromColor(color);
  final minLightness = vivid ? 0.16 : 0.06;
  final maxLightness = vivid ? 0.34 : 0.20;
  // The extracted swatch is often a dark *muted* tone; on a phone that needs
  // its saturation pushed up (not just kept) to read as a colour rather than
  // grey. The ceiling keeps it from going neon.
  final saturationScale = vivid ? 1.5 : 0.85;
  final maxSaturation = vivid ? 0.72 : 0.55;
  return hsl
      .withLightness(hsl.lightness.clamp(minLightness, maxLightness))
      .withSaturation(
        (hsl.saturation * saturationScale).clamp(0.0, maxSaturation),
      )
      .toColor();
}
