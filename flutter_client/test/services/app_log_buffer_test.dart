import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_log_buffer.dart';

void main() {
  test('evicts the oldest lines past the byte budget', () {
    final buffer = AppLogBuffer(maxBytes: 300);
    for (var i = 0; i < 20; i++) {
      buffer.add(AppLogLevel.info, 'line $i');
    }

    expect(buffer.entries.length, lessThan(20));
    expect(buffer.entries.last.message, 'line 19');
  });

  test('redacts credentials in Xtream paths, query params and bearers', () {
    final buffer = AppLogBuffer()
      ..add(
        AppLogLevel.info,
        'GET http://host/live/alice/s3cret/123.ts and '
        'http://host/api/tv/alice/s3cret/notifications',
      )
      ..add(
        AppLogLevel.info,
        'player_api.php?username=alice&password=s3cret&api_key=k&X-Plex-Token=t',
      )
      ..add(AppLogLevel.info, 'Authorization: Bearer abc.def');

    final text = buffer.export();
    expect(text, isNot(contains('alice')));
    expect(text, isNot(contains('s3cret')));
    expect(text, isNot(contains('abc.def')));
    expect(text, contains('/live/[redacted]/[redacted]/123.ts'));
    expect(text, contains('X-Plex-Token=[redacted]'));
  });

  test('scrubs registered secrets anywhere, including the header', () {
    final buffer = AppLogBuffer()
      ..registerSecret('hunter22')
      ..add(AppLogLevel.error, 'login failed for hunter22');

    final text = buffer.export(header: 'pw hunter22');
    expect(text, isNot(contains('hunter22')));
  });

  test('export with a byte cap keeps the header and the newest lines', () {
    final buffer = AppLogBuffer();
    for (var i = 0; i < 100; i++) {
      buffer.add(AppLogLevel.info, 'line ${i.toString().padLeft(3, '0')}');
    }

    final text = buffer.export(header: 'HEADER', maxBytes: 200);
    expect(text, startsWith('HEADER\n---\n'));
    expect(text, contains('line 099'));
    expect(text, isNot(contains('line 000')));
    expect(text.length, lessThanOrEqualTo(200));
  });

  test('install tees debugPrint and framework errors into the buffer', () {
    final previousPrint = debugPrint;
    final previousFlutterError = FlutterError.onError;
    final previousPlatformError = PlatformDispatcher.instance.onError;
    addTearDown(() {
      debugPrint = previousPrint;
      FlutterError.onError = previousFlutterError;
      PlatformDispatcher.instance.onError = previousPlatformError;
    });
    final forwarded = <String?>[];
    debugPrint = (message, {wrapWidth}) => forwarded.add(message);
    FlutterError.onError = (_) {};

    final buffer = AppLogBuffer()..install();
    debugPrint('hello');
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('boom')),
    );

    expect(forwarded, ['hello']);
    expect(buffer.entries.first.message, 'hello');
    expect(buffer.entries.last.level, AppLogLevel.error);
    expect(buffer.entries.last.message, contains('boom'));
  });
}
