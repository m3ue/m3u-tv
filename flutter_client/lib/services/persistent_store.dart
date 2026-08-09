import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/async_lifecycle.dart';

class PersistentJsonStore {
  PersistentJsonStore({File? file}) : _file = file ?? File(_defaultPath());

  final File _file;
  Map<String, Object?>? _cache;
  final SerialQueue _writeQueue = SerialQueue();

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
    final data = Map<String, Object?>.from(await _readAllUnlocked())
      ..[key] = value;
    await _writeStaging(data);
    try {
      if (!shouldCommit()) return false;
      await _commitStaging(data);
      Future<void> restorePrevious() async {
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
    await _writeStaging(data);
    try {
      await _commitStaging(data);
    } finally {
      await _deleteStaging();
    }
  }

  Future<void> _writeStaging(Map<String, Object?> data) async {
    await _file.parent.create(recursive: true);
    await _stagingFile.writeAsString(jsonEncode(data), flush: true);
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
