import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/simkl_service.dart';
import 'package:m3u_tv/services/trakt_service.dart';

String _futureExpiry() =>
    '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}';

void main() {
  group('Trakt account name', () {
    Future<InMemorySecureStorage> signedIn() async {
      final storage = InMemorySecureStorage();
      await storage.write('trakt_access_token', 'trakt-at');
      await storage.write('trakt_refresh_token', 'trakt-rt');
      await storage.write('trakt_token_expiry', _futureExpiry());
      return storage;
    }

    test('an existing sign-in looks its name up once and keeps it', () async {
      final storage = await signedIn();
      final tokens = <String>[];
      final service = TraktService(
        storage: storage,
        clientId: 'client',
        transport: (_) async => const TraktResponse(200, {}),
        accountNameLookup: (token) async {
          tokens.add(token);
          return 'couchpotato';
        },
      );
      addTearDown(service.dispose);

      await service.init();
      await pumpEventQueue();

      expect(service.accountName, 'couchpotato');
      expect(tokens, ['trakt-at']);
      expect(await storage.read('trakt_account_name'), 'couchpotato');

      final restarted = TraktService(
        storage: storage,
        clientId: 'client',
        transport: (_) async => const TraktResponse(200, {}),
        accountNameLookup: (token) async {
          tokens.add(token);
          return 'other';
        },
      );
      addTearDown(restarted.dispose);
      await restarted.init();
      await pumpEventQueue();

      expect(restarted.accountName, 'couchpotato');
      expect(tokens, hasLength(1));
    });

    test('disconnecting forgets the name', () async {
      final storage = await signedIn();
      final service = TraktService(
        storage: storage,
        clientId: 'client',
        transport: (_) async => const TraktResponse(200, {}),
        accountNameLookup: (_) async => 'couchpotato',
      );
      addTearDown(service.dispose);
      await service.init();
      await pumpEventQueue();

      await service.disconnect();

      expect(service.accountName, isNull);
      expect(await storage.read('trakt_account_name'), isNull);
    });

    test('a failed lookup stays connected without a name', () async {
      final service = TraktService(
        storage: await signedIn(),
        clientId: 'client',
        transport: (_) async => const TraktResponse(200, {}),
        accountNameLookup: (_) async => throw Exception('offline'),
      );
      addTearDown(service.dispose);

      await service.init();
      await pumpEventQueue();

      expect(service.isConnected, isTrue);
      expect(service.accountName, isNull);
    });
  });

  group('Simkl account name', () {
    test('an existing sign-in looks its name up on start', () async {
      final storage = InMemorySecureStorage();
      await storage.write('simkl_access_token', 'simkl-at');
      await storage.write('simkl_refresh_token', 'simkl-rt');
      await storage.write('simkl_token_expiry', _futureExpiry());
      final service = SimklService(
        storage: storage,
        clientId: 'client',
        transport: (_) async => const SimklResponse(200, {}),
        appVersionResolver: () async => '1.0',
        accountNameLookup: (token) async =>
            token == 'simkl-at' ? 'jane_doe' : null,
      );
      addTearDown(service.dispose);

      await service.init();
      await pumpEventQueue();

      expect(service.accountName, 'jane_doe');
      expect(await storage.read('simkl_account_name'), 'jane_doe');

      await service.disconnect();

      expect(service.accountName, isNull);
      expect(await storage.read('simkl_account_name'), isNull);
    });
  });
}
