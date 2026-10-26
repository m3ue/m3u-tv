import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:m3u_tv/features/player/playback_controls.dart'
    show isHandheldLayout;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart'
    show ResilientMediaImage;
import 'package:m3u_tv/shared/selectable_chip.dart';

/// Seasons from [info] that actually have at least one episode - the only
/// ones the picker can show. Exposed so a caller can decide whether the
/// picker affordance (e.g. a toolbar button) has anything to open before
/// enabling it, rather than enabling it unconditionally and letting
/// [showEpisodePicker] silently no-op when there's nothing to pick from.
List<Season> pickableSeasons(SeriesInfo info) =>
    info.seasons
        .where(
          (season) =>
              (info.episodesBySeason[season.number] ?? const <Episode>[])
                  .isNotEmpty,
        )
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

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
  final seasons = pickableSeasons(info);
  if (seasons.isEmpty) return Future<void>.value();
  final initialSeason =
      seasons.any((season) => season.number == currentSeasonNumber)
      ? currentSeasonNumber!
      : seasons.first.number;

  final isHandheld = isHandheldLayout(context);
  final screenWidth = MediaQuery.sizeOf(context).width;
  // TV/desktop: Material's default modal-bottom-sheet width cap (~640dp)
  // read as cramped on a wide TV screen - widen it well past that, still
  // leaving side margins rather than spanning edge to edge. Phones/tablets
  // keep the unconstrained default (full width), which is how a bottom
  // sheet reads best there - same as `SeasonPicker`'s own phone sheet.
  final constraints = isHandheld
      ? null
      : BoxConstraints(
          maxWidth: math.min(screenWidth * 0.62, screenWidth - 48),
        );

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: constraints,
    builder: (sheetContext) => SafeArea(
      child: _EpisodePickerSheet(
        info: info,
        seasons: seasons,
        initialSeason: initialSeason,
        currentEpisodeId: currentEpisodeId,
        isHandheld: isHandheld,
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
    required this.isHandheld,
    required this.onSelect,
  });

  final SeriesInfo info;
  final List<Season> seasons;
  final int initialSeason;
  final String currentEpisodeId;
  final bool isHandheld;
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

  /// Owns the focus for whichever tile is currently playing, within
  /// whichever season holds it - `ListView.builder` only builds tiles near
  /// the viewport, so a plain per-tile `autofocus` silently does nothing for
  /// an episode far down a long season (focus would fall through to episode
  /// 1 with no indication anything was wrong). A large `cacheExtent` on the
  /// episode list (below) guarantees this node's tile is actually built on
  /// the first frame so `.context` and `.requestFocus()` both work.
  final FocusNode _currentEpisodeFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedSeason();
      _focusCurrentEpisode();
    });
  }

  @override
  void dispose() {
    _currentEpisodeFocusNode.dispose();
    super.dispose();
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

  /// Scrolls the currently-playing episode into view and gives it focus, if
  /// its tile is built (only true while the season actually showing it is
  /// selected - switching away just leaves the season's own first-episode
  /// autofocus in charge, which is already correct there).
  void _focusCurrentEpisode() {
    final context = _currentEpisodeFocusNode.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 200),
    );
    _currentEpisodeFocusNode.requestFocus();
  }

  void _selectSeason(int seasonNumber) {
    setState(() => _season = seasonNumber);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedSeason();
      _focusCurrentEpisode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final episodes =
        (widget.info.episodesBySeason[_season] ?? const <Episode>[]).toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final hasCurrentEpisode = episodes.any(
      (episode) => episode.id == widget.currentEpisodeId,
    );
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
                    SelectableChip(
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
                // Generous enough to pre-build a full season's worth of
                // tiles (even a 40+ episode anime season at "Very Large"
                // scale) so the current episode's tile - however far down -
                // is always built on the first frame, letting
                // `_focusCurrentEpisode` actually find and focus it instead
                // of silently falling back to episode 1.
                scrollCacheExtent: const ScrollCacheExtent.pixels(6000),
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
                    isHandheld: widget.isHandheld,
                    // The current episode's focus is driven explicitly by
                    // `_focusCurrentEpisode` (via its own FocusNode) so it
                    // doesn't race a plain `autofocus: true` here - only
                    // fall back to autofocusing episode 1 when this season
                    // doesn't contain the current episode at all.
                    focusNode: isCurrent ? _currentEpisodeFocusNode : null,
                    autofocus: !hasCurrentEpisode && index == 0,
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

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.isCurrent,
    required this.isHandheld,
    required this.autofocus,
    required this.onTap,
    this.focusNode,
  });

  final Episode episode;
  final bool isCurrent;
  final bool isHandheld;
  final bool autofocus;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    // Smaller on phones/tablets - leaves enough room for the title/plot
    // text next to it instead of squeezing both into a narrow screen,
    // especially at a larger display-size setting.
    final thumbWidth = (isHandheld ? 72 : 96) * scale;
    final thumbHeight = thumbWidth * 9 / 16;
    final plot = episode.plot?.trim();

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4 * scale),
      child: DpadInkWell(
        focusNode: focusNode,
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
