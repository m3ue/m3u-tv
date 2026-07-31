import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  group('playback aspect ratio', () {
    test('uses explicit display ratio for non-square pixels', () {
      expect(
        playbackAspectRatioFromValues(
          aspectRatio: 4 / 3,
          width: 720,
          height: 576,
        ),
        closeTo(4 / 3, 0.0001),
      );
    });

    test('derives standard and ultrawide ratios from display dimensions', () {
      expect(
        playbackAspectRatioFromValues(width: 1920, height: 1080),
        closeTo(16 / 9, 0.0001),
      );
      expect(
        playbackAspectRatioFromValues(width: 1440, height: 1080),
        closeTo(4 / 3, 0.0001),
      );
      expect(
        playbackAspectRatioFromValues(width: 3840, height: 1608),
        closeTo(3840 / 1608, 0.0001),
      );
    });
  });
}
