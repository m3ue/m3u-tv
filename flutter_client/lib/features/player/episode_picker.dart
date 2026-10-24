import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Opens an in-player dialog letting the viewer jump directly to another
/// episode of the current series without leaving playback - a season
/// selector (when the series has more than one) plus the episode list for
/// the selected season. Mirrors `TrackSelector`'s dialog-based picker
/// pattern and `SeasonPicker`'s D-pad list-row styling. Returns the
/// dialog's dismiss future so the caller can track its open/closed state
/// (e.g. to keep the player's OSD pinned while it's up).
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

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _EpisodePickerDialog(
      info: info,
      seasons: seasons,
      initialSeason: initialSeason,
      currentEpisodeId: currentEpisodeId,
      onSelect: (episode) {
        Navigator.of(dialogContext).pop();
        onSelect(episode);
      },
    ),
  );
}

class _EpisodePickerDialog extends StatefulWidget {
  const _EpisodePickerDialog({
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
  State<_EpisodePickerDialog> createState() => _EpisodePickerDialogState();
}

class _EpisodePickerDialogState extends State<_EpisodePickerDialog> {
  late int _season = widget.initialSeason;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final episodes =
        (widget.info.episodesBySeason[_season] ?? const <Episode>[]).toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final hasMultipleSeasons = widget.seasons.length > 1;

    return AlertDialog(
      clipBehavior: Clip.antiAlias,
      title: Text(l.playerEpisodePickerTitle),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
      content: SizedBox(
        width: 460 * scale,
        child: DpadRegion(
          verticalEdge: DpadEdgeBehavior.stop,
          horizontalEdge: DpadEdgeBehavior.stop,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasMultipleSeasons)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 44 * scale,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.seasons.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final season = widget.seasons[index];
                        final selected = season.number == _season;
                        return AppButton(
                          label: l.homeSeason(season.number),
                          variant: selected
                              ? AppButtonVariant.primary
                              : AppButtonVariant.tonal,
                          autoScroll: false,
                          onPressed: () =>
                              setState(() => _season = season.number),
                        );
                      },
                    ),
                  ),
                ),
              if (hasMultipleSeasons) const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: viewportHeight * 0.5),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
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
        ),
      ),
      actions: [
        AppButton(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: DpadInkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        color: isCurrent ? scheme.primaryContainer : null,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${episode.episodeNumber}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  episode.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (isCurrent)
                Icon(Icons.play_arrow, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
