import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/shared/sized_image_url.dart';

void main() {
  const original = 'https://image.tmdb.org/t/p/original/abc.jpg';

  test('picks the smallest TMDB width that covers the decode width', () {
    expect(
      sizedImageUrl(original, decodeWidth: 400),
      'https://image.tmdb.org/t/p/w500/abc.jpg',
    );
    expect(
      sizedImageUrl(original, decodeWidth: 342),
      'https://image.tmdb.org/t/p/w342/abc.jpg',
    );
  });

  test('leaves the URL unsized when only the height is known', () {
    expect(sizedImageUrl(original), original);
  });

  test('keeps original when the decode is wider than every bucket', () {
    expect(sizedImageUrl(original, decodeWidth: 1920), original);
  });

  test('never upsizes a URL that is already smaller', () {
    const small = 'https://image.tmdb.org/t/p/w185/abc.jpg';
    expect(sizedImageUrl(small, decodeWidth: 400), small);
  });

  test('downsizes a URL that is already sized but larger than needed', () {
    expect(
      sizedImageUrl(
        'https://image.tmdb.org/t/p/w1280/abc.jpg',
        decodeWidth: 300,
      ),
      'https://image.tmdb.org/t/p/w342/abc.jpg',
    );
  });

  test('leaves non-TMDB URLs and unknown sizes alone', () {
    const proxied = 'https://editor.example/logo-proxy/abc?w=600';
    expect(sizedImageUrl(proxied, decodeWidth: 200), proxied);
    expect(sizedImageUrl(original), original);
    const profile = 'https://image.tmdb.org/t/p/h632/abc.jpg';
    expect(sizedImageUrl(profile, decodeWidth: 100), profile);
  });
  test('never modifies signed m3u-editor media server image URLs', () {
    const signed =
        'http://m3ueditor.test:80/media-server/3/image/97370/Primary?v=1&signature=abc123';
    expect(sizedImageUrl(signed, decodeWidth: 300), signed);
  });
}
