import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/immersive_top.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:material_ui/material_ui.dart';

const _band = ImmersiveTopRegions(statusBarHidden: true, occlusions: []);

ImmersiveTopRegions _bandWith(List<Rect> occlusions) =>
    ImmersiveTopRegions(statusBarHidden: true, occlusions: occlusions);

const _spans = [(0.0, 56.0), (300.0, 500.0)];

void main() {
  group('immersiveHeaderTop', () {
    test('keeps the safe area when the band is not available', () {
      expect(
        immersiveHeaderTop(
          regions: null,
          headerSpans: _spans,
          headerHeight: 56,
        ),
        isNull,
      );
      expect(
        immersiveHeaderTop(
          regions: const ImmersiveTopRegions(
            statusBarHidden: false,
            occlusions: [],
          ),
          headerSpans: _spans,
          headerHeight: 56,
        ),
        isNull,
      );
    });

    test('moves to the minimum when no occlusion is in the way', () {
      expect(
        immersiveHeaderTop(
          regions: _band,
          headerSpans: _spans,
          headerHeight: 56,
        ),
        12,
      );
      // Camera in the top-right corner, clear of back button and title.
      expect(
        immersiveHeaderTop(
          regions: _bandWith([const Rect.fromLTWH(700, 0, 60, 40)]),
          headerSpans: _spans,
          headerHeight: 56,
        ),
        12,
      );
    });

    test('drops below an occlusion the header overlaps', () {
      expect(
        immersiveHeaderTop(
          regions: _bandWith([const Rect.fromLTWH(380, 0, 40, 34)]),
          headerSpans: _spans,
          headerHeight: 56,
        ),
        34,
      );
    });

    test('ignores occlusions below the header', () {
      expect(
        immersiveHeaderTop(
          regions: _bandWith([const Rect.fromLTWH(0, 400, 800, 20)]),
          headerSpans: _spans,
          headerHeight: 56,
        ),
        12,
      );
    });
  });

  group('ImmersiveTopController', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('immersive_top_test');
    final requests = <Object?>[];

    setUp(() {
      requests.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            requests.add(call.arguments);
            return {
              'statusBarHidden': call.arguments == true,
              'occlusions': [
                [10, 0, 20, 30],
              ],
            };
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'requests once for stacked holders and clears on last release',
      () async {
        final controller =
            ImmersiveTopController(
                channel: channel,
                enabled: true,
              )
              ..acquire()
              ..acquire();
        await pumpEventQueue();
        expect(requests, [true]);
        expect(controller.regions.value?.statusBarHidden, isTrue);
        expect(controller.regions.value?.occlusions, [
          const Rect.fromLTWH(10, 0, 20, 30),
        ]);

        controller.release();
        await pumpEventQueue();
        expect(requests, [true]);
        expect(controller.regions.value, isNotNull);

        controller.release();
        await pumpEventQueue();
        expect(requests, [true, false]);
        expect(controller.regions.value, isNull);
      },
    );

    test('does nothing off iOS', () async {
      final controller = ImmersiveTopController(
        channel: channel,
        enabled: false,
      )..acquire();
      await pumpEventQueue();
      expect(requests, isEmpty);
      expect(controller.regions.value, isNull);
    });
  });

  group('ItemDetailScaffold header', () {
    tearDown(() => ImmersiveTopController.instance.regions.value = null);

    Future<double> backButtonTop(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 80)),
            child: child!,
          ),
          home: const ItemDetailScaffold(
            title: 'Sprite Fright',
            body: SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      final backButton = find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(IconButton),
      );
      return tester.getTopLeft(backButton).dy;
    }

    testWidgets('stays below the status bar band by default', (tester) async {
      expect(await backButtonTop(tester), greaterThanOrEqualTo(80));
    });

    testWidgets('moves into the band when the status bar is hidden', (
      tester,
    ) async {
      ImmersiveTopController.instance.regions.value = _band;
      final top = await backButtonTop(tester);
      expect(top, lessThan(80));
      expect(top, greaterThanOrEqualTo(12));
    });
  });
}
