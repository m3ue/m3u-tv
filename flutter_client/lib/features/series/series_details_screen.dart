import 'package:flutter/material.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({
    super.key,
    required this.seriesId,
    required this.seriesName,
    required this.xtreamService,
  });

  final int seriesId;
  final String seriesName;
  final XtreamService xtreamService;

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  late final Future<SeriesInfo> _future = widget.xtreamService.getSeriesInfo(
    widget.seriesId,
  );
  int? _selectedSeason;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.seriesName)),
      body: SafeArea(
        child: FutureBuilder<SeriesInfo>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Could not load episodes: ${snapshot.error}'),
              );
            }
            final info = snapshot.data;
            if (info == null)
              return const Center(child: Text('No episodes available'));
            return _SeriesDetailsBody(
              info: info,
              selectedSeason: _selectedSeason,
              onSeasonSelected: (season) =>
                  setState(() => _selectedSeason = season),
              onEpisodeSelected: _playEpisode,
            );
          },
        ),
      ),
    );
  }

  void _playEpisode(Episode episode) {
    final streamUrl = episode.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) return;
    Navigator.of(context).pushNamed(
      RouteNames.player,
      arguments: PlayerArgs(
        streamUrl: streamUrl,
        title: episode.title,
        type: 'series',
        streamId: int.tryParse(episode.id),
        seriesId: widget.seriesId,
        seasonNumber: episode.seasonNumber,
        metadata: <String, Object?>{
          'container_extension': episode.containerExtension,
        },
      ),
    );
  }
}

class _SeriesDetailsBody extends StatelessWidget {
  const _SeriesDetailsBody({
    required this.info,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.onEpisodeSelected,
  });

  final SeriesInfo info;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<Episode> onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seasonNumber =
        selectedSeason ??
        (info.seasons.isNotEmpty
            ? info.seasons.first.number
            : info.episodesBySeason.keys.firstOrNull);
    final episodes = seasonNumber == null
        ? const <Episode>[]
        : info.episodesBySeason[seasonNumber] ?? const <Episode>[];
    final backdrop = info.series.backdropUrl;

    final content = Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: AspectRatio(
              aspectRatio: 0.68,
              child: ResilientMediaImage(
                imageUrl: info.series.coverUrl,
                fallbackIcon: Icons.tv,
                borderRadius: 16,
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(info.series.name, style: theme.textTheme.headlineMedium),
                if (info.series.rating != null) ...[
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('★ ${info.series.rating}'),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ],
                if (info.series.plot != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    info.series.plot!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: info.seasons
                        .map((season) {
                          final selected = season.number == seasonNumber;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(season.name),
                              selected: selected,
                              onSelected: (_) =>
                                  onSeasonSelected(season.number),
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: episodes.isEmpty
                      ? const Center(child: Text('No episodes available'))
                      : ListView.separated(
                          itemCount: episodes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final episode = episodes[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                autofocus: index == 0,
                                leading: CircleAvatar(
                                  child: Text('${episode.episodeNumber}'),
                                ),
                                title: Text(episode.title),
                                subtitle: episode.plot == null
                                    ? null
                                    : Text(episode.plot!),
                                trailing: const Icon(Icons.play_arrow),
                                onTap: () => onEpisodeSelected(episode),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (backdrop == null) return content;

    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topRight,
          child: FractionallySizedBox(
            widthFactor: 0.7,
            heightFactor: 0.4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(backdrop, fit: BoxFit.cover),
                // Fade left edge into background
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                        colors: [Colors.transparent, theme.colorScheme.surface],
                        stops: const [0.1, 1.0],
                      ),
                    ),
                  ),
                ),
                // Fade bottom edge into background
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, theme.colorScheme.surface],
                        stops: const [0.1, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        content,
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
