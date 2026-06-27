import 'dart:convert';
import 'dart:io';

class PersistentJsonStore {
  PersistentJsonStore({File? file}) : _file = file ?? File(_defaultPath());

  final File _file;
  Map<String, Object?>? _cache;
  Future<void> _pendingWrite = Future<void>.value();

  Future<Object?> read(String key) async {
    await _pendingWrite;
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

  Future<void> delete(String key) async {
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data.remove(key);
      await _writeAll(data);
    });
  }

  Future<Map<String, Object?>> snapshot() async {
    await _pendingWrite;
    return Map<String, Object?>.from(await _readAllUnlocked());
  }

  Future<void> removeWhere(bool Function(String key) test) async {
    await _queueWrite(() async {
      final data = await _readAllUnlocked();
      data.removeWhere((key, value) => test(key));
      await _writeAll(data);
    });
  }

  Future<void> _queueWrite(Future<void> Function() operation) {
    final previous = _pendingWrite;
    final next = previous.then((_) => operation(), onError: (_) => operation());
    _pendingWrite = next.catchError((_) {});
    return next;
  }

  Future<Map<String, Object?>> _readAllUnlocked() async {
    final cached = _cache;
    if (cached != null) return cached;
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
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(data), flush: true);
    try {
      await _file.delete();
    } on PathNotFoundException {
      // File may not exist yet or was already removed by a concurrent write.
    }
    await temp.rename(_file.path);
    _cache = data;
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
