import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/sort_option_row.dart';

/// Shows the "Sort By" modal shared by every sortable media grid (VOD,
/// Series). Returns the newly selected [MediaSortOption], or null if the
/// dialog was dismissed (Close, back, tap outside) without one. The
/// Favorites First switch reports through [onFavoritesFirstChanged] as it
/// is flipped, independent of the return value.
Future<MediaSortOption?> showMediaSortDialog(
  BuildContext context, {
  required String title,
  required MediaSortOption current,
  required bool favoritesFirst,
  required ValueChanged<bool> onFavoritesFirstChanged,
}) {
  final l = AppLocalizations.of(context);
  final options = <(IconData, String, MediaSortOption)>[
    (Icons.list_alt, l.mediaSortDefault, MediaSortOption.defaultOrder),
    (Icons.star_rate, l.mediaSortRating, MediaSortOption.ratingDesc),
    (
      Icons.south,
      l.mediaSortReleaseDateNewest,
      MediaSortOption.releaseDateDesc,
    ),
    (
      Icons.north,
      l.mediaSortReleaseDateOldest,
      MediaSortOption.releaseDateAsc,
    ),
  ];
  return showDialog<MediaSortOption>(
    context: context,
    builder: (dialogContext) {
      final scale = FontSizeScope.scaleOf(dialogContext);
      return SimpleDialog(
        title: Row(
          children: [
            Icon(Icons.sort, size: 18 * scale),
            SizedBox(width: 8 * scale),
            Expanded(child: Text(title)),
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
