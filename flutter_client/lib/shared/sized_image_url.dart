/// TMDB width buckets its image CDN serves for any image path. Fetching the
/// smallest one that still covers the decode size keeps a poster grid from
/// downloading (and then decoding down) ~2000x3000 `original` files.
const List<int> _tmdbWidths = <int>[92, 154, 185, 342, 500, 780, 1280];

final RegExp _tmdbImage = RegExp(
  r'^(https?://image\.tmdb\.org/t/p/)(original|w(\d+))(/.+)$',
);

/// Returns [url] rewritten to fetch a server-side downscaled variant at least
/// [decodeWidth] pixels wide, or [url] unchanged when the width is unknown,
/// the host has no sized variants, or no smaller variant would cover it.
///
/// Only TMDB URLs are rewritten. m3u-editor serves its logo proxy, media
/// server and Schedules Direct artwork already downscaled to a role-based
/// size it picks itself (logo proxy URLs carry a `?p=` profile name), and
/// arbitrary provider hosts have no resize API. Its media server image proxy
/// URLs are signed over their full query string, so they must never be
/// modified here.
///
/// Never upsizes: a URL already at a smaller width is left as-is, and a
/// decode wider than the largest bucket keeps `original`. A height alone is
/// not enough to pick a width (a landscape image needs more width than its
/// height), so that case is left unsized rather than guessed.
String sizedImageUrl(String url, {int? decodeWidth}) {
  final target = decodeWidth;
  if (target == null || target <= 0) return url;
  final match = _tmdbImage.firstMatch(url);
  if (match == null) return url;

  final currentWidth = match.group(3) == null
      ? null
      : int.tryParse(match.group(3)!);
  final bucket = _tmdbWidths.firstWhere(
    (width) => width >= target,
    orElse: () => -1,
  );
  if (bucket == -1) return url;
  if (currentWidth != null && currentWidth <= bucket) return url;
  return '${match.group(1)}w$bucket${match.group(4)}';
}
