import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/web_stream_kind.dart';

WebStreamKind _kind(
  String contentType, {
  String requested = '/live/u/p/5.m3u8',
  String? resolved,
  bool isLive = true,
}) => webStreamKind(
  contentType: contentType,
  requestedUri: Uri.parse('http://editor.test$requested?proxy=true'),
  resolvedUri: resolved == null
      ? null
      : Uri.parse('http://editor.test$resolved?username=u'),
  isLive: isLive,
);

void main() {
  test('live .m3u8 request redirected to raw MPEG-TS uses mpegts', () {
    expect(
      _kind('video/mp2t', resolved: '/m3u-proxy/stream/abc'),
      WebStreamKind.mpegTs,
    );
  });

  test('live proxy stream with no known type uses mpegts', () {
    expect(
      _kind('application/octet-stream', resolved: '/m3u-proxy/stream/abc'),
      WebStreamKind.mpegTs,
    );
  });

  test('HLS output uses hls', () {
    expect(
      _kind(
        'application/vnd.apple.mpegurl',
        resolved: '/m3u-proxy/hls/abc/playlist.m3u8',
      ),
      WebStreamKind.hls,
    );
    expect(
      _kind('text/plain', resolved: '/m3u-proxy/hls/abc/playlist.m3u8'),
      WebStreamKind.hls,
    );
  });

  test('a failed probe falls back to the requested extension', () {
    expect(_kind(''), WebStreamKind.hls);
    expect(
      _kind('', requested: '/timeshift/u/p/60/x/5.ts', isLive: false),
      WebStreamKind.mpegTs,
    );
  });

  test('VOD containers keep their players', () {
    expect(
      _kind(
        'application/octet-stream',
        requested: '/movie/u/p/5.mkv',
        resolved: '/m3u-proxy/stream/abc',
        isLive: false,
      ),
      WebStreamKind.matroska,
    );
    expect(
      _kind(
        'video/mp4',
        requested: '/movie/u/p/5.mp4',
        resolved: '/m3u-proxy/stream/abc',
        isLive: false,
      ),
      WebStreamKind.native,
    );
  });
}
