import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

/// The sort button's label: generic "Sort" at playlist order (matching the
/// VOD/Series sort button's own default-order label), otherwise the active
/// option's own name so the button doubles as a status indicator.
String channelSortButtonLabel(AppLocalizations l, ChannelSortOption option) =>
    switch (option) {
      ChannelSortOption.playlistOrder => l.mediaCategorySortButton,
      ChannelSortOption.channelNumber => l.channelSortChannelNumber,
      ChannelSortOption.alphabeticalAsc => l.channelSortAlphabeticalAsc,
      ChannelSortOption.alphabeticalDesc => l.channelSortAlphabeticalDesc,
    };

/// The catalog ordering behind each Live TV sort option. Natural name order
/// comes from the promoted `nameSortKey` column (see `NaturalSortKey.encode`).
CatalogSort catalogSortForChannels(ChannelSortOption option) =>
    switch (option) {
      ChannelSortOption.playlistOrder => CatalogSort.providerOrder,
      ChannelSortOption.channelNumber => CatalogSort.channelNumber,
      ChannelSortOption.alphabeticalAsc => CatalogSort.nameNatural,
      ChannelSortOption.alphabeticalDesc => CatalogSort.nameNaturalDesc,
    };
