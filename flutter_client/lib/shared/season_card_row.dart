import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Horizontally scrolling row of season cards for the Series Details
/// screen. Replaces the old `_SeasonChips` pill row with poster-sized
/// cards (120×180) — each card shows the season's TMDB poster
/// thumbnail, name, and episode count. Tapping a card (or D-pad
/// left/right to it + Enter) selects that season.
///
/// All layouts (TV / desktop / mobile) use this same component. There is
/// no dropdown, no overlay, and no popup — the row is always visible.
class SeasonCardRow extends StatelessWidget {
  const SeasonCardRow({
    super.key,
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;

  static const double _cardWidth = 120;
  static const double _cardHeight = 180;
  static const double _cardRadius = 8;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    return DpadRegion(
      memoryKey: 'season-card-row',
      horizontalEdge: DpadEdgeBehavior.stop,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: MediaBrowsingMetrics.contentPadding,
          vertical: MediaBrowsingMetrics.itemGap,
        ),
        child: Row(
          children: [
            for (var i = 0; i < seasons.length; i++) ...[
              if (i > 0) const SizedBox(width: MediaBrowsingMetrics.itemGap),
              _SeasonCard(
                season: seasons[i],
                isSelected: seasons[i].number == selectedSeason,
                onTap: () => onSeasonSelected(seasons[i].number),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    required this.season,
    required this.isSelected,
    required this.onTap,
  });

  final Season season;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final posterUrl = season.coverBigUrl ?? season.coverUrl;

    return DpadInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SeasonCardRow._cardRadius),
      color: colorScheme.surfaceContainerHigh,
      effects: [
        GradientBorderEffect(
          borderRadius: BorderRadius.circular(SeasonCardRow._cardRadius),
        ),
      ],
      child: SizedBox(
        width: SeasonCardRow._cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(SeasonCardRow._cardRadius),
              ),
              child: SizedBox(
                width: SeasonCardRow._cardWidth,
                height: SeasonCardRow._cardHeight,
                child: ResilientMediaImage(
                  imageUrl: posterUrl,
                  fallbackIcon: Icons.tv,
                  borderRadius: 0,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.homeSeason(season.number),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (season.episodeCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      l
                          .seriesSeasonPillLabel(
                            season.number,
                            season.episodeCount,
                          )
                          .split(' · ')
                          .last,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
