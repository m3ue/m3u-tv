import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'active Linux native-plane tile punches through instead of painting black',
    (tester) async {
      const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
      const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');
      final eventListenerReady = Completer<void>();
      final events = StreamController<Map<String, Object?>>.broadcast(
        onListen: eventListenerReady.complete,
      );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(eventChannel, null);
        await events.close();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen(eventSink.success);
              },
            ),
          );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              await eventListenerReady.future;
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 1,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 1,
                'usesNativePlane': true,
              };
            }
            return null;
          });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            multiviewChannelsProvider.overrideWith(
              (_) => const <Channel>[
                Channel(
                  id: 1,
                  name: 'Native Plane Channel',
                  streamUrl: 'https://example.com/live.m3u8',
                ),
              ],
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MultiviewScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final surface = find.byType(NativeVideoSurface);
      expect(surface, findsOneWidget);
      expect(
        tester.widget<NativeVideoSurface>(surface).nativePlane?.usesNativePlane,
        isTrue,
      );
      expect(
        tester
            .widgetList<ColoredBox>(
              find.ancestor(of: surface, matching: find.byType(ColoredBox)),
            )
            .where((box) => box.color == Colors.black),
        isEmpty,
      );
      expect(
        find.descendant(of: surface, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
