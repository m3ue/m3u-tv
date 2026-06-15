import 'dart:convert';
import 'dart:io';

class PersistentJsonStore {
  PersistentJsonStore({File? file}) : _file = file ?? File(_defaultPath());

  final File _file;
  Map<String, Object?>? _cache;

  Future<Object?> read(String key) async {
    final data = await _readAll();
    return data[key];
  }

  Future<void> write(String key, Object? value) async {
    final data = await _readAll();
    data[key] = value;
    await _writeAll(data);
  }

  Future<void> delete(String key) async {
    final data = await _readAll();
    data.remove(key);
    await _writeAll(data);
  }

  Future<Map<String, Object?>> snapshot() async {
    return Map<String, Object?>.from(await _readAll());
  }

  Future<void> removeWhere(bool Function(String key) test) async {
    final data = await _readAll();
    data.removeWhere((key, value) => test(key));
    await _writeAll(data);
  }

  Future<Map<String, Object?>> _readAll() async {
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
    if (await _file.exists()) {
      await _file.delete();
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
