import 'dart:async';
import 'dart:io' show Platform;

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
    'Linux native-plane tile clears while healthy and paints black on error',
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
      final clippedTile = find
          .ancestor(
            of: surface,
            matching: find.byType(ClipRRect),
          )
          .first;

      List<RecordedInvocation> recordedTilePaint() {
        final canvas = TestRecordingCanvas();
        final context = TestRecordingPaintingContext(canvas);
        tester.renderObject<RenderBox>(clippedTile).paint(context, Offset.zero);
        context.dispose();
        return canvas.invocations;
      }

      bool paintsWithBlendMode(
        List<RecordedInvocation> invocations,
        BlendMode blendMode,
      ) {
        return invocations.any(
          (record) =>
              record.invocation.memberName == #drawRect &&
              (record.invocation.positionalArguments[1] as Paint).blendMode ==
                  blendMode,
        );
      }

      final healthyPaint = recordedTilePaint();
      expect(
        healthyPaint.any(
          (record) => record.invocation.memberName == #clipRRect,
        ),
        isTrue,
      );
      expect(paintsWithBlendMode(healthyPaint, BlendMode.clear), isTrue);

      events.add(<String, Object?>{
        'schemaVersion': 1,
        'handle': 1,
        'sequence': 1,
        'kind': 'ERROR',
        'message': 'Playback failed',
        'code': 'playback_failed',
      });
      await tester.pump();

      expect(find.text("Couldn't play - select to retry"), findsOneWidget);
      final errorPaint = recordedTilePaint();
      expect(paintsWithBlendMode(errorPaint, BlendMode.clear), isFalse);
      expect(
        errorPaint.any(
          (record) =>
              record.invocation.memberName == #drawRect &&
              (record.invocation.positionalArguments[1] as Paint).color ==
                  Colors.black,
        ),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    // `buildMultiviewTilePlayer` picks Linux's DesktopLibmpvBackend vs.
    // macOS's MacMpvNativeBackend by checking the real `Platform.isMacOS`,
    // not this test's TargetPlatformVariant override -- so on a macOS host
    // this always resolves to MacMpvNativeBackend (not a NativePlaneProvider)
    // and the native-plane assertions below can never pass. CI's flutter
    // test job runs on ubuntu-latest, where this exercises the real path.
    skip: !Platform.isLinux,
  );
}
