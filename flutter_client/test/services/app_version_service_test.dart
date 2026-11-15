import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

AppVersionService _serviceReporting(String remoteVersion) => AppVersionService(
  apiClient: ApiClient(
    client: MockClient(
      (_) async =>
          http.Response('name: m3u_tv\nversion: $remoteVersion\n', 200),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a newer release is new once, and unread until marked read', () async {
    final storage = InMemorySecureStorage();
    final service = _serviceReporting('999.0.0');

    final first = await service.updateNotice(storage);
    expect(first?.version, '999.0.0');
    expect(first?.isNew, isTrue);
    expect(first?.isRead, isFalse);

    final relaunch = await service.updateNotice(storage);
    expect(relaunch?.isNew, isFalse);
    expect(relaunch?.isRead, isFalse);

    await service.markNoticeRead(storage, '999.0.0');
    expect((await service.updateNotice(storage))?.isRead, isTrue);

    final next = await _serviceReporting('999.0.1').updateNotice(storage);
    expect(next?.isNew, isTrue);
    expect(next?.isRead, isFalse);
  });

  test('no notice when the installed version is current', () async {
    expect(
      await _serviceReporting('0.0.1').updateNotice(InMemorySecureStorage()),
      isNull,
    );
  });

  test('no notice when the remote check fails', () async {
    final service = AppVersionService(
      apiClient: ApiClient(
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    expect(await service.updateNotice(InMemorySecureStorage()), isNull);
  });
}
