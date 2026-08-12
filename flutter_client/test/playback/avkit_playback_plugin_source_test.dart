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

  test('tvOS AVKit supports track discovery and selection', () {
    final source = File(
      'tvos/Runner/AvKitPlaybackPlugin.swift',
    ).readAsStringSync();

    expect(source, contains('case "setAudioTrack":'));
    expect(source, contains('case "setSubtitleTrack":'));
    expect(
      source,
      contains(
        'selectTrack(playerId: playerId, characteristic: .audible, trackId: args?["trackId"] as? String)',
      ),
    );
    expect(
      source,
      contains(
        'selectTrack(playerId: playerId, characteristic: .legible, trackId: args?["trackId"] as? String)',
      ),
    );
    expect(source, contains('group.options.enumerated().map'));
    expect(source, contains(r'"id": "\(prefix):\(index)"'));
    expect(source, contains('item.select(group.options[index], in: group)'));
    expect(source, contains('item.select(nil, in: group)'));
    expect(
      source,
      contains(
        'audioTracks: playbackTracks(playerId: playerId, characteristic: .audible)',
      ),
    );
    expect(
      source,
      contains(
        'subtitleTracks: playbackTracks(playerId: playerId, characteristic: .legible)',
      ),
    );
    expect(
      source,
      contains(
        'selectedAudioTrackId: selectedTrackId(playerId: playerId, characteristic: .audible)',
      ),
    );
    expect(
      source,
      contains(
        'selectedSubtitleTrackId: selectedTrackId(playerId: playerId, characteristic: .legible)',
      ),
    );
    expect(source, contains('includeSelectedAudioTrackId: true'));
    expect(source, contains('includeSelectedSubtitleTrackId: true'));
    expect(source, contains('includeSelectedAudioTrackId: Bool = false'));
    expect(source, contains('includeSelectedSubtitleTrackId: Bool = false'));
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
    expect(source, contains('if let a  = audioTracks'));
    expect(source, contains('event["audioTracks"] = a'));
    expect(source, contains('if let st = subtitleTracks'));
    expect(source, contains('event["subtitleTracks"] = st'));
  });

  test('tvOS AVKit keys player state by playerId for Multiview', () {
    final source = File(
      'tvos/Runner/AvKitPlaybackPlugin.swift',
    ).readAsStringSync();

    // One channel pair, several concurrent AVPlayers — every call after
    // "probe" is routed by a Dart-assigned playerId instead of a single
    // shared instance field.
    expect(
      source,
      contains('private var states: [String: _PlayerState] = [:]'),
    );
    expect(
      source,
      contains('let playerId = (args?["playerId"] as? String) ?? "default"'),
    );
    expect(source, contains('states[playerId] = playerState'));
    expect(source, contains('func releasePlayer(playerId: String)'));
    expect(
      source,
      contains(
        'guard let s = states.removeValue(forKey: playerId) else { return }',
      ),
    );
    expect(source, contains('case "setVolume":'));
    expect(source, contains('states[playerId]?.player.volume = volume'));
    expect(
      source,
      contains(
        'var event: [String: Any] = ["type": type, "backend": "appleAvKit", "playerId": playerId]',
      ),
    );
  });
}
