import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_screen.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/editor_stream_session_gateway.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

class _NoopWakelock implements WakelockController {
  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpMultiview(
    WidgetTester tester, {
    required List<Channel> channels,
  }) async {
    const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
    const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final events = StreamController<Map<String, Object?>>.broadcast();
    addTearDown(() async {
      messenger
        ..setMockMethodCallHandler(methodChannel, null)
        ..setMockStreamHandler(eventChannel, null);
      await events.close();
    });
    messenger
      ..setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, eventSink) {
            events.stream.listen(eventSink.success);
          },
        ),
      )
      ..setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'load') {
          return <String, Object?>{'ok': true, 'handle': 1};
        }
        return null;
      });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          streamSessionGatewayProvider.overrideWith(
            (_) => EditorStreamSessionGateway(
              serverBase: () => null,
              stopPlayerStream:
                  ({
                    required type,
                    required streamId,
                    required clientId,
                  }) async {},
            ),
          ),
          multiviewChannelsProvider.overrideWith((_) => channels),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiviewScreen(wakelockController: _NoopWakelock()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  double opacityOf(WidgetTester tester, String text) => tester
      .widget<AnimatedOpacity>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(AnimatedOpacity),
            )
            .first,
      )
      .opacity;

  double opacityOfFinder(WidgetTester tester, Finder finder) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)).first,
      )
      .opacity;

  Future<void> waitForChromeToHide(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  }

  const channelOne = Channel(
    id: 1,
    name: 'Channel One',
    streamUrl: 'https://example.com/live.m3u8',
  );
  const channelTwo = Channel(
    id: 2,
    name: 'Channel Two',
    streamUrl: 'https://example.com/live2.m3u8',
  );

  testWidgets(
    'header and tile labels fade out when idle and return on a key press',
    (tester) async {
      await pumpMultiview(
        tester,
        channels: const <Channel>[
          Channel(
            id: 1,
            name: 'Channel One',
            streamUrl: 'https://example.com/live.m3u8',
          ),
        ],
      );

      expect(opacityOf(tester, 'Multiview'), 1);
      expect(opacityOf(tester, 'Channel One'), 1);

      await tester.pump(const Duration(seconds: 4));
      expect(opacityOf(tester, 'Multiview'), 1);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(opacityOf(tester, 'Multiview'), 0);
      expect(opacityOf(tester, 'Channel One'), 0);
      // The audible tile keeps its speaker icon.
      expect(opacityOfFinder(tester, find.byIcon(Icons.volume_up)), 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(opacityOf(tester, 'Multiview'), 1);
      expect(opacityOf(tester, 'Channel One'), 1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(opacityOf(tester, 'Multiview'), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    // Tiles resolve their backend from the real host platform, so the libmpv
    // channel mocked above only backs a tile on Linux (see
    // multiview_native_plane_test.dart).
    skip: !Platform.isLinux,
  );

  testWidgets(
    'a tap on the hidden header only reveals it',
    (tester) async {
      await pumpMultiview(tester, channels: const [channelOne, channelTwo]);
      await waitForChromeToHide(tester);
      expect(opacityOf(tester, 'Multiview'), 0);

      // Two tiles sit side by side; this lands on the top of the second one,
      // under the hidden header.
      final size = tester.getSize(find.byType(Scaffold));
      await tester.tapAt(Offset(size.width * 0.75, 20));
      await tester.pump();

      expect(opacityOf(tester, 'Multiview'), 1);
      // Focus (and with it the audio) stayed on the first tile.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.byIcon(Icons.volume_up),
            matching: find.byType(Row),
          ),
          matching: find.text('Channel One'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    skip: !Platform.isLinux,
  );

  testWidgets(
    'chrome does not hide while another route covers the grid',
    (tester) async {
      await pumpMultiview(tester, channels: const [channelOne]);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator))
        ..push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacityOf(tester, 'Multiview'), 1);

      await waitForChromeToHide(tester);
      expect(opacityOf(tester, 'Multiview'), 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    skip: !Platform.isLinux,
  );

  testWidgets('header stays visible while there are no tiles', (tester) async {
    await pumpMultiview(tester, channels: const <Channel>[]);

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(opacityOf(tester, 'Multiview'), 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
