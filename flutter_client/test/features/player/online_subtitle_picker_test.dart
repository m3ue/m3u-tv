import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/online_subtitle_picker.dart';
import 'package:m3u_tv/features/player/track_selector.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/online_subtitle_service.dart';
import 'package:material_ui/material_ui.dart';

OnlineSubtitle _sub(String id, String language) => OnlineSubtitle(
  id: id,
  url: 'https://subs.example/$id',
  language: language,
  release: 'Release.$id',
);

void main() {
  Widget host(Widget child) => Dpad(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  AppLocalizations strings(WidgetTester tester, Type type) =>
      AppLocalizations.of(tester.element(find.byType(type)));

  group('language order', () {
    final subtitles = [
      _sub('1', 'spa'),
      _sub('2', 'eng'),
      _sub('3', 'ger'),
      _sub('4', 'fre'),
    ];

    test('is by name without a preference', () {
      expect(orderOnlineSubtitleLanguages(subtitles), [
        'ger',
        'eng',
        'spa',
        'fre',
      ]);
    });

    test('puts the device language first', () {
      expect(
        orderOnlineSubtitleLanguages(subtitles, deviceLanguage: 'fr').first,
        'fre',
      );
    });

    test('puts the last used language ahead of the device one', () {
      expect(
        orderOnlineSubtitleLanguages(
          subtitles,
          lastLanguage: 'spa',
          deviceLanguage: 'fr',
        ).take(2),
        ['spa', 'fre'],
      );
    });
  });

  group('results', () {
    testWidgets('shows searching, then languages with counts', (tester) async {
      final completer = Completer<List<OnlineSubtitle>>();
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () => completer.future,
            onSelected: (_) async {},
          ),
        ),
      );
      await tester.pump();
      final l = strings(tester, OnlineSubtitleResults);
      expect(find.text(l.playerOnlineSubtitlesSearching), findsOneWidget);

      completer.complete([
        _sub('1', 'eng'),
        _sub('2', 'eng'),
        _sub('3', 'ger'),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('English (2)'), findsOneWidget);
      expect(find.text('Deutsch (1)'), findsOneWidget);
    });

    testWidgets('a language leads to its releases and back', (tester) async {
      String? picked;
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () async => [_sub('1', 'eng'), _sub('2', 'ger')],
            onSelected: (_) async {},
            onLanguagePicked: (language) => picked = language,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = strings(tester, OnlineSubtitleResults);

      await tester.tap(find.text('English (1)'));
      await tester.pumpAndSettle();
      expect(picked, 'eng');
      expect(find.text('Release.1'), findsOneWidget);
      expect(find.text('Release.2'), findsNothing);

      await tester.tap(find.text(l.playerOnlineSubtitlesAllLanguages));
      await tester.pumpAndSettle();
      expect(find.text('Deutsch (1)'), findsOneWidget);
    });

    testWidgets('a single language skips straight to releases', (tester) async {
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () async => [_sub('1', 'eng')],
            onSelected: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = strings(tester, OnlineSubtitleResults);

      expect(find.text('Release.1'), findsOneWidget);
      expect(find.text(l.playerOnlineSubtitlesAllLanguages), findsNothing);
    });

    testWidgets('says when nothing was found', (tester) async {
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () async => const [],
            onSelected: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = strings(tester, OnlineSubtitleResults);

      expect(find.text(l.playerOnlineSubtitlesEmpty), findsOneWidget);
    });

    testWidgets('a failed search can be retried', (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () async {
              attempts++;
              if (attempts == 1) throw const OnlineSubtitleException('offline');
              return [_sub('1', 'eng')];
            },
            onSelected: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = strings(tester, OnlineSubtitleResults);
      expect(find.text(l.playerOnlineSubtitlesFailed), findsOneWidget);

      await tester.tap(find.text(l.playerOnlineSubtitlesRetry));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Release.1'), findsOneWidget);
    });

    testWidgets('a failed pick stays open to try another', (tester) async {
      await tester.pumpWidget(
        host(
          OnlineSubtitleResults(
            search: () async => [_sub('1', 'eng')],
            onSelected: (_) async =>
                throw const OnlineSubtitleException('download failed'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = strings(tester, OnlineSubtitleResults);

      await tester.tap(find.text('Release.1'));
      await tester.pumpAndSettle();

      expect(find.text(l.playerOnlineSubtitlesFailed), findsOneWidget);
      expect(find.text('Release.1'), findsOneWidget);
    });

    testWidgets('a good pick loads the subtitle and closes', (tester) async {
      OnlineSubtitle? selected;
      await tester.pumpWidget(
        Dpad(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => unawaited(
                    showOnlineSubtitlePicker(
                      context,
                      search: () async => [_sub('1', 'eng')],
                      onSelected: (subtitle) async => selected = subtitle,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release.1'));
      await tester.pumpAndSettle();

      expect(selected?.id, '1');
      expect(find.byType(OnlineSubtitleResults), findsNothing);
    });
  });

  group('subtitle button', () {
    Widget selector({
      List<PlaybackTrack> subtitleTracks = const [],
      VoidCallback? onSearch,
    }) => host(
      TrackSelector(
        audioTracks: const [],
        subtitleTracks: subtitleTracks,
        selectedAudioTrackId: null,
        selectedSubtitleTrackId: null,
        onAudioTrackSelected: (_) {},
        onSubtitleTrackSelected: (_) {},
        onSearchOnlineSubtitles: onSearch,
      ),
    );

    testWidgets('stays hidden with no tracks and no search', (tester) async {
      await tester.pumpWidget(selector());

      final l = strings(tester, TrackSelector);
      expect(find.text(l.playerTrackSubtitles), findsNothing);
    });

    testWidgets('shows for a stream with no tracks when search is available, '
        'and search opens once the menu has closed', (tester) async {
      var searches = 0;
      await tester.pumpWidget(selector(onSearch: () => searches++));
      final l = strings(tester, TrackSelector);

      await tester.tap(find.text(l.playerTrackSubtitles));
      await tester.pumpAndSettle();
      expect(searches, 0);

      await tester.tap(find.text(l.playerOnlineSubtitlesSearch));
      await tester.pumpAndSettle();

      expect(searches, 1);
      expect(find.text(l.playerOnlineSubtitlesSearch), findsNothing);
    });

    testWidgets('the menu has no search row without search', (tester) async {
      await tester.pumpWidget(
        selector(
          subtitleTracks: const [PlaybackTrack(id: '1', label: 'English')],
        ),
      );
      final l = strings(tester, TrackSelector);

      await tester.tap(find.text(l.playerTrackSubtitles));
      await tester.pumpAndSettle();

      expect(find.text('English'), findsOneWidget);
      expect(find.text(l.playerOnlineSubtitlesSearch), findsNothing);
    });
  });
}
