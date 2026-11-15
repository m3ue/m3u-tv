// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

/// Audio and subtitle sync offsets. Positive delays the audio or subtitles,
/// negative plays them earlier, matching mpv's `audio-delay`/`sub-delay`.
typedef SyncOffsets = ({Duration audio, Duration subtitle});

const SyncOffsets zeroSyncOffsets = (
  audio: Duration.zero,
  subtitle: Duration.zero,
);

/// What an offset is remembered for: the live channel (catch-up included,
/// it's the same channel's stream), the movie, or the series (every episode
/// shares one). Null when the content has no id to remember it by.
String? syncOffsetKeyFor({
  required String type,
  int? streamId,
  int? seriesId,
}) {
  switch (type) {
    case 'live' || 'catchup':
      return streamId == null ? null : 'live:$streamId';
    case 'series':
      if (seriesId != null) return 'series:$seriesId';
      return streamId == null ? null : 'episode:$streamId';
    case 'vod':
      return streamId == null ? null : 'vod:$streamId';
    default:
      return null;
  }
}

/// Remembers sync offsets per channel or title, on this device, separately
/// for each saved playlist (channel and title ids are per editor). Offsets
/// back at zero are dropped, so the store only holds what was changed.
class SyncOffsetStore {
  SyncOffsetStore({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_sync_offsets';

  /// Oldest entries are dropped past this, so the map can't grow forever.
  static const maxEntries = 500;

  final PersistentJsonStore? _store;
  final SerialQueue _writes = SerialQueue();

  PlaylistScope? playlistScope;

  Future<SyncOffsets> read(String key) async {
    final entry = (await _readAll(_storageKey()))[key];
    if (entry is! Map) return zeroSyncOffsets;
    return (
      audio: Duration(milliseconds: _asInt(entry['a'])),
      subtitle: Duration(milliseconds: _asInt(entry['s'])),
    );
  }

  Future<void> write(String key, SyncOffsets offsets) {
    final storageKey = _storageKey();
    return _writes.run(() async {
      final store = _store;
      if (store == null) return;
      final all = Map<String, Object?>.of(await _readAll(storageKey))
        ..remove(key);
      if (offsets.audio != Duration.zero || offsets.subtitle != Duration.zero) {
        // Re-inserted last, so the oldest entries are the first dropped.
        all[key] = <String, Object?>{
          if (offsets.audio != Duration.zero) 'a': offsets.audio.inMilliseconds,
          if (offsets.subtitle != Duration.zero)
            's': offsets.subtitle.inMilliseconds,
        };
      }
      while (all.length > maxEntries) {
        all.remove(all.keys.first);
      }
      await store.write(storageKey, all);
    });
  }

  String _storageKey() => playlistScopedKey(_storeKey, playlistScope?.call());

  Future<Map<String, Object?>> _readAll(String storageKey) async {
    final raw = await _store?.read(storageKey);
    if (raw is! Map) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static int _asInt(Object? value) => value is num ? value.toInt() : 0;
}
