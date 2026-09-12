import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/movie_detail_body.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart';

class AIOStreamsDetailScreen extends StatefulWidget {
  const AIOStreamsDetailScreen({
    super.key,
    required this.item,
    required this.integrationId,
    required this.apiService,
    required this.onPlay,
    this.onSidebarActivate,
    this.appStateController,
    this.onOpenRelated,
  });

  final AIOStreamsItem item;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(PlayerArgs) onPlay;
  final VoidCallback? onSidebarActivate;
  final AppStateController? appStateController;

  /// Opens a related item's own detail screen. Null hides the row's actions
  /// (the row itself still renders informationally when this is null).
  final ValueChanged<RelatedItem>? onOpenRelated;

  @override
  State<AIOStreamsDetailScreen> createState() => _AIOStreamsDetailScreenState();
}

class _AIOStreamsDetailScreenState extends State<AIOStreamsDetailScreen> {
  late final Future<AIOStreamsItem?> _metaFuture = widget.apiService
      .getMeta(widget.integrationId, widget.item.type, widget.item.id)
      .then((meta) {
        unawaited(
          _resolveDominantColor(
            meta?.background ??
                meta?.poster ??
                widget.item.background ??
                widget.item.poster,
          ),
        );
        return meta;
      });

  /// Palette-extracted tone from the backdrop (or poster), so the hero can
  /// bleed a matching colour past the image edge and cross-fade it in with
  /// the art - identical treatment to VodDetailsScreen / SeriesDetailsScreen.
  Color? _dominantColor;
  bool _colorMatchResolved = false;

  /// Owned here (rather than inside the shared series body) so the AppBar
  /// back button - outside the scrollable page entirely - can also snap it
  /// back to top on focus. Unused (never attached) on the movie path.
  final ScrollController _scrollController = ScrollController();

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  bool get _isSeries => widget.item.type == 'series';

