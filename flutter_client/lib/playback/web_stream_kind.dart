/// Which of the web backend's players a stream needs.
enum WebStreamKind { hls, mpegTs, matroska, native }

/// Picks the player for a stream from its probe response.
///
/// What the server sends wins over the requested extension: live channels are
/// always requested as `.m3u8`, but the editor redirects to raw MPEG-TS when
/// nothing converts the stream to HLS, and hls.js waits on that endless body
/// forever without reporting an error.
///
/// [resolvedUri] is where the probe ended up after redirects, or null when it
/// failed. URLs are only consulted when [contentType] doesn't name a format.
WebStreamKind webStreamKind({
  required String contentType,
  required Uri requestedUri,
  required Uri? resolvedUri,
  required bool isLive,
}) {
  final type = contentType.toLowerCase();
  if (type.contains('mpegurl')) return WebStreamKind.hls;
  if (type.contains('mp2t')) return WebStreamKind.mpegTs;
  if (type.contains('matroska')) {
    return isLive ? WebStreamKind.native : WebStreamKind.matroska;
  }

  final path = (resolvedUri ?? requestedUri).path.toLowerCase();
  if (path.endsWith('.m3u8')) return WebStreamKind.hls;
  if (type.startsWith('video/')) return WebStreamKind.native;
  if (path.endsWith('.ts')) return WebStreamKind.mpegTs;

  final isProxyStream = path.contains('/stream/');
  if (isLive && isProxyStream) return WebStreamKind.mpegTs;

  // The proxy's `/stream/<id>` has no extension, so use the requested one.
  final requestedPath = requestedUri.path.toLowerCase();
  if (requestedPath.endsWith('.ts')) return WebStreamKind.mpegTs;
  if (requestedPath.endsWith('.mkv') || path.endsWith('.mkv')) {
    return isLive ? WebStreamKind.native : WebStreamKind.matroska;
  }
  if (requestedPath.endsWith('.m3u8') && !isProxyStream) {
    return WebStreamKind.hls;
  }
  return WebStreamKind.native;
}
