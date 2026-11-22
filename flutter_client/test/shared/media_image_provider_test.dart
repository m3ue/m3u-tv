import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/media_image_provider.dart';

void main() {
  test('proxy URL matches the editor logo-proxy encoding', () {
    const url =
        'https://aiostreams.example/api/v1/posters/rpdb?id=tmdb%3A1307474&type=movie';
    const provider = CorsFallbackImageProvider(
      url,
      editorOrigin: 'http://editor.test',
    );

    final proxyUrl = Uri.parse(provider.proxyUrl);
    expect(proxyUrl.origin, 'http://editor.test');
    expect(proxyUrl.pathSegments.first, 'logo-proxy');

    final encoded = proxyUrl.pathSegments[1];
    expect(encoded, isNot(contains('=')));
    expect(
      utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      url,
    );
  });

  test('providers for the same image share an image cache key', () {
    const a = CorsFallbackImageProvider(
      'https://x.example/a.jpg',
      editorOrigin: 'http://editor.test',
    );
    const b = CorsFallbackImageProvider(
      'https://x.example/a.jpg',
      editorOrigin: 'http://editor.test',
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });
}
