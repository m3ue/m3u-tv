import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:m3u_tv/shared/embedded_origin.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:material_ui/material_ui.dart';

/// The image provider for a remote poster, backdrop, logo or thumbnail.
///
/// Natively (and for same-origin URLs on the web) this is the usual
/// [CachedNetworkImageProvider]. The web build served by M3U Editor at
/// /m3u-tv/ instead gets a [CorsFallbackImageProvider] for other origins:
/// Flutter's web renderer fetches image bytes rather than using an `<img>`
/// tag, so a host that sends no CORS headers (e.g. AIOStreams' RPDB posters)
/// can't be loaded directly and goes through the editor's /logo-proxy/.
ImageProvider<Object> mediaImageProvider(String url) {
  final origin = embeddedEditorOrigin;
  if (origin == null) {
    return CachedNetworkImageProvider(
      url,
      cacheManager: mediaImageCacheManager,
    );
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.origin == origin) {
    return CachedNetworkImageProvider(url);
  }
  return CorsFallbackImageProvider(url, editorOrigin: origin);
}

/// Loads [url] directly and, when the browser blocks that for missing CORS
/// headers, through M3U Editor's /logo-proxy/ on [editorOrigin] (same
/// origin, so always readable). A host that needed the proxy once goes
/// straight to it for the rest of the session, so it costs one blocked
/// request per host rather than per image.
@immutable
class CorsFallbackImageProvider
    extends ImageProvider<CorsFallbackImageProvider> {
  const CorsFallbackImageProvider(this.url, {required this.editorOrigin});

  final String url;
  final String editorOrigin;

  static final Set<String> _proxiedHosts = <String>{};
  static final http.Client _client = http.Client();

  /// The editor's logo-proxy URL for [url] (unpadded base64url, the same
  /// encoding as `LogoProxyController::generateProxyUrl`).
  String get proxyUrl {
    final encoded = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
    return '$editorOrigin/logo-proxy/$encoded/image';
  }

  @override
  Future<CorsFallbackImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<CorsFallbackImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    CorsFallbackImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadCodec(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final host = Uri.parse(url).host;
    Uint8List? bytes;
    if (!_proxiedHosts.contains(host)) {
      try {
        bytes = await _fetch(url);
      } on http.ClientException {
        // A CORS rejection surfaces as a network error with no status
        // (unlike a 404, which throws a StateError below and isn't retried).
        _proxiedHosts.add(host);
      }
    }
    bytes ??= await _fetch(proxyUrl);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _fetch(String target) async {
    final response = await _client.get(Uri.parse(target));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode} loading image');
    }
    return response.bodyBytes;
  }

  @override
  bool operator ==(Object other) =>
      other is CorsFallbackImageProvider &&
      other.url == url &&
      other.editorOrigin == editorOrigin;

  @override
  int get hashCode => Object.hash(url, editorOrigin);

  @override
  String toString() => 'CorsFallbackImageProvider("$url")';
}
