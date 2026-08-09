import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ownership loss during commit restores existing state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-write-if-commit-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final store = PersistentJsonStore(file: stateFile);
    await stateFile.writeAsString('{\n  "owner": "account-a"\n}\n');
    expect(await store.read('owner'), 'account-a');
    final previousBytes = await stateFile.readAsBytes();
    var current = true;
    var ownershipChecks = 0;

    final accepted = await store.writeIf('owner', 'account-b', () {
      ownershipChecks += 1;
      if (ownershipChecks == 2) {
        scheduleMicrotask(() => current = false);
      }
      return current;
    });

    expect(
      (accepted: accepted, current: current, cached: await store.read('owner')),
      (accepted: false, current: false, cached: 'account-a'),
    );
    expect(await stateFile.readAsBytes(), previousBytes);
  });

  test('ownership loss during first commit restores file absence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-write-if-first-commit-rollback-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final store = PersistentJsonStore(file: stateFile);
    var current = true;
    var ownershipChecks = 0;

    final accepted = await store.writeIf('owner', 'account-b', () {
      ownershipChecks += 1;
      if (ownershipChecks == 2) {
        scheduleMicrotask(() => current = false);
      }
      return current;
    });

    expect(
      (
        accepted: accepted,
        current: current,
        cached: await store.read('owner'),
        fileExists: await stateFile.exists(),
      ),
      (accepted: false, current: false, cached: null, fileExists: false),
    );
  });

  test('stale rollback preserves an unrelated concurrent commit', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-write-if-concurrent-commit-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final store = PersistentJsonStore(file: stateFile);
    await store.write('owner', 'account-a');
    var ownershipChecks = 0;

    final accepted = await store.writeIf('owner', 'account-b', () {
      ownershipChecks += 1;
      if (ownershipChecks < 3) return true;
      final concurrent = (jsonDecode(stateFile.readAsStringSync()) as Map)
          .cast<String, Object?>();
      concurrent['account-a-notification'] = 'read';
      stateFile.writeAsStringSync(jsonEncode(concurrent), flush: true);
      return false;
    });

    expect(accepted, isFalse);
    expect(
      await PersistentJsonStore(file: stateFile).snapshot(),
      <String, Object?>{
        'owner': 'account-a',
        'account-a-notification': 'read',
      },
    );
  });

  test('same-file instances preserve each other writes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-same-file-stores-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final first = PersistentJsonStore(file: stateFile);
    final second = PersistentJsonStore(file: stateFile);
    expect(await second.snapshot(), isEmpty);

    await first.write('account-a-notification', 'read');
    await second.write('account-a-channels', <String>['dvr']);

    expect(
      await PersistentJsonStore(file: stateFile).snapshot(),
      <String, Object?>{
        'account-a-notification': 'read',
        'account-a-channels': <Object?>['dvr'],
      },
    );
  });

  test('rejected writeIf never publishes candidate bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-write-if-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final stagingFile = File('${stateFile.path}.tmp');
    final store = PersistentJsonStore(file: stateFile);
    await store.write('notification', <String, Object?>{
      'owner': 'source-a',
      'body': 'source-a private message',
    });
    var ownershipChecks = 0;

    final accepted = await store.writeIf(
      'notification',
      <String, Object?>{
        'owner': 'source-b',
        'body': 'source-b private message',
      },
      () {
        ownershipChecks += 1;
        if (ownershipChecks == 2) {
          final primary = (jsonDecode(stateFile.readAsStringSync()) as Map)
              .cast<String, Object?>();
          expect((primary['notification']! as Map)['owner'], 'source-a');
          expect(
            (jsonDecode(stagingFile.readAsStringSync()) as Map)['notification'],
            containsPair('owner', 'source-b'),
          );
          return false;
        }
        return true;
      },
    );

    expect(accepted, isFalse);
    final restored = await store.read('notification');
    expect((restored! as Map)['owner'], 'source-a');
    expect(await stagingFile.exists(), isFalse);
  });

  test(
    'ownership check failure leaves the durable primary unchanged',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'm3u-tv-write-if-failure-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stateFile = File('${directory.path}/app_state.json');
      final stagingFile = File('${stateFile.path}.tmp');
      final store = PersistentJsonStore(file: stateFile);
      await store.write('owner', 'source-a');
      var ownershipChecks = 0;

      await expectLater(
        store.writeIf('owner', 'source-b', () {
          ownershipChecks += 1;
          if (ownershipChecks == 2) {
            expect(
              (jsonDecode(stateFile.readAsStringSync()) as Map)['owner'],
              'source-a',
            );
            expect(
              (jsonDecode(stagingFile.readAsStringSync()) as Map)['owner'],
              'source-b',
            );
            throw StateError('injected commit-boundary failure');
          }
          return true;
        }),
        throwsStateError,
      );

      expect(await store.read('owner'), 'source-a');
      expect(
        (jsonDecode(await stateFile.readAsString()) as Map)['owner'],
        'source-a',
      );
      expect(await stagingFile.exists(), isFalse);
    },
  );

  test('startup discards an abandoned staging candidate', () async {
    final directory = await Directory.systemTemp.createTemp(
      'm3u-tv-write-if-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File('${directory.path}/app_state.json');
    final stagingFile = File('${stateFile.path}.tmp');
    await stateFile.writeAsString(
      jsonEncode(<String, Object?>{
        'owner': 'source-a',
      }),
    );
    await stagingFile.writeAsString(
      jsonEncode(<String, Object?>{
        'owner': 'source-b',
      }),
    );

    final restarted = PersistentJsonStore(file: stateFile);

    expect(await restarted.read('owner'), 'source-a');
    expect(await stagingFile.exists(), isFalse);
  });
}
