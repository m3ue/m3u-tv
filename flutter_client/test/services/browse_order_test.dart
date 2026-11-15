import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

void main() {
  late ViewSettingsService service;

  setUp(() => service = ViewSettingsService(memory: <String, Object?>{}));

  test('defaults match what the screens open with', () {
    expect(service.vodBrowseOrder, (
      sort: MediaSortOption.defaultOrder,
      favoritesFirst: true,
    ));
    expect(service.liveTvBrowseOrder, (
      sort: ChannelSortOption.playlistOrder,
      favoritesFirst: true,
    ));
  });

  test('persisted choices only count under Filter Persistence', () async {
    await service.setRememberMediaSort(true);
    await service.setSeriesSortOption(MediaSortOption.titleDesc);
    await service.setSeriesFavoritesFirst(false);
    expect(service.seriesBrowseOrder, (
      sort: MediaSortOption.titleDesc,
      favoritesFirst: false,
    ));

    final resetEachTime = ViewSettingsService(
      memory: <String, Object?>{
        ViewSettingsService.rememberMediaSortKey: false,
        ViewSettingsService.seriesSortOptionKey:
            MediaSortOption.titleDesc.value,
      },
    );
    expect(resetEachTime.seriesBrowseOrder.sort, MediaSortOption.defaultOrder);
  });

  test('saving a choice keeps the session order in step', () async {
    await service.setRememberMediaSort(false);
    await service.setRememberMediaSort(true);

    await service.setVodSortOption(MediaSortOption.ratingDesc);
    expect(service.vodBrowseOrder.sort, MediaSortOption.ratingDesc);
    await service.setVodFavoritesFirst(false);
    expect(service.vodBrowseOrder, (
      sort: MediaSortOption.ratingDesc,
      favoritesFirst: false,
    ));
  });

  test("a screen's order is shared without being persisted", () async {
    var notified = 0;
    service
      ..addListener(() => notified++)
      ..setVodBrowseOrder((
        sort: MediaSortOption.ratingDesc,
        favoritesFirst: false,
      ));

    expect(notified, 1);
    expect(service.vodBrowseOrder.sort, MediaSortOption.ratingDesc);
    expect(await service.vodSortOption(), MediaSortOption.defaultOrder);
  });

  test('flipping Filter Persistence leaves the current order alone', () async {
    service.setLiveTvBrowseOrder((
      sort: ChannelSortOption.channelNumber,
      favoritesFirst: true,
    ));
    await service.setRememberMediaSort(true);
    expect(service.liveTvBrowseOrder.sort, ChannelSortOption.channelNumber);
    await service.setRememberMediaSort(false);
    expect(service.liveTvBrowseOrder.sort, ChannelSortOption.channelNumber);
  });
}
