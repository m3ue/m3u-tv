import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  test(
    'stale delayed credential write cannot overwrite the current session',
    () async {
      final storage = _DelayedFirstWriteStorage();
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _authenticate),
        secureStorage: storage,
      );
      const sourceA = UserCredentials(
        server: 'https://source-a.invalid',
        username: 'source-a',
        password: 'private-a',
      );
      const sourceB = UserCredentials(
        server: 'https://source-b.invalid',
        username: 'source-b',
        password: 'private-b',
      );

      final connectA = notifier.connect(sourceA);
      await storage.firstWriteStarted.future;
      final connectB = notifier.connect(sourceB);
      await Future<void>.delayed(Duration.zero);
      storage.releaseFirstWrite.complete();

      expect(await connectA, isFalse);
      expect(await connectB, isTrue);
      expect(notifier.credentials, sourceB);
      expect(
        jsonDecode((await storage.read('m3ue_tv_credentials'))!),
        <String, Object?>{
          'server': sourceB.server,
          'username': sourceB.username,
          'password': sourceB.password,
        },
      );
    },
  );

  test(
    'connect resolves a bare-host server to an absolute URL',
    () async {
      final storage = _DelayedFirstWriteStorage()..releaseFirstWrite.complete();
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _authenticate),
        secureStorage: storage,
      );

      // Regression: a bare host used to reach the notification owner key and
      // Reverb config unresolved, so `Uri.parse` produced no host and the
      // socket silently never connected.
      final connected = await notifier.connect(
        const UserCredentials(
          server: 'm3ueditor.test',
          username: 'user1',
          password: 'pass1',
        ),
      );

      expect(connected, isTrue);
      expect(notifier.credentials?.server, 'http://m3ueditor.test');
      expect(
        jsonDecode((await storage.read('m3ue_tv_credentials'))!),
        containsPair('server', 'http://m3ueditor.test'),
      );
    },
  );
}

Future<Object?> _authenticate(XtreamRequest request) async => <String, Object?>{
  'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
  'm3u_editor': <String, Object?>{'version': '0.10.0'},
};

class _DelayedFirstWriteStorage implements SecureStorage {
  final firstWriteStarted = Completer<void>();
  final releaseFirstWrite = Completer<void>();
  final _values = <String, String>{};
  var _shouldDelay = true;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (_shouldDelay) {
      _shouldDelay = false;
      firstWriteStarted.complete();
      await releaseFirstWrite.future;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
