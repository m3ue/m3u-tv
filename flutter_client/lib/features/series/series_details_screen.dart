import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({
    super.key,
    required this.seriesId,
    required this.seriesName,
    required this.xtreamService,
    this.onPlay,
    this.progressList = const [],
  });

  final int seriesId;
  final String seriesName;
  final XtreamService xtreamService;
  final void Function(PlayerArgs)? onPlay;
  final List<Progress> progressList;

  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  late final Future<SeriesInfo> _future = widget.xtreamService
      .getSeriesInfo(widget.seriesId)
      .then((info) {
        _seriesInfo = info;
        return info;
      });
  int? _selectedSeason;
  SeriesInfo? _seriesInfo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.seriesName),
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: DpadFocusable(
            onSelect: () => Navigator.of(context).maybePop(),
            effects: const [
              GradientBorderEffect(
                borderRadius: BorderRadius.all(Radius.circular(50)),
              ),
            ],
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: FutureBuilder<SeriesInfo>(
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
          if (info == null) {
            return const Center(child: Text('No episodes available'));
          }
          return _SeriesDetailsBody(
            info: info,
            selectedSeason: _selectedSeason,
            progressList: widget.progressList,
            onSeasonSelected: (season) =>
                setState(() => _selectedSeason = season),
            onEpisodeSelected: _playEpisode,
          );
        },
      ),
    );
  }

  void _playEpisode(Episode episode) {
    final streamUrl = episode.streamUrl;
    if (streamUrl == null || streamUrl.isEmpty) return;
    widget.onPlay?.call(
      PlayerArgs(
        streamUrl: streamUrl,
        title: episode.title,
        type: 'series',
        streamId: int.tryParse(episode.id),
        seriesId: widget.seriesId,
        seasonNumber: episode.seasonNumber,
        metadata: <String, Object?>{
          'container_extension': episode.containerExtension,
          'season_number': episode.seasonNumber,
          'episode_number': episode.episodeNumber,
          'episode_title': episode.title,
          'series_name': widget.seriesName,
          if (_seriesInfo?.series.tmdbId != null)
            'tmdb_id': _seriesInfo!.series.tmdbId,
          if (_seriesInfo?.series.backdropUrl != null)
            'backdrop_url': _seriesInfo!.series.backdropUrl,
          if (episode.thumbnailUrl != null)
            'thumbnail_url': episode.thumbnailUrl,
          if (episode.rating != null) 'rating': '${episode.rating}',
          if (episode.duration != null) 'duration': episode.duration,
        },
      ),
    );
  }
}

class _SeriesDetailsBody extends StatelessWidget {
  const _SeriesDetailsBody({
    required this.info,
    required this.selectedSeason,
    required this.progressList,
    required this.onSeasonSelected,
    required this.onEpisodeSelected,
  });

  final SeriesInfo info;
  final int? selectedSeason;
  final List<Progress> progressList;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<Episode> onEpisodeSelected;

  static const double _wideBreakpoint = 600;

  int? get _resolvedSeason =>
      selectedSeason ??
      (info.seasons.isNotEmpty
          ? info.seasons.first.number
          : info.episodesBySeason.keys.firstOrNull);

