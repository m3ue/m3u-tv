import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/system_clock.dart';

Widget _app(Widget child, {bool use24Hour = false}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, app) => MediaQuery(
    data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24Hour),
    child: app!,
  ),
  home: Scaffold(body: child),
);

PlaybackControls _controls({
  bool isLive = false,
  bool isPlaying = true,
  Duration position = const Duration(minutes: 5),
  Duration duration = const Duration(hours: 1),
  DateTime? liveProgrammeEnd,
}) => PlaybackControls(
  isPlaying: isPlaying,
  isLive: isLive,
  canSeek: !isLive,
  currentPosition: position,
  duration: duration,
  onPlayPause: () {},
  onSeek: (_) {},
  onBack: () {},
  liveProgrammeEnd: liveProgrammeEnd,
);

void main() {
  group('SystemClock', () {
    final fixed = DateTime(2026, 10, 12, 21, 5);

    testWidgets('follows the 12-hour preference', (tester) async {
      await tester.pumpWidget(_app(SystemClock(now: () => fixed)));
      expect(find.text(DateFormat.jm('en').format(fixed)), findsOneWidget);
    });

    testWidgets('follows the 24-hour preference', (tester) async {
      await tester.pumpWidget(
        _app(SystemClock(now: () => fixed), use24Hour: true),
      );
      expect(find.text('21:05'), findsOneWidget);
    });
  });

  group('PlaybackControls clock and Ends at', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first
        ..physicalSize = const Size(1920, 1080)
        ..devicePixelRatio = 1;
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    testWidgets('shows the clock and Ends at for VOD', (tester) async {
      await tester.pumpWidget(_app(_controls()));

      expect(find.byType(SystemClock), findsOneWidget);
      final finish = DateTime.now().add(const Duration(minutes: 55));
      expect(
        find.text('Ends at ${DateFormat.jm('en').format(finish)}'),
        findsOneWidget,
      );
    });

    testWidgets('uses the EPG programme end for live TV', (tester) async {
      final end = DateTime.now().add(const Duration(minutes: 20));
      await tester.pumpWidget(
        _app(_controls(isLive: true, liveProgrammeEnd: end)),
      );

      expect(
        find.text('Ends at ${DateFormat.jm('en').format(end)}'),
        findsOneWidget,
      );
    });

    testWidgets('hides Ends at for live TV without EPG data', (tester) async {
      await tester.pumpWidget(_app(_controls(isLive: true)));

      expect(find.byType(SystemClock), findsOneWidget);
      expect(find.byKey(const Key('playback-ends-at')), findsNothing);
    });

    testWidgets('hides a live programme end that has already passed', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _controls(
            isLive: true,
            liveProgrammeEnd: DateTime.now().subtract(
              const Duration(minutes: 1),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('playback-ends-at')), findsNothing);
    });

    testWidgets('hides Ends at until the duration is known', (tester) async {
      await tester.pumpWidget(_app(_controls(duration: Duration.zero)));

      expect(find.byKey(const Key('playback-ends-at')), findsNothing);
    });

    testWidgets('stacks Ends at under the clock', (tester) async {
      await tester.pumpWidget(_app(_controls()));

      final clock = tester.getRect(find.byType(SystemClock));
      final endsAt = tester.getRect(find.byKey(const Key('playback-ends-at')));
      expect(endsAt.top, greaterThanOrEqualTo(clock.bottom));
      expect(endsAt.right, moreOrLessEquals(clock.right));
    });

    testWidgets('holds the finish minute steady while playing', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_controls()));
      final before = tester
          .widget<Text>(find.byKey(const Key('playback-ends-at')))
          .data;

      // A position tick a few seconds on, same whole minutes left.
      await tester.pumpWidget(
        _app(_controls(position: const Duration(minutes: 5, seconds: 3))),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('playback-ends-at'))).data,
        before,
      );
    });
  });
}
