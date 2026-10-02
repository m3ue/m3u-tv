import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/mpv_seek_window.dart';

void main() {
  test('reads the seekable ranges from mpv demuxer cache state', () {
    final window = mpvSeekWindow(const <String, Object?>{
      'cacheState':
          '{"cache-end":616.2,"reader-pts":602.6,"seekable-ranges":'
          '[{"start":30.021333,"end":51.981333},{"start":600.0,"end":615.96}]}',
    });

    expect(window?.buffered, <({Duration start, Duration end})>[
      (
        start: const Duration(seconds: 30, microseconds: 21333),
        end: const Duration(seconds: 51, microseconds: 981333),
      ),
      (
        start: const Duration(seconds: 600),
        end: const Duration(seconds: 615, milliseconds: 960),
      ),
    ]);
    expect(window!.contains(const Duration(seconds: 45)), isTrue);
    expect(window.contains(const Duration(seconds: 100)), isFalse);
  });

  test('is an empty window when mpv has nothing it can seek to', () {
    final window = mpvSeekWindow(const <String, Object?>{
      'cacheState': '{"cache-end":0,"seekable-ranges":[]}',
    });

    expect(window?.buffered, isEmpty);
  });

  test('is null without a usable cache state', () {
    expect(mpvSeekWindow(null), isNull);
    expect(mpvSeekWindow(const <String, Object?>{}), isNull);
    expect(mpvSeekWindow(const <String, Object?>{'cacheState': ''}), isNull);
    expect(
      mpvSeekWindow(const <String, Object?>{'cacheState': 'not json'}),
      isNull,
    );
  });
}
