import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/secure_storage.dart';

/// A keychain that, like the real one, matches reads on accessibility but
/// identifies an item by its key alone.
class _FakeKeychain {
  final Map<String, ({String value, String accessibility})> items = {};

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments! as Map<Object?, Object?>;
    final key = args['key'] as String?;
    final options = args['options']! as Map<Object?, Object?>;
    final accessibility = options['accessibility'] as String? ?? 'unlocked';
    switch (call.method) {
      case 'read':
        final item = items[key];
        return item != null && item.accessibility == accessibility
            ? item.value
            : null;
      case 'containsKey':
        final item = items[key];
        return item != null && item.accessibility == accessibility;
      case 'write':
        if (items.containsKey(key) &&
            items[key]!.accessibility != accessibility) {
          throw PlatformException(code: '-25299', message: 'Duplicate item');
        }
        items[key!] = (
          value: args['value']! as String,
          accessibility: accessibility,
        );
        return null;
      case 'delete':
        items.remove(key);
        return null;
    }
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  late _FakeKeychain keychain;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    keychain = _FakeKeychain();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, keychain.handle);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('writes new items readable after first unlock', () async {
    final storage = FlutterSecureStorageAdapter(migratesToFirstUnlock: true);

    await storage.write('token', 'abc');

    expect(keychain.items['token']?.accessibility, 'first_unlock');
    expect(await storage.read('token'), 'abc');
  });

  test('moves an item saved before over on first read', () async {
    keychain.items['token'] = (value: 'abc', accessibility: 'unlocked');
    final storage = FlutterSecureStorageAdapter(migratesToFirstUnlock: true);

    expect(await storage.read('token'), 'abc');
    expect(keychain.items['token'], (
      value: 'abc',
      accessibility: 'first_unlock',
    ));
    expect(await storage.read('token'), 'abc');
  });

  test('a missing item stays missing', () async {
    final storage = FlutterSecureStorageAdapter(migratesToFirstUnlock: true);

    expect(await storage.read('token'), isNull);
    expect(keychain.items, isEmpty);
  });

  test('leaves other platforms on the default', () async {
    final storage = FlutterSecureStorageAdapter(migratesToFirstUnlock: false);

    await storage.write('token', 'abc');

    expect(keychain.items['token']?.accessibility, 'unlocked');
  });
}
