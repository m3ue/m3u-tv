import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Runs once before any test in this suite.
///
/// Every test that builds an AppStateController / CacheService without
/// injecting a catalog store gets its own private in-memory CatalogDatabase,
/// so a single test process legitimately holds many of them at once. drift's
/// debug-build guard assumes a second instance means an accidental duplicate
/// sharing one executor and prints a multi-line warning + stack trace for each
/// one; silence it here since these databases are fully isolated.
///
/// Default-constructed PersistentJsonStores (any AppStateController built
/// without a `persistentStore`) write into a private temp directory per test
/// process instead of the real app-data directory, which parallel test
/// processes would otherwise race on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final appDataDir = Directory.systemTemp.createTempSync('m3u_tv_test_');
  PersistentJsonStore.debugDirectoryOverride = appDataDir.path;
  // testMain() only declares the tests; they run after it returns.
  tearDownAll(() {
    try {
      appDataDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Best effort: a late background write may still hold a file.
    }
  });
  await testMain();
}