  List<Episode> _episodes(int? seasonNumber) => seasonNumber == null
      ? const <Episode>[]
      : info.episodesBySeason[seasonNumber] ?? const <Episode>[];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return _buildNarrow(context);
        }
        return _buildWide(context);
      },
    );
  }

  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
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
                _SeasonChips(
                  seasons: info.seasons,
                  selectedSeason: seasonNumber,
                  onSeasonSelected: onSeasonSelected,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _EpisodeList(
                    episodes: episodes,
                    progressList: progressList,
                    onEpisodeSelected: onEpisodeSelected,
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

  Widget _buildNarrow(BuildContext context) {
    final theme = Theme.of(context);
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
    final backdrop = info.series.backdropUrl;
    final cover = info.series.coverUrl;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              if (backdrop != null)
                SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(backdrop, fit: BoxFit.cover),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                theme.colorScheme.surface,
                              ],
                              stops: const [0.4, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: EdgeInsets.only(
                  top: backdrop != null ? 120 : 16,
                  left: 16,
                  right: 16,
                  bottom: 16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ResilientMediaImage(
                        imageUrl: cover,
                        fallbackIcon: Icons.tv,
                        width: 100,
                        height: 148,
                        borderRadius: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            info.series.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (info.series.rating != null) ...[
                            const SizedBox(height: 4),
                            Chip(
                              label: Text('★ ${info.series.rating}'),
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (info.series.plot != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                info.series.plot!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _SeasonChips(
              seasons: info.seasons,
              selectedSeason: seasonNumber,
              onSeasonSelected: onSeasonSelected,
            ),
          ),
        ),
        if (episodes.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No episodes available')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverList.separated(
              itemCount: episodes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final streamId = int.tryParse(episode.id);
                final progress = streamId == null
                    ? null
                    : progressList
                          .where(
                            (p) =>
                                p.streamId == streamId &&
                                p.contentType == ContentType.episode,
                          )
                          .firstOrNull;
                return _EpisodeTile(
                  episode: episode,
                  progress: progress,
                  autofocus: index == 0,
                  onTap: () => onEpisodeSelected(episode),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SeasonChips extends StatefulWidget {
  const _SeasonChips({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;

  @override
  State<_SeasonChips> createState() => _SeasonChipsState();
}

class _SeasonChipsState extends State<_SeasonChips> {
  final ScrollController _controller = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) return const SizedBox.shrink();
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.seasons
                .map((season) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CategoryFilterChip(
                      label: season.name,
                      isSelected: season.number == widget.selectedSeason,
                      onTap: () => widget.onSeasonSelected(season.number),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.episodes,
    required this.progressList,
    required this.onEpisodeSelected,
  });

  final List<Episode> episodes;
  final List<Progress> progressList;
  final ValueChanged<Episode> onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    if (episodes.isEmpty) {
      return const Center(child: Text('No episodes available'));
    }
    return ListView.separated(
      itemCount: episodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final episode = episodes[index];
        final streamId = int.tryParse(episode.id);
        final progress = streamId == null
            ? null
            : progressList
                  .where(
                    (p) =>
                        p.streamId == streamId &&
                        p.contentType == ContentType.episode,
                  )
                  .firstOrNull;
        return _EpisodeTile(
          episode: episode,
          progress: progress,
          autofocus: index == 0,
          onTap: () => onEpisodeSelected(episode),
        );
      },
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.autofocus,
    required this.onTap,
    this.progress,
  });

  final Episode episode;
  final Progress? progress;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setHovered(bool v) {
    if (_hovered == v) return;
    setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final progress = widget.progress;
    final autofocus = widget.autofocus;
    final onTap = widget.onTap;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final p = progress;
    final progressValue =
        (p != null &&
            p.durationSeconds != null &&
            p.durationSeconds! > 0 &&
            !p.completed)
        ? (p.positionSeconds / p.durationSeconds!).clamp(0.0, 1.0)
        : null;

    final hasThumbnail = episode.thumbnailUrl != null;

    final metaChips = <String>[
      if (episode.rating != null) '★ ${episode.rating!.toStringAsFixed(1)}',
      if (episode.duration != null) episode.duration!,
      if (episode.releaseDate != null) episode.releaseDate!,
    ];

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: DpadFocusable(
        autofocus: autofocus,
        focusNode: _focusNode,
        onSelect: onTap,
        builder: (context, state, child) => DpadEffect.wrap(
          context,
          const [
            GradientBorderEffect(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ],
          DpadFocusState(
            focused: state.focused || _hovered,
            pressed: state.pressed,
          ),
          child,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  _focusNode.requestFocus();
                  onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail or episode-number badge
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 120,
                          height: 68,
                          child: hasThumbnail
                              ? Image.network(
                                  episode.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) =>
                                      _episodeNumberBadge(colorScheme),
                                )
                              : _episodeNumberBadge(colorScheme),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Title, meta chips, description
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: theme.textTheme.titleSmall,
                                      children: [
                                        TextSpan(
                                          text: 'E${episode.episodeNumber} · ',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        TextSpan(text: episode.title),
                                      ],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.play_arrow, size: 20),
                              ],
                            ),
                            if (metaChips.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: metaChips
                                    .map(
                                      (chip) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorScheme.surfaceBright,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          chip,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme.onPrimary,
                                              ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                            if (episode.plot != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                episode.plot!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (progressValue != null)
                LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 3,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodeNumberBadge(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          'E${widget.episode.episodeNumber}',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
