import 'dart:async';

import 'package:drift/drift.dart';

/// Runs once before any test in this suite.
///
/// Every test that builds an AppStateController / CacheService without
/// injecting a catalog store gets its own private in-memory CatalogDatabase,
/// so a single test process legitimately holds many of them at once. drift's
/// debug-build guard assumes a second instance means an accidental duplicate
/// sharing one executor and prints a multi-line warning + stack trace for each
/// one; silence it here since these databases are fully isolated.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
