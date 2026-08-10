import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/async_lifecycle.dart';

class PersistentJsonStore {
  PersistentJsonStore({File? file}) : this._(file ?? File(_defaultPath()));

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
    final candidateBytes = utf8.encode(jsonEncode(data));
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
            : (jsonDecode(utf8.decode(currentBytes)) as Map)
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
    final decoded = jsonDecode(text);
    _cache = decoded is Map
        ? decoded.cast<String, Object?>()
        : <String, Object?>{};
    return _cache!;
  }

  Future<void> _writeAll(Map<String, Object?> data) async {
    await _writeStaging(utf8.encode(jsonEncode(data)));
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

  static String _defaultPath() {
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
    return '$base/m3u_tv/app_state.json';
  }
}

class _PersistentJsonStoreState {
  Map<String, Object?>? cache;
  final SerialQueue writeQueue = SerialQueue();
}
