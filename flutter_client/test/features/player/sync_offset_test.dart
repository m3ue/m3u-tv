import 'package:dpad/dpad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/sync_offset_bar.dart';
import 'package:m3u_tv/features/player/track_selector.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:material_ui/material_ui.dart';

final AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

Widget _host(Widget child) => Dpad(
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  test('formatSyncOffset', () {
    expect(formatSyncOffset(_l, Duration.zero), '0 ms');
    expect(formatSyncOffset(_l, const Duration(milliseconds: 120)), '+120 ms');
    expect(formatSyncOffset(_l, const Duration(milliseconds: -50)), '-50 ms');
    expect(formatSyncOffset(_l, const Duration(milliseconds: 1500)), '+1.5 s');
    expect(formatSyncOffset(_l, const Duration(seconds: -2)), '-2 s');
    expect(formatSyncOffset(_l, const Duration(milliseconds: 1250)), '+1.25 s');
  });

  group('TrackSelector sync rows', () {
    Widget selector({VoidCallback? onAudioSync, VoidCallback? onSubSync}) =>
        _host(
          TrackSelector(
            audioTracks: const [PlaybackTrack(id: 'a1', label: 'English 5.1')],
            subtitleTracks: const [PlaybackTrack(id: 's1', label: 'English')],
            selectedAudioTrackId: 'a1',
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
            audioSyncOffset: const Duration(milliseconds: 120),
            subtitleSyncOffset: Duration.zero,
            onAdjustAudioSync: onAudioSync,
            onAdjustSubtitleSync: onSubSync,
          ),
        );

    testWidgets('the audio picker shows the offset and opens the bar after '
        'it closes', (tester) async {
      var opened = 0;
      await tester.pumpWidget(selector(onAudioSync: () => opened++));

      await tester.tap(find.text(_l.playerTrackAudio));
      await tester.pumpAndSettle();
      final row = find.text('${_l.playerAudioSync}: +120 ms');
      expect(row, findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('English 5.1'), findsNothing);
    });

    testWidgets('the subtitle picker has its own row', (tester) async {
      var opened = 0;
      await tester.pumpWidget(selector(onSubSync: () => opened++));

      await tester.tap(find.text(_l.playerTrackSubtitles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('${_l.playerSubtitleSync}: 0 ms'));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('no rows when the backend cannot shift sync', (tester) async {
      await tester.pumpWidget(selector());

      await tester.tap(find.text(_l.playerTrackAudio));
      await tester.pumpAndSettle();

      expect(find.textContaining(_l.playerAudioSync), findsNothing);
    });

    testWidgets('long-pressing Audio opens the bar directly', (tester) async {
      var opened = 0;
      await tester.pumpWidget(selector(onAudioSync: () => opened++));

      await tester.longPress(find.text(_l.playerTrackAudio));
      await tester.pumpAndSettle();

      expect(opened, 1);
    });
  });

  group('SyncOffsetBar', () {
    Future<List<Duration>> pumpBar(
      WidgetTester tester, {
      SyncOffsetKind kind = SyncOffsetKind.audio,
      Duration initial = Duration.zero,
    }) async {
      final changes = <Duration>[];
      await tester.pumpWidget(
        _host(
          SyncOffsetBar(kind: kind, initial: initial, onChanged: changes.add),
        ),
      );
      return changes;
    }

    testWidgets('audio steps by 10 ms and 100 ms', (tester) async {
      final changes = await pumpBar(tester);

      await tester.tap(find.text('+10 ms'));
      await tester.pump();
      await tester.tap(find.text('+100 ms'));
      await tester.pump();
      await tester.tap(find.text('-10 ms'));
      await tester.pump();

      expect(changes.map((d) => d.inMilliseconds), [10, 110, 100]);
      expect(find.text('+100 ms'), findsNWidgets(2));
    });

    testWidgets('subtitles step by 50 ms and 1 s', (tester) async {
      final changes = await pumpBar(tester, kind: SyncOffsetKind.subtitle);

      await tester.tap(find.text('-1 s'));
      await tester.pump();
      await tester.tap(find.text('+50 ms'));
      await tester.pump();

      expect(changes.map((d) => d.inMilliseconds), [-1000, -950]);
    });

    testWidgets('stops at the limit and resets to zero', (tester) async {
      final changes = await pumpBar(
        tester,
        kind: SyncOffsetKind.subtitle,
        initial: maxSyncOffset - const Duration(milliseconds: 500),
      );

      await tester.tap(find.text('+1 s'));
      await tester.pump();
      await tester.tap(find.text('+1 s'));
      await tester.pump();
      expect(changes, [maxSyncOffset]);

      await tester.tap(find.text(_l.playerSyncReset));
      await tester.pump();
      expect(changes.last, Duration.zero);
    });
  });
}
