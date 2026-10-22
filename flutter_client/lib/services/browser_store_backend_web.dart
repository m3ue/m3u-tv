import 'dart:convert';

import 'package:m3u_tv/services/store_backend.dart';
import 'package:web/web.dart' as web;

StoreBackend browserStoreBackend(String name) => _LocalStorageBackend(name);

/// One localStorage entry per store. A single setItem is already atomic, so
/// staging is just bytes held until commit. localStorage is capped at a few
/// MB per origin, which these stores fit comfortably now that the catalog
/// lives in SQLite.
class _LocalStorageBackend implements StoreBackend {
  _LocalStorageBackend(String name) : _key = 'm3u_tv/$name';

  final String _key;
  List<int>? _staged;

  web.Storage get _storage => web.window.localStorage;

  @override
  String get identity => 'localStorage:$_key';

  @override
  Future<bool> exists() async => _storage.getItem(_key) != null;

  @override
  Future<List<int>> readAsBytes() async => utf8.encode(await readAsString());

  @override
  Future<String> readAsString() async => _storage.getItem(_key) ?? '';

  @override
  Future<void> delete() async => _storage.removeItem(_key);

  @override
  Future<void> writeStaging(List<int> bytes) async => _staged = bytes;

  @override
  Future<void> commitStaging() async {
    final staged = _staged;
    if (staged == null) throw StateError('Nothing staged for $_key');
    _storage.setItem(_key, utf8.decode(staged));
    _staged = null;
  }

  @override
  Future<void> deleteStaging() async => _staged = null;
}
