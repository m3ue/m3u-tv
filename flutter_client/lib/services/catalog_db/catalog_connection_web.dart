import 'dart:io' show Directory;

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart' as web;

// Both files must be in web/, matching the drift and sqlite3 versions in
// pubspec.lock; scripts/fetch-web-assets.sh downloads them.
Uri _asset(String name) => Uri.parse(web.document.baseURI).resolve(name);

Future<DatabaseConnection> _open(
  Future<DatabaseConnection> Function() open,
) async {
  try {
    return await open();
  } on Object catch (error) {
    throw StateError(
      'Could not start the web SQLite runtime ($error). Run '
      'scripts/fetch-web-assets.sh so web/sqlite3.wasm and '
      'web/drift_worker.js exist, then rebuild.',
    );
  }
}

QueryExecutor openInMemoryCatalog() => DatabaseConnection.delayed(
  _open(() async {
    final sqlite3 = await WasmSqlite3.loadFromUrl(_asset('sqlite3.wasm'));
    sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
    return DatabaseConnection(WasmDatabase.inMemory(sqlite3));
  }),
);

QueryExecutor openCatalogFile(Directory directory, String fileName) =>
    throw UnsupportedError('Use openBrowserCatalog on the web.');

/// Persists in the browser's origin-private file system or IndexedDB,
/// whichever drift finds usable.
QueryExecutor openBrowserCatalog(String name) => DatabaseConnection.delayed(
  _open(() async {
    final result = await WasmDatabase.open(
      databaseName: name,
      sqlite3Uri: _asset('sqlite3.wasm'),
      driftWorkerUri: _asset('drift_worker.js'),
    );
    debugPrint(
      '[Catalog] web storage: ${result.chosenImplementation}'
      '${result.missingFeatures.isEmpty ? '' : ' (missing ${result.missingFeatures})'}',
    );
    return result.resolvedExecutor;
  }),
);
