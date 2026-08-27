import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/device_identity_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

void main() {
  DeviceIdentityService build(
    SecureStorage storage, {
    DeviceMetaResolver? metaResolver,
    Future<String?> Function()? appVersionResolver,
  }) => DeviceIdentityService(
    storage: storage,
    metaResolver:
        metaResolver ??
        () async => const DeviceMeta(platform: 'ios', name: "Shaun's iPhone"),
    appVersionResolver: appVersionResolver ?? () async => '1.1.2',
  );

  test('generates a device id once and persists it', () async {
    final storage = InMemorySecureStorage();
    final service = build(storage);

    final first = await service.deviceId();
    final second = await service.deviceId();

    expect(first, isNotEmpty);
    expect(first, second);
    expect(await storage.read('m3u_tv_device_id'), first);

    // A fresh service instance reads the same persisted id.
    expect(await build(storage).deviceId(), first);
  });

  test('generates a syntactically valid v4 uuid', () async {
    final id = await build(InMemorySecureStorage()).deviceId();

    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
      reason: id,
    );
  });

  test('resolve() bundles id, name, platform and app version', () async {
    final identity = await build(InMemorySecureStorage()).resolve();

    expect(identity.deviceName, "Shaun's iPhone");
    expect(identity.platform, 'ios');
    expect(identity.appVersion, '1.1.2');
    expect(identity.toQueryParams(), {
      'device_id': identity.deviceId,
      'platform': 'ios',
      'device_name': "Shaun's iPhone",
      'app_version': '1.1.2',
    });
  });

  test('resolve() still succeeds when metadata resolution throws', () async {
    final service = build(
      InMemorySecureStorage(),
      metaResolver: () async => throw Exception('no plugin'),
      appVersionResolver: () async => throw Exception('no asset'),
    );

    final identity = await service.resolve();

    expect(identity.deviceId, isNotEmpty);
    expect(identity.platform, 'unknown');
    expect(identity.deviceName, isNull);
    expect(identity.appVersion, isNull);
    expect(identity.toQueryParams().containsKey('device_name'), isFalse);
    expect(identity.toQueryParams().containsKey('app_version'), isFalse);
  });
}
