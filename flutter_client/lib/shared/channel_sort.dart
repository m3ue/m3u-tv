import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/natural_sort.dart';

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

/// Sorts the Live TV channel list/grid per [option]. Channels are a plain
/// in-memory list (unlike VOD/Series' windowed SQL-backed catalog), so this
/// sorts client-side rather than pushing an `ORDER BY` down to a repository.
///
/// Channels whose id is in [favoritesFirst] are moved ahead of the rest,
/// each group keeping [option]'s order - the in-memory counterpart of
/// `CatalogRepository.pageItems`' `favoritesFirst`.
List<Channel> sortChannels(
  List<Channel> channels,
  ChannelSortOption option, {
  Set<int> favoritesFirst = const {},
}) {
  final sorted = _sortChannelsBy(channels, option);
  if (favoritesFirst.isEmpty) return sorted;
  return [
    ...sorted.where((channel) => favoritesFirst.contains(channel.id)),
    ...sorted.where((channel) => !favoritesFirst.contains(channel.id)),
  ];
}

List<Channel> _sortChannelsBy(
  List<Channel> channels,
  ChannelSortOption option,
) {
  if (option == ChannelSortOption.playlistOrder) return channels;
  final list = channels.toList(growable: false);
  switch (option) {
    case ChannelSortOption.playlistOrder:
      break;
    case ChannelSortOption.channelNumber:
      // Channels without a provider-assigned number (null or 0) sink below
      // every numbered one, then fall back to natural name order so they're
      // still browsable rather than left in an arbitrary clump.
      list.sort((a, b) {
        final an = a.channelNumber;
        final bn = b.channelNumber;
        final aHas = an != null && an != 0;
        final bHas = bn != null && bn != 0;
        if (aHas && bHas) {
          final cmp = an.compareTo(bn);
          return cmp != 0 ? cmp : compareNatural(a.name, b.name);
        }
        if (aHas != bHas) return aHas ? -1 : 1;
        return compareNatural(a.name, b.name);
      });
    case ChannelSortOption.alphabeticalAsc:
      list.sort((a, b) => compareNatural(a.name, b.name));
    case ChannelSortOption.alphabeticalDesc:
      list.sort((a, b) => compareNatural(b.name, a.name));
  }
  return list;
}
