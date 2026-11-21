import 'dart:async';
import 'dart:io';

/// MIME for an HLS playlist (`#EXTM3U`).
const String kHlsMime = 'application/vnd.apple.mpegurl';

/// MIME for a raw MPEG-TS byte stream.
const String kTsMime = 'video/mp2t';

/// Resolves whether a `?timeshift=1` live URL currently serves an HLS window
/// (warm buffer) or a raw MPEG-TS pipe (cold buffer / plain proxy fallback).
///
/// The server varies the response for the same `.m3u8` URL: warm requests
/// redirect to a signed HLS playlist, cold ones fall through to the proxy's
/// `/stream/{id}` TS pipe. ExoPlayer infers HLS from the `.m3u8` extension
/// before it ever sees the body, so the caller must pass the resolved MIME via
/// `MediaItem.setMimeType` or the TS pipe fails with
/// `Input does not start with the #EXTM3U header`.
///
/// The body is sniffed *before* the `Content-Type` header: these proxy streams
/// are not labelled reliably and a raw TS body can arrive labelled as a
/// playlist. Only the first bytes of a live pipe are read, then the connection
/// is force-closed, so a never-ending TS stream is never drained.
///
/// Returns null on timeout/failure; callers should fall back to [kTsMime]
/// (the cold case is what breaks) — the native player also retries the flipped
/// MIME on a format-mismatch error.
Future<String?> probeTimeshiftMime(
  String url, {
  // The first cold request makes the editor create/kick off the pooled stream
  // before it redirects, which can take a few seconds. Too short a deadline
  // times out → the caller falls back to TS → ExoPlayer parses the eventual
  // HLS playlist as progressive and briefly errors. Warm opens answer at once.
  Duration timeout = const Duration(milliseconds: 6000),
}) async {
  HttpClient? client;
  try {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 1200)
      ..idleTimeout = const Duration(milliseconds: 1200);

    final deadline = DateTime.now().add(timeout);
    Duration remaining() {
      final left = deadline.difference(DateTime.now());
      // HttpClient treats a zero timeout as "immediate", so never pass < 1ms.
      return left.isNegative || left == Duration.zero
          ? const Duration(milliseconds: 1)
          : left;
    }

    Future<HttpClientResponse> open(Uri target) async {
      final request = await client!.getUrl(target).timeout(remaining());
      request.followRedirects = false;
      return request.close().timeout(remaining());
    }

    var response = await open(uri);

    // Walk redirects manually: the final hop tells us the real container.
    var hops = 0;
    while (response.statusCode >= 300 &&
        response.statusCode < 400 &&
        hops < 5) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>().catchError((Object _) {});
      if (location == null) return null;
      final next = uri.resolve(location);
      final path = next.path.toLowerCase();
      if (path.contains('.m3u8')) return kHlsMime;
      if (path.contains('/stream/')) return kTsMime;
      response = await open(next);
      hops++;
    }

    final contentType = response.headers.contentType?.mimeType ?? '';

    // Sniff the first bytes. `#EXTM3U` is 7 bytes; a TS packet starts 0x47.
    final head = <int>[];
    try {
      await for (final chunk in response.timeout(
        const Duration(milliseconds: 800),
      )) {
        head.addAll(chunk);
        if (head.length >= 7) break;
      }
    } on TimeoutException {
      // Fall through to the header hint / null.
    } on Object {
      // Fall through to the header hint / null.
    }

    if (head.length >= 7 &&
        String.fromCharCodes(head.take(7)).startsWith('#EXTM3U')) {
      return kHlsMime;
    }
    if (head.isNotEmpty) return kTsMime;

    // No body within the deadline — trust the header as a last resort.
    if (contentType.contains('mpegurl')) return kHlsMime;
    if (contentType.contains('mp2t')) return kTsMime;
    return null;
  } on Object {
    return null;
  } finally {
    client?.close(force: true);
  }
}
