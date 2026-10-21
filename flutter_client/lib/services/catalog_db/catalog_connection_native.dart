import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

QueryExecutor openInMemoryCatalog() => NativeDatabase.memory();

QueryExecutor openCatalogFile(Directory directory, String fileName) {
  final file = File(p.join(directory.path, fileName));
  return NativeDatabase.createInBackground(
    file,
    setup: (db) {
      db
        ..execute('PRAGMA journal_mode=WAL')
        ..execute('PRAGMA synchronous=NORMAL');
    },
  );
}

QueryExecutor openBrowserCatalog(String name) =>
    throw UnsupportedError('A browser catalog database needs a web build.');
