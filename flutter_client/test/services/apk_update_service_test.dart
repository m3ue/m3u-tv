import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/apk_update_service.dart';

Map<String, Object?> _asset(String name) => {
  'name': name,
  'size': 4,
  'browser_download_url': 'https://example.test/$name',
};

void main() {
  group('parseRelease', () {
    test('picks the versioned APK and its checksum', () {
      final release = ApkUpdateService.parseRelease({
        'tag_name': 'v1.4.0',
        'assets': [
          _asset('m3u-tv-android.apk'),
          _asset('m3u-tv-v1.4.0-linux.zip'),
          _asset('m3u-tv-v1.4.0-android.apk'),
          _asset('m3u-tv-v1.4.0-android.apk.sha256'),
        ],
      });

      expect(release, isNotNull);
      expect(release!.version, '1.4.0');
      expect(release.apkName, 'm3u-tv-v1.4.0-android.apk');
      expect(
        release.checksumUrl.toString(),
        'https://example.test/m3u-tv-v1.4.0-android.apk.sha256',
      );
      expect(release.sizeBytes, 4);
    });

    test('is null without a checksum or APK', () {
      expect(
        ApkUpdateService.parseRelease({
          'assets': [_asset('m3u-tv-v1.4.0-android.apk')],
        }),
        isNull,
      );
      expect(
        ApkUpdateService.parseRelease({
          'assets': [_asset('m3u-tv-android.apk')],
        }),
        isNull,
      );
      expect(ApkUpdateService.parseRelease('nope'), isNull);
    });
  });

  group('download', () {
    late Directory cache;
    final apkBytes = [1, 2, 3, 4];
    final release = ApkRelease(
      version: '1.4.0',
      apkName: 'm3u-tv-v1.4.0-android.apk',
      apkUrl: Uri.parse('https://example.test/apk'),
      checksumUrl: Uri.parse('https://example.test/apk.sha256'),
      sizeBytes: 4,
    );

    setUp(() => cache = Directory.systemTemp.createTempSync('apk_update'));
    tearDown(() => cache.deleteSync(recursive: true));

    ApkUpdateService service(String checksum) {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('.sha256')) {
          return http.Response('$checksum  ${release.apkName}\n', 200);
        }
        return http.Response.bytes(apkBytes, 200);
      });
      return ApkUpdateService(
        apiClient: ApiClient(client: client),
        httpClient: client,
        cacheDirectory: () async => cache,
        enabled: true,
      );
    }

    test('keeps a file matching the published checksum', () async {
      final progress = <int>[];
      final file = await service(
        sha256.convert(apkBytes).toString(),
      ).download(release, onProgress: (received, _) => progress.add(received));

      expect(file.readAsBytesSync(), apkBytes);
      expect(progress.last, 4);
    });

    test('discards a file that does not match', () async {
      await expectLater(
        service('0' * 64).download(release),
        throwsA(isA<ApkChecksumMismatch>()),
      );
      final dir = Directory('${cache.path}/apk_update');
      expect(
        dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('clearDownloads removes a finished download', () async {
      final updates = service(sha256.convert(apkBytes).toString());
      final file = await updates.download(release);
      await updates.clearDownloads();
      expect(file.existsSync(), isFalse);
    });
  });
}
