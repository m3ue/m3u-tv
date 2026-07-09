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

  Future<void> save(Progress progress) async {
    final key = _keyForProgress(progress);
    _memory[key] = progress;
    await _store?.write(key, progress.toJson());
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

  String _key(String viewerId, ContentType contentType, int streamId) =>
      'm3ue_resume_${viewerId}_${contentType.wireName}_$streamId';

  Progress? _progressFromStored(Object? raw) {
    if (raw is Progress) return raw;
    if (raw is Map) return Progress.fromJson(raw.cast<String, Object?>());
    return null;
  }
}
