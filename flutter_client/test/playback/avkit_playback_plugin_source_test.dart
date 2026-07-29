import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AVKit emits explicit nulls only for included track selections', () {
    final source = File(
      'ios/Runner/AvKitPlaybackPlugin.swift',
    ).readAsStringSync();

    expect(
      source,
      contains(
        'if includeSelectedAudioTrackId { event["selectedAudioTrackId"] = selectedAudioTrackId ?? NSNull() }',
      ),
    );
    expect(
      source,
      contains(
        'if includeSelectedSubtitleTrackId { event["selectedSubtitleTrackId"] = selectedSubtitleTrackId ?? NSNull() }',
      ),
    );
    expect(source, contains('includeSelectedAudioTrackId: Bool = false'));
    expect(source, contains('includeSelectedSubtitleTrackId: Bool = false'));
    expect(source, contains('if let a  = audioTracks'));
    expect(source, contains('event["audioTracks"] = a'));
    expect(source, contains('if let st = subtitleTracks'));
    expect(source, contains('event["subtitleTracks"] = st'));
  });
}
