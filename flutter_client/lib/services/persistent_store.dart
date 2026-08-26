import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/json_isolate.dart';

class PersistentJsonStore {
  /// [fileName] picks the basename inside the platform app-data directory
  /// (default `app_state.json`). Pass a distinct name (e.g. `cache.json`) to
  /// keep a large, frequently-rewritten section in its own file so an
  /// unrelated single-key write does not re-serialize it. Ignored when an
  /// explicit [file] is given (tests).
  PersistentJsonStore({File? file, String fileName = 'app_state.json'})
    : this._(file ?? File(_defaultPath(fileName)));

  PersistentJsonStore._(File file)
    : _file = file,
      _state = _states.putIfAbsent(
        file.absolute.path,
        _PersistentJsonStoreState.new,
      );

  final File _file;
  final _PersistentJsonStoreState _state;
  static final Map<String, _PersistentJsonStoreState> _states = {};

  Map<String, Object?>? get _cache => _state.cache;
  set _cache(Map<String, Object?>? value) => _state.cache = value;
  SerialQueue get _writeQueue => _state.writeQueue;

  Future<Object?> read(String key) async {
    await _writeQueue.drained;
    final data = await _readAllUnlocked();
    return data[key];
  }

  Future<void> write(String key, Object? value) async {
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data[key] = value;
      await _writeAll(data);
    });
  }

  Future<bool> writeIf(
    String key,
    Object? value,
    bool Function() shouldCommit,
  ) => _writeQueue.run(() async {
    if (!shouldCommit()) return false;
    final previousCache = _cache;
    final previousBytes = await _file.exists()
        ? await _file.readAsBytes()
        : null;
    final previous = Map<String, Object?>.from(await _readAllUnlocked());
    final hadPreviousValue = previous.containsKey(key);
    final previousValue = previous[key];
    final data = Map<String, Object?>.from(previous)..[key] = value;
    // Encode off the calling isolate for large maps, same as [_writeAll]. This
    // store is shared with the content cache, so a single-key write (e.g. the
    // resume tracker every ~10s during playback) would otherwise re-serialize
    // the entire channel/VOD/series catalog on the UI isolate and drop frames.
    // The catalog lives in a handful of huge keys, so force the offload off
    // the file size rather than the (low) top-level key count.
    final candidateBytes = utf8.encode(
      await encodeJsonOffMainIsolate(
        data,
        forceOffload: (previousBytes?.length ?? 0) >= 32 * 1024,
      ),
    );
    await _writeStaging(candidateBytes);
    try {
      if (!shouldCommit()) return false;
      await _commitStaging(data);
      Future<void> restorePrevious() async {
        final currentBytes = await _file.exists()
            ? await _file.readAsBytes()
            : null;
        if (_sameBytes(currentBytes, candidateBytes)) {
          _cache = previousCache;
          if (previousBytes == null) {
            try {
              await _file.delete();
            } on PathNotFoundException {
              return;
            }
          } else {
            await _stagingFile.writeAsBytes(previousBytes, flush: true);
            await _stagingFile.rename(_file.path);
          }
          return;
        }

        final current = currentBytes == null || currentBytes.isEmpty
            ? <String, Object?>{}
            : ((await decodeJsonOffMainIsolate(utf8.decode(currentBytes)))!
                      as Map)
                  .cast<String, Object?>();
        if (hadPreviousValue) {
          current[key] = previousValue;
        } else {
          current.remove(key);
        }
        if (current.isEmpty && previousBytes == null) {
          _cache = current;
          try {
            await _file.delete();
          } on PathNotFoundException {
            return;
          }
        } else {
          await _writeAll(current);
        }
      }

      bool stillOwnsCommit;
      try {
        stillOwnsCommit = shouldCommit();
      } catch (_) {
        await restorePrevious();
        rethrow;
      }
      if (!stillOwnsCommit) {
        await restorePrevious();
        return false;
      }
      return true;
    } finally {
      await _deleteStaging();
    }
  });

  Future<void> delete(String key) async {
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data.remove(key);
      await _writeAll(data);
    });
  }

  Future<Map<String, Object?>> snapshot() async {
    await _writeQueue.drained;
    return Map<String, Object?>.from(await _readAllUnlocked());
  }

  /// One-time move of keys matching [test] out of [source] and into this
  /// store, run on boot. Writes here first, then clears [source]. It is
  /// idempotent: once this store holds the keys, later calls only sweep any
  /// copy still left in [source] - e.g. from a crash between the two writes,
  /// or from [source] being reseeded - so the large payload can never linger
  /// there (which would defeat the point of the split).
  Future<void> adoptKeysFrom(
    PersistentJsonStore source,
    bool Function(String key) test,
  ) async {
    // Distinct instances can share one file, and its cache + write queue, via
    // the static _states map; a shared state means there is nothing to move.
    if (identical(_state, source._state)) return;
    await _writeQueue.drained;
    final existing = await _readAllUnlocked();
    if (existing.keys.any(test)) {
      // Destination already migrated. Only rewrite the source if an earlier
      // run left matching keys behind - otherwise every boot would rewrite
      // app_state.json for nothing.
      if ((await source.snapshot()).keys.any(test)) {
        await source.removeWhere(test);
      }
      return;
    }
    final sourceData = await source.snapshot();
    final migrated = <String, Object?>{
      for (final entry in sourceData.entries)
        if (test(entry.key)) entry.key: entry.value,
    };
    if (migrated.isEmpty) return;
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data.addAll(migrated);
      await _writeAll(data);
    });
    await source.removeWhere(test);
  }

  Future<void> removeWhere(bool Function(String key) test) async {
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data.removeWhere((key, value) => test(key));
      await _writeAll(data);
    });
  }

  Future<void> replaceWhere(
    bool Function(String key) test,
    Map<String, Object?> replacement,
  ) async {
    await _queueWrite(() async {
      final data = Map<String, Object?>.from(await _readAllUnlocked())
        ..removeWhere((key, value) => test(key))
        ..addAll(replacement);
      await _writeAll(data);
    });
  }

  Future<void> _queueWrite(Future<void> Function() operation) =>
      _writeQueue.run(operation);

  Future<Map<String, Object?>> _readAllUnlocked() async {
    final cached = _cache;
    if (cached != null) return cached;
    await _deleteStaging();
    if (!await _file.exists()) {
      _cache = <String, Object?>{};
      return _cache!;
    }
    final text = await _file.readAsString();
    if (text.trim().isEmpty) {
      _cache = <String, Object?>{};
      return _cache!;
    }
    final decoded = await decodeJsonOffMainIsolate(text);
    _cache = decoded is Map
        ? decoded.cast<String, Object?>()
        : <String, Object?>{};
    return _cache!;
  }

  Future<void> _writeAll(Map<String, Object?> data) async {
    await _writeStaging(utf8.encode(await encodeJsonOffMainIsolate(data)));
    try {
      await _commitStaging(data);
    } finally {
      await _deleteStaging();
    }
  }

  Future<void> _writeStaging(List<int> bytes) async {
    await _file.parent.create(recursive: true);
    await _stagingFile.writeAsBytes(bytes, flush: true);
  }

  Future<void> _commitStaging(Map<String, Object?> data) async {
    await _stagingFile.rename(_file.path);
    _cache = data;
  }

  Future<void> _deleteStaging() async {
    try {
      await _stagingFile.delete();
    } on PathNotFoundException {
      // A successful rename already consumed the staging file.
    }
  }

  File get _stagingFile => File('${_file.path}.tmp');

  static bool _sameBytes(List<int>? first, List<int> second) {
    if (first == null || first.length != second.length) return false;
    for (var index = 0; index < first.length; index += 1) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  static String _defaultPath(String fileName) {
    final env = Platform.environment;
    final base = switch (Platform.operatingSystem) {
      'windows' =>
        env['APPDATA'] ?? env['LOCALAPPDATA'] ?? Directory.systemTemp.path,
      'macos' =>
        '${env['HOME'] ?? Directory.systemTemp.path}/Library/Application Support',
      'linux' =>
        env['XDG_DATA_HOME'] ??
            '${env['HOME'] ?? Directory.systemTemp.path}/.local/share',
      _ => '${env['HOME'] ?? Directory.systemTemp.path}/.m3u_tv',
    };
    return '$base/m3u_tv/$fileName';
  }
}

class _PersistentJsonStoreState {
  Map<String, Object?>? cache;
  final SerialQueue writeQueue = SerialQueue();
}
