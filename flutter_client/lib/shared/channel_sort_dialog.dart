import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/sort_option_row.dart';

/// Shows the Live TV "Sort By" modal - the channel-list counterpart of
/// `showMediaSortDialog`, kept separate because [ChannelSortOption]'s cases
/// (playlist order / channel number / alphabetical) have nothing in common
/// with VOD/Series' (rating / release date). Returns the newly selected
/// [ChannelSortOption], or null if the dialog was dismissed without one.
/// The Favorites First switch reports through [onFavoritesFirstChanged] as
/// it is flipped, independent of the return value.
Future<ChannelSortOption?> showChannelSortDialog(
  BuildContext context, {
  required ChannelSortOption current,
  required bool favoritesFirst,
  required ValueChanged<bool> onFavoritesFirstChanged,
}) {
  final l = AppLocalizations.of(context);
  final options = <(IconData, String, ChannelSortOption)>[
    (
      Icons.list_alt,
      l.channelSortPlaylistOrder,
      ChannelSortOption.playlistOrder,
    ),
    (
      Icons.tag,
      l.channelSortChannelNumber,
      ChannelSortOption.channelNumber,
    ),
    (
      Icons.sort_by_alpha,
      l.channelSortAlphabeticalAsc,
      ChannelSortOption.alphabeticalAsc,
    ),
    (
      Icons.sort_by_alpha,
      l.channelSortAlphabeticalDesc,
      ChannelSortOption.alphabeticalDesc,
    ),
  ];
  return showDialog<ChannelSortOption>(
    context: context,
    builder: (dialogContext) {
      final scale = FontSizeScope.scaleOf(dialogContext);
      return SimpleDialog(
        title: Row(
          children: [
            Icon(Icons.sort, size: 18 * scale),
            SizedBox(width: 8 * scale),
            Expanded(child: Text(l.liveTvSortDialogTitle)),
          ],
        ),
        children: [
          DpadRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FavoritesFirstSortRow(
                  initialValue: favoritesFirst,
                  onChanged: onFavoritesFirstChanged,
                ),
                const Divider(),
                for (final (icon, label, option) in options)
                  SortOptionRow(
                    icon: icon,
                    label: label,
                    isActive: current == option,
                    autofocus: current == option,
                    onTap: () => Navigator.of(dialogContext).pop(option),
                  ),
                SortOptionRow(
                  icon: Icons.close,
                  label: l.close,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
