import 'dart:convert';

import 'package:m3u_tv/playback/player_adapter.dart';

/// Builds a [PlaybackSeekWindow] from an mpv core's `seekWindow` response,
/// which carries mpv's `demuxer-cache-state` property read as a string (mpv
/// formats it as JSON). Its `seekable-ranges` use the same clock as
/// `time-pos`, and mpv seeks inside them from its cache even when the stream
/// itself can't seek. Null when the response carries no cache state.
PlaybackSeekWindow? mpvSeekWindow(Map<String, Object?>? response) {
  final cacheState = response?['cacheState'];
  if (cacheState is! String || cacheState.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(cacheState);
  } on FormatException {
    return null;
  }
  final ranges = decoded is Map ? decoded['seekable-ranges'] : null;
  return PlaybackSeekWindow([
    if (ranges is List)
      for (final range in ranges)
        if (range is Map && range['start'] is num && range['end'] is num)
          (
            start: _seconds(range['start'] as num),
            end: _seconds(range['end'] as num),
          ),
  ]);
}

Duration _seconds(num seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());