  @override
  void initState() {
    super.initState();
    // Best-effort colour match from the data we already have, so the reveal
    // starts before getMeta returns (and still works if it fails).
    unawaited(
      _resolveDominantColor(widget.item.background ?? widget.item.poster),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _resolveDominantColor(String? url) async {
    final color = await resolveDominantBackdropColor(url);
    if (!mounted) return;
    setState(() {
      if (color != null) _dominantColor = color;
      _colorMatchResolved = true;
    });
  }

  void _openStreamPicker({
    required AIOStreamsItem item,
    required String type,
    required String id,
    required String title,
    AIOStreamsVideo? video,
  }) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AIOStreamsStreamPickerSheet(
          integrationId: widget.integrationId,
          type: type,
          id: id,
          apiService: widget.apiService,
          onStreamSelected: (stream) {
            Navigator.of(context).pop();
            widget.onPlay(
              PlayerArgs(
                streamUrl: stream.url,
                title: title,
                type: type == 'series' ? 'series' : 'vod',
                headers: _proxyRequestHeaders(stream.behaviorHints),
                metadata: <String, Object?>{
                  'aiostreams': true,
                  'aio_item_id': widget.item.id,
                  'aio_integration_id': widget.integrationId,
                  // For series: title is the series name; series_name drives the
                  // Trakt show/episode branch in _scrobble().
                  'title': widget.item.name,
                  if (type == 'series') 'series_name': widget.item.name,
                  // Episodes use episode thumb; movies/series fall back to backdrop, then poster.
                  'thumbnail_url':
                      video?.thumbnail ?? item.background ?? item.poster,
                  'backdrop_url': item.background ?? item.poster,
                  if (video != null) 'season_number': video.season,
                  if (video != null) 'episode_number': video.episode,
                  if (video != null) 'episode_title': video.title,
                  if (item.year != null) 'year': item.year,
                  if (item.imdbRating != null) 'rating': item.imdbRating,
                  if (item.description != null) 'plot': item.description,
                  'source': stream.name,
                  'quality': stream.title,
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Extracts request headers that the player must send when opening this
  /// stream. AIOStreams (and the Stremio addon spec) puts these under
  /// behaviorHints.proxyHeaders.request — typically a User-Agent that the
  /// debrid/CDN server requires.
  static Map<String, String> _proxyRequestHeaders(
    Map<String, dynamic> behaviorHints,
  ) {
    final proxyHeaders = behaviorHints['proxyHeaders'];
    if (proxyHeaders is! Map) return const {};
    final request = proxyHeaders['request'];
    if (request is! Map) return const {};
    final result = <String, String>{};
    request.forEach((key, value) {
      if (key is String && value is String && value.isNotEmpty) {
        result[key] = value;
      }
    });
    return result.isEmpty ? const {} : result;
  }

  @override
  Widget build(BuildContext context) {
    return ItemDetailScaffold(
      title: widget.item.name,
      onSidebarActivate: widget.onSidebarActivate,
      onBackButtonFocused: _scrollToTop,
      body: FutureBuilder<AIOStreamsItem?>(
        future: _metaFuture,
        builder: (context, snapshot) {
          final item = snapshot.data ?? widget.item;
          final isLoading = snapshot.connectionState != ConnectionState.done;
          // A failed meta fetch means no palette step will resolve from it -
          // reveal the (surface) hero rather than holding on the flat colour.
          final colorMatchReady = _colorMatchResolved || snapshot.hasError;
          if (_isSeries) {
            if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _SeriesBody(
              item: item,
              appStateController: widget.appStateController,
              dominantColor: _dominantColor,
              colorMatchReady: colorMatchReady,
              scrollController: _scrollController,
              onEpisodeSelected: (video) => _openStreamPicker(
                item: item,
                type: 'series',
                id: video.id,
                title: video.title.isNotEmpty ? video.title : item.name,
                video: video,
              ),
              onOpenRelated: widget.onOpenRelated,
            );
          }
          return _MovieBody(
            item: item,
            isLoading: isLoading,
            dominantColor: _dominantColor,
            colorMatchReady: colorMatchReady,
            onGetStreams: () => _openStreamPicker(
              item: item,
              type: 'movie',
              id: item.id,
              title: item.name,
            ),
            onOpenRelated: widget.onOpenRelated,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movie body - builds the shared MovieDetailBody from AIOStreams data
// ---------------------------------------------------------------------------

class _MovieBody extends StatelessWidget {
  const _MovieBody({
    required this.item,
    required this.isLoading,
    required this.onGetStreams,
    this.dominantColor,
    this.colorMatchReady = false,
    this.onOpenRelated,
  });

  final AIOStreamsItem item;
  final bool isLoading;
  final VoidCallback onGetStreams;
  final ValueChanged<RelatedItem>? onOpenRelated;

  /// Palette-extracted backdrop tone + whether it has resolved. Drives the
  /// same colour-matched, cross-faded hero as the Xtream VOD detail.
  final Color? dominantColor;
  final bool colorMatchReady;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final richCast = item.richCast;
    return MovieDetailBody(
      name: item.name,
      posterUrl: item.poster,
      backdropUrl: item.background,
      clearLogoUrl: item.clearLogoUrl,
      chips: [
        if (item.year != null) item.year!,
        if (item.imdbRating != null) '★ ${item.imdbRating}',
        ?_runtimeChip(item.runtime),
        ...item.genres.take(3),
      ],
      plot: item.description,
      credits: [
        if (item.director != null)
          MetaCreditLine(label: 'Director', value: item.director!),
        if (item.writer != null)
          MetaCreditLine(label: 'Writer', value: item.writer!),
        // The comma-separated `cast` string only earns a credit line when
        // there is no rich cast row - otherwise it just repeats it.
        if ((richCast == null || richCast.isEmpty) && item.cast != null)
          MetaCreditLine(label: 'Cast', value: item.cast!),
      ],
      richCast: richCast,
      castSemanticLabel: l.vodCast,
      richRelated: item.related,
      onRelatedTap: onOpenRelated,
      primaryButtonLabel: l.aiostreamsGetStreams,
      onPrimary: onGetStreams,
      isLoading: isLoading,
      dominantColor: dominantColor,
      colorMatchReady: colorMatchReady,
    );
  }
}

/// Renders a runtime value ("136", "136 min") as a "136m" chip, or null when
/// there is nothing parseable.
String? _runtimeChip(String? runtime) {
  if (runtime == null) return null;
  final match = RegExp(r'(\d+)').firstMatch(runtime);
  if (match == null) return null;
  return '${match.group(1)}m';
}

// ---------------------------------------------------------------------------
// Series body - shares SeriesDetailsScreen's season picker + episode strip +
// cast row (lib/shared/series_detail_widgets.dart), adapted to AIOStreams data.
// ---------------------------------------------------------------------------

const double _kAioSeriesCompactBreakpoint = 700;

class _SeriesBody extends StatefulWidget {
  const _SeriesBody({
    required this.item,
    required this.onEpisodeSelected,
    this.appStateController,
    this.dominantColor,
    this.colorMatchReady = false,
    this.scrollController,
    this.onOpenRelated,
  });

  final AIOStreamsItem item;
  final void Function(AIOStreamsVideo video) onEpisodeSelected;
  final AppStateController? appStateController;
  final ScrollController? scrollController;
  final ValueChanged<RelatedItem>? onOpenRelated;

  /// Palette-extracted backdrop tone + whether it has resolved. Drives the
  /// same colour-matched, cross-faded hero as SeriesDetailsScreen.
  final Color? dominantColor;
  final bool colorMatchReady;

  @override
  State<_SeriesBody> createState() => _SeriesBodyState();
}

class _SeriesBodyState extends State<_SeriesBody> {
  int? _selectedSeason;
  final FocusNode _seasonFocusNode = FocusNode(debugLabel: 'aioSeasonPicker');

  @override
  void dispose() {
    _seasonFocusNode.dispose();
    super.dispose();
  }

  List<Progress> get _progressForSeries =>
      widget.appStateController?.progressList
          .where(
            (p) =>
                p.contentType == ContentType.aiostreams &&
                p.aioItemId == widget.item.id,
          )
          .toList() ??
      const [];

  Map<int, List<AIOStreamsVideo>> get _videosBySeason {
    final map = <int, List<AIOStreamsVideo>>{};
    for (final v in widget.item.videos) {
      map.putIfAbsent(v.season, () => []).add(v);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.episode.compareTo(b.episode));
    }
    return map;
  }

  /// Season numbers that either the meta's `videos` or the enriched `seasons`
  /// array know about, low to high.
  List<int> get _seasonNumbers {
    final numbers =
        <int>{
          ...widget.item.seasons.map((s) => s.number),
          ..._videosBySeason.keys,
        }.toList()..sort((a, b) {
          // Season 0 is the "specials" bucket - always sort it last so the
          // picker defaults to a real season (usually 1).
          if (a == 0) return 1;
          if (b == 0) return -1;
          return a.compareTo(b);
        });
    return numbers;
  }

  /// One [Season] record per number in [_seasonNumbers], using the enriched
  /// poster/overview when the editor supplied it and a bare placeholder
  /// otherwise, so [SeasonPicker] always has something to render.
  List<Season> get _seasons => _seasonNumbers
      .map((n) {
        return widget.item.seasons.firstWhere(
          (s) => s.number == n,
          orElse: () => Season(number: n, name: 'Season $n'),
        );
      })
      .toList(growable: false);

  int? get _resolvedSeason {
    final numbers = _seasonNumbers;
    if (numbers.isEmpty) return null;
    return _selectedSeason ?? numbers.first;
  }

  Season? get _resolvedSeasonObj {
    final n = _resolvedSeason;
    if (n == null) return null;
    return widget.item.seasons.firstWhere(
      (s) => s.number == n,
      orElse: () => Season(number: n, name: 'Season $n'),
    );
  }

  int _episodeCountFor(int seasonNumber) {
    final loaded = _videosBySeason[seasonNumber]?.length ?? 0;
    if (loaded > 0) return loaded;
    return widget.item.seasons
        .firstWhere(
          (s) => s.number == seasonNumber,
          orElse: () => const Season(number: -1, name: ''),
        )
        .episodeCount;
  }

  /// AIOStreams episodes for a season, mapped onto the shared [Episode] shape
  /// the episode strip renders. `containerExtension` is irrelevant here (the
  /// stream is chosen later in the picker sheet).
  List<Episode> _episodesForSeason(int? seasonNumber) {
    final videos = seasonNumber == null
        ? const <AIOStreamsVideo>[]
        : _videosBySeason[seasonNumber] ?? const <AIOStreamsVideo>[];
    return videos
        .map(
          (v) => Episode(
            id: v.id,
            episodeNumber: v.episode,
            title: v.title,
            containerExtension: '',
            seasonNumber: v.season,
            plot: v.description,
            thumbnailUrl: v.thumbnail,
            rating: v.rating,
            releaseDate: v.released,
          ),
        )
        .toList(growable: false);
  }

  /// AIOStreams progress rows are keyed by season + episode number, not by a
  /// numeric stream id, so the strip needs this instead of its default
  /// id-based match.
  Progress? _progressForEpisode(Episode episode) {
    for (final p in _progressForSeries) {
      if (p.seasonNumber == episode.seasonNumber &&
          p.episodeNumber == episode.episodeNumber) {
        return p;
      }
    }
    return null;
  }

  void _selectEpisode(Episode episode) {
    final video = widget.item.videos.firstWhere(
      (v) => v.id == episode.id,
      orElse: () => widget.item.videos.firstWhere(
        (v) =>
            v.season == episode.seasonNumber &&
            v.episode == episode.episodeNumber,
        orElse: () => throw StateError('no video for ${episode.id}'),
      ),
    );
    widget.onEpisodeSelected(video);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.appStateController;
    if (controller != null) {
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _buildLayout(context),
      );
    }
    return _buildLayout(context);
  }

  Widget _buildLayout(BuildContext context) {
    final l = AppLocalizations.of(context);
    final item = widget.item;
    // Relabel the season 0 bucket as "Specials" for the picker list. Ordering
    // (last) is handled in _seasonNumbers, which _seasons maps over.
    final seasons = [
      for (final s in _seasons)
        if (s.number == 0)
          Season(
            number: 0,
            name: l.requestsSeasonSpecials,
            episodeCount: s.episodeCount,
            coverUrl: s.coverUrl,
            overview: s.overview,
            releaseDate: s.releaseDate,
          )
        else
          s,
    ];
    final seasonNumber = _resolvedSeason;
    final seasonObj = _resolvedSeasonObj;
    final episodes = _episodesForSeason(seasonNumber);
    final progress = _progressForSeries;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < _kAioSeriesCompactBreakpoint;
    final plotMaxWidth = compact ? double.infinity : screenWidth * 0.6;

    final richCast = item.richCast;
    final seasonCover = seasonObj?.coverUrl;
    final description = (seasonObj?.overview?.trim().isNotEmpty ?? false)
        ? seasonObj!.overview!.trim()
        : item.description;
    // Season cover -> series poster -> backdrop.
    final posterChain = <String>[
      if (seasonCover != null && seasonCover.trim().isNotEmpty) seasonCover,
      if (item.poster != null && item.poster!.trim().isNotEmpty) item.poster!,
      if (item.background != null && item.background!.trim().isNotEmpty)
        item.background!,
    ];

    final chips = <String>[
      if (seasons.isNotEmpty) '${seasons.length} ${l.seriesSeasons}',
      if (item.imdbRating != null) '★ ${item.imdbRating}',
      ?_runtimeChip(item.runtime),
    ];

    final meta = ItemMetaInfo(
      name: item.name,
      clearLogoUrl: item.clearLogoUrl,
      chips: chips,
      hidePrimaryAction: true,
      buttonLabel: '',
      onPlay: null,
      plot: description,
      plotMaxWidth: plotMaxWidth,
      plotMaxLines: 4,
      credits: [
        if (item.director != null)
          MetaCreditLine(label: 'Director', value: item.director!),
        if (item.writer != null)
          MetaCreditLine(label: 'Writer', value: item.writer!),
        if ((richCast == null || richCast.isEmpty) && item.cast != null)
          MetaCreditLine(label: 'Cast', value: item.cast!),
      ],
    );

    return SeriesDetailBody(
      seriesName: item.name,
      posterChain: posterChain,
      backdropUrl: item.background,
      seasons: seasons,
      selectedSeason: _selectedSeason,
      resolvedSeason: seasonNumber,
      episodes: episodes,
      episodeCountFor: _episodeCountFor,
      fallbackPosterUrl: item.poster,
      meta: meta,
      primaryActions: const [],
      richCast: richCast,
      castSemanticLabel: l.seriesCast,
      richRelated: item.related,
      onRelatedTap: widget.onOpenRelated,
      progressList: progress,
      progressResolver: _progressForEpisode,
      canMarkWatched: false,
      emptyEpisodesLabel: l.aiostreamsNoStreams,
      dominantColor: widget.dominantColor,
      colorMatchReady: widget.colorMatchReady,
      seasonPickerFocusNode: _seasonFocusNode,
      onSeasonSelected: (s) => setState(() => _selectedSeason = s),
      onEpisodeSelected: (episode, {startPosition}) => _selectEpisode(episode),
      onMarkEpisode: (_, {required watched}) {},
      onMarkSeason: (_, {required watched}) {},
      onExitTop: _seasonFocusNode.requestFocus,
      scrollController: widget.scrollController,
    );
  }
}

// ---------------------------------------------------------------------------
// Stream picker bottom sheet
// ---------------------------------------------------------------------------

/// Public stream-picker bottom sheet — reused by continue-watching flows.
class AIOStreamsStreamPickerSheet extends StatefulWidget {
  const AIOStreamsStreamPickerSheet({
    super.key,
    required this.integrationId,
    required this.type,
    required this.id,
    required this.apiService,
    required this.onStreamSelected,
  });

  final int integrationId;
  final String type;
  final String id;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsStream) onStreamSelected;

  @override
  State<AIOStreamsStreamPickerSheet> createState() =>
      _AIOStreamsStreamPickerSheetState();
}

class _AIOStreamsStreamPickerSheetState
    extends State<AIOStreamsStreamPickerSheet> {
  late final Future<List<AIOStreamsStream>> _future = widget.apiService
      .getStreams(widget.integrationId, widget.type, widget.id);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DpadRegion(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Text(
                l.aiostreamsSelectStream,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<AIOStreamsStream>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(l.aiostreamsLoadingStreams),
                          ],
                        ),
                      ),
                    );
                  }

                  final streams = snapshot.data ?? const [];

                  if (streams.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(child: Text(l.aiostreamsNoStreams)),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: streams.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final stream = streams[index];
                      return DpadInkWell(
                        borderRadius: BorderRadius.zero,
                        onTap: () => widget.onStreamSelected(stream),
                        autofocus: index == 0,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stream.name.isEmpty
                                          ? stream.title
                                          : stream.name,
                                      style: theme.textTheme.bodyLarge,
                                    ),
                                    if (stream.title.isNotEmpty &&
                                        stream.name.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        stream.title,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 2, left: 8),
                                child: Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
