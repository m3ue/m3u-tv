import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

Progress _upNext({int stream = 99}) => Progress(
  viewerId: 'v1',
  contentType: ContentType.episode,
  streamId: stream,
  positionSeconds: 0,
  seriesId: 5,
  seasonNumber: 2,
  episodeNumber: 6,
  seriesName: 'Breaking Bad',
  episodeTitle: 'Next One',
  upNext: true,
);

void main() {
  group('isContinueWatchingEligible', () {
    test('lets up-next entries through despite zero position', () {
      expect(isContinueWatchingEligible(_upNext()), isTrue);
    });

    test('still rejects a live up-next entry', () {
      const live = Progress(
        viewerId: 'v1',
        contentType: ContentType.live,
        streamId: 1,
        positionSeconds: 0,
        upNext: true,
      );
      expect(isContinueWatchingEligible(live), isFalse);
    });

    test('still requires >=30s for non-up-next entries', () {
      const p = Progress(
        viewerId: 'v1',
        contentType: ContentType.vod,
        streamId: 1,
        positionSeconds: 10,
        durationSeconds: 3600,
      );
      expect(isContinueWatchingEligible(p), isFalse);
    });
  });

  testWidgets('up-next preview item carries the badge label and no progress', (
    tester,
  ) async {
    late List<MediaPreviewItem> items;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            items = continueWatchingPreviewItems(
              context,
              progressList: [_upNext()],
              vodItems: const [],
              seriesList: const [Series(id: 5, name: 'Breaking Bad')],
              onProgressSelect: (_) {},
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(items, hasLength(1));
    expect(items.first.upNextLabel, 'Up next');
    expect(items.first.progressFraction, isNull);
  });
}
