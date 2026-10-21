import 'dart:io';

/// Where a PersistentJsonStore keeps its JSON: the few operations it needs,
/// including the stage-then-commit pair that makes each write atomic.
abstract interface class StoreBackend {
  /// Keys the shared cache and write queue, so stores over the same backing
  /// data share them.
  String get identity;

  Future<bool> exists();

  Future<List<int>> readAsBytes();

  Future<String> readAsString();

  /// Removes the committed data; a no-op when there is none.
  Future<void> delete();

  Future<void> writeStaging(List<int> bytes);

  /// Replaces the committed data with the staged bytes.
  Future<void> commitStaging();

  /// Drops staged bytes that were never committed; a no-op when there are none.
  Future<void> deleteStaging();
}

/// A JSON file, written through a `.tmp` sibling and an atomic rename.
class FileStoreBackend implements StoreBackend {
  FileStoreBackend(this._file);

  final File _file;

  File get _stagingFile => File('${_file.path}.tmp');

  @override
  String get identity => _file.absolute.path;

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<List<int>> readAsBytes() => _file.readAsBytes();

  @override
  Future<String> readAsString() => _file.readAsString();

  @override
  Future<void> delete() async {
    try {
      await _file.delete();
    } on PathNotFoundException {
      // Already gone.
    }
  }

  @override
  Future<void> writeStaging(List<int> bytes) async {
    await _file.parent.create(recursive: true);
    await _stagingFile.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> commitStaging() async {
    await _stagingFile.rename(_file.path);
  }

  @override
  Future<void> deleteStaging() async {
    try {
      await _stagingFile.delete();
    } on PathNotFoundException {
      // A successful rename already consumed the staging file.
    }
  }
}
