// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class ResumeService {
  ResumeService({
    Map<String, Object?>? memory,
    PersistentJsonStore? store,
    this.promptThreshold = const Duration(seconds: 30),
  }) : _memory = memory ?? <String, Object?>{},
       _store = store;

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;
  final Duration promptThreshold;

  Future<bool> save(
    Progress progress, {
    bool Function()? shouldCommit,
  }) async {
    final key = _keyForProgress(progress);
    if (shouldCommit != null) {
      final store = _store;
      if (store != null &&
          !await store.writeIf(key, progress.toJson(), shouldCommit)) {
        return false;
      }
      if (!shouldCommit()) return false;
      _memory[key] = progress;
      return true;
    }
    _memory[key] = progress;
    await _store?.write(key, progress.toJson());
    return true;
  }

  Future<Progress?> load(
    String viewerId,
    ContentType contentType,
    int streamId,
  ) async {
    final key = _key(viewerId, contentType, streamId);
    final raw = _store == null ? _memory[key] : await _store.read(key);
    if (raw is Progress) return raw;
    if (raw is Map) return Progress.fromJson(raw.cast<String, Object?>());
    return null;
  }

  Future<List<Progress>> all(String viewerId) async {
    final values = _store == null
        ? _memory.values
        : (await _store.snapshot()).values;
    return values
        .map(_progressFromStored)
        .whereType<Progress>()
        .where((progress) => progress.viewerId == viewerId)
        .toList(growable: false);
  }

  /// The last Continue Watching list stored by [saveRecent], in display
  /// order, or null if none has been stored for [viewerId] yet (e.g. first
  /// launch after upgrading - callers fall back to [all]). Each entry is
  /// overlaid with its resume entry, which playback keeps more current than
  /// the list itself.
  Future<List<Progress>?> recent(String viewerId) async {
    final values = _store == null ? _memory : await _store.snapshot();
    final raw = values[_recentKey(viewerId)];
    if (raw is! List) return null;
    return raw
        .map(_progressFromStored)
        .whereType<Progress>()
        .map(
          (p) => p.upNext
              ? p
              : _progressFromStored(values[_keyForProgress(p)]) ?? p,
        )
        .toList(growable: false);
  }

  /// Stores [progress] as [viewerId]'s Continue Watching list, so a cold
  /// start paints what the server last said instead of every entry ever
  /// saved. With [prune] (only for an authoritative server list), also drops
  /// [viewerId]'s resume entries the list no longer contains - e.g. copies
  /// left under an old stream_id after a media-server library flush, which
  /// would otherwise sit in the store forever.
  Future<bool> saveRecent(
    String viewerId,
    List<Progress> progress, {
    bool prune = false,
    bool Function()? shouldCommit,
  }) async {
    final recentKey = _recentKey(viewerId);
    final resumePrefix = 'm3ue_resume_${viewerId}_';
    final replacement = <String, Object?>{
      recentKey: [for (final p in progress) p.toJson()],
      if (prune)
        for (final p in progress)
          // Synthetic "up next" rows are never resume entries (see
          // AppStateController._loadRecentlyWatched).
          if (!p.upNext) _keyForProgress(p): p.toJson(),
    };
    bool replaced(String key) =>
        key == recentKey || (prune && key.startsWith(resumePrefix));
    final store = _store;
    if (store != null) {
      if (shouldCommit == null) {
        await store.replaceWhere(replaced, replacement);
      } else if (!await store.replaceWhereIf(
        replaced,
        replacement,
        shouldCommit,
      )) {
        return false;
      }
    }
    if (shouldCommit != null && !shouldCommit()) return false;
    _memory
      ..removeWhere((key, _) => replaced(key))
      ..addAll({
        for (final entry in replacement.entries)
          entry.key: entry.key == recentKey
              ? entry.value
              : Progress.fromJson(entry.value! as Map<String, Object?>),
      });
    return true;
  }

  /// Drops [progress]'s resume entry.
  Future<void> remove(Progress progress) async {
    final key = _keyForProgress(progress);
    _memory.remove(key);
    await _store?.delete(key);
  }

  Future<bool> shouldPromptResume(
    String viewerId,
    ContentType contentType,
    int streamId,
  ) async {
    final progress = await load(viewerId, contentType, streamId);
    return progress != null &&
        !progress.completed &&
        progress.positionSeconds >= promptThreshold.inSeconds;
  }

  String _keyForProgress(Progress progress) =>
      progress.contentType == ContentType.aiostreams &&
          progress.aioItemId != null
      ? 'm3ue_resume_${progress.viewerId}_aiostreams_${progress.aioItemId}'
      : 'm3ue_resume_${progress.viewerId}_${progress.contentType.wireName}_${progress.streamId}';

  String _recentKey(String viewerId) => 'm3ue_recent_watched_$viewerId';

  String _key(String viewerId, ContentType contentType, int streamId) =>
      'm3ue_resume_${viewerId}_${contentType.wireName}_$streamId';

  Progress? _progressFromStored(Object? raw) {
    if (raw is Progress) return raw;
    if (raw is Map) return Progress.fromJson(raw.cast<String, Object?>());
    return null;
  }
}
