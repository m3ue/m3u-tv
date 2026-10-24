import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart'
    show ResilientMediaImage;

/// Opens a bottom drawer letting the viewer jump directly to another episode
/// of the current series without leaving playback - a season selector (when
/// the series has more than one) plus the episode list for the selected
/// season, each row showing its thumbnail and a truncated synopsis. Mirrors
/// `SeasonPicker`'s bottom-sheet-with-header pattern. Returns the sheet's
/// dismiss future so the caller can track its open/closed state (e.g. to
/// keep the player's OSD pinned while it's up).
Future<void> showEpisodePicker(
  BuildContext context, {
  required SeriesInfo info,
  required int? currentSeasonNumber,
  required String currentEpisodeId,
  required ValueChanged<Episode> onSelect,
}) {
  final seasons =
      info.seasons
          .where(
            (season) =>
                (info.episodesBySeason[season.number] ?? const <Episode>[])
                    .isNotEmpty,
          )
          .toList()
        ..sort((a, b) => a.number.compareTo(b.number));
  if (seasons.isEmpty) return Future<void>.value();
  final initialSeason =
      seasons.any((season) => season.number == currentSeasonNumber)
      ? currentSeasonNumber!
      : seasons.first.number;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: _EpisodePickerSheet(
        info: info,
        seasons: seasons,
        initialSeason: initialSeason,
        currentEpisodeId: currentEpisodeId,
        onSelect: (episode) {
          Navigator.of(sheetContext).pop();
          onSelect(episode);
        },
      ),
    ),
  );
}

class _EpisodePickerSheet extends StatefulWidget {
  const _EpisodePickerSheet({
    required this.info,
    required this.seasons,
    required this.initialSeason,
    required this.currentEpisodeId,
    required this.onSelect,
  });

  final SeriesInfo info;
  final List<Season> seasons;
  final int initialSeason;
  final String currentEpisodeId;
  final ValueChanged<Episode> onSelect;

  @override
  State<_EpisodePickerSheet> createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<_EpisodePickerSheet> {
  late int _season = widget.initialSeason;

  /// One key per season chip, so the selected season can be scrolled fully
  /// into view (it otherwise sits wherever the horizontal strip happens to
  /// start, which clipped it against the sheet's edge when it wasn't the
  /// first season).
  late final Map<int, GlobalKey> _seasonKeys = {
    for (final season in widget.seasons) season.number: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedSeason(),
    );
  }

  void _scrollToSelectedSeason() {
    final context = _seasonKeys[_season]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
    );
  }

  void _selectSeason(int seasonNumber) {
    setState(() => _season = seasonNumber);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedSeason(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final episodes =
        (widget.info.episodesBySeason[_season] ?? const <Episode>[]).toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final hasMultipleSeasons = widget.seasons.length > 1;

    // One DpadRegion for the whole sheet - the close button, the season
    // strip, and the episode list - so D-pad up/down/left/right can reach
    // every control without escaping the sheet (same reasoning as
    // `SeasonPicker._showPicker`'s pickerBody).
    return DpadRegion(
      verticalEdge: DpadEdgeBehavior.stop,
      horizontalEdge: DpadEdgeBehavior.stop,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20 * scale,
              0,
              12 * scale,
              4 * scale,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.playerEpisodePickerTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                AppIconButton(
                  icon: Icons.close,
                  dense: true,
                  tooltip: l.cancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (hasMultipleSeasons)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              child: Row(
                children: [
                  for (final season in widget.seasons) ...[
                    _SeasonChip(
                      key: _seasonKeys[season.number],
                      label: l.homeSeason(season.number),
                      selected: season.number == _season,
                      onTap: () => _selectSeason(season.number),
                    ),
                    SizedBox(width: 8 * scale),
                  ],
                ],
              ),
            ),
          if (hasMultipleSeasons) SizedBox(height: 8 * scale),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: viewportHeight * 0.55),
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(
                  12 * scale,
                  4 * scale,
                  12 * scale,
                  12 * scale,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final isCurrent = episode.id == widget.currentEpisodeId;
                  return _EpisodeTile(
                    episode: episode,
                    isCurrent: isCurrent,
                    autofocus: isCurrent || index == 0,
                    onTap: () => widget.onSelect(episode),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact season pill - deliberately not `AppButton`, which is sized for
/// primary actions and was too large for a strip of several of these in a
/// row. Mirrors `request_detail_screen.dart`'s `_SeasonToggle` styling: a
/// small pill with a leading check icon on the selected one.
class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return DpadInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 14 * scale,
          vertical: 8 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 16 * scale, color: foreground),
              SizedBox(width: 6 * scale),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.isCurrent,
    required this.autofocus,
    required this.onTap,
  });

  final Episode episode;
  final bool isCurrent;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final thumbWidth = 96 * scale;
    final thumbHeight = thumbWidth * 9 / 16;
    final plot = episode.plot?.trim();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * scale),
      child: DpadInkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(8 * scale),
        clipBehavior: Clip.antiAlias,
        color: isCurrent ? scheme.primaryContainer : null,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8 * scale),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6 * scale),
                child: ResilientMediaImage(
                  imageUrl: episode.thumbnailUrl,
                  fallbackIcon: Icons.tv,
                  width: thumbWidth,
                  height: thumbHeight,
                  borderRadius: 0,
                ),
              ),
              SizedBox(width: 12 * scale),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${episode.episodeNumber}. ${episode.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isCurrent) ...[
                          SizedBox(width: 6 * scale),
                          Icon(
                            Icons.play_arrow,
                            size: 18 * scale,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                    if (plot != null && plot.isNotEmpty) ...[
                      SizedBox(height: 4 * scale),
                      Text(
                        plot,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
