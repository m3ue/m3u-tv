import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_reveal_slot.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
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
  });

  final AIOStreamsItem item;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(PlayerArgs) onPlay;
  final VoidCallback? onSidebarActivate;
  final AppStateController? appStateController;

  @override
  State<AIOStreamsDetailScreen> createState() => _AIOStreamsDetailScreenState();
}

class _AIOStreamsDetailScreenState extends State<AIOStreamsDetailScreen> {
  late final Future<AIOStreamsItem?> _metaFuture = widget.apiService.getMeta(
    widget.integrationId,
    widget.item.type,
    widget.item.id,
  );

  bool get _isSeries => widget.item.type == 'series';

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
      body: FutureBuilder<AIOStreamsItem?>(
        future: _metaFuture,
        builder: (context, snapshot) {
          final item = snapshot.data ?? widget.item;
          final isLoading = snapshot.connectionState != ConnectionState.done;
          if (_isSeries) {
            if (isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return _SeriesBody(
              item: item,
              appStateController: widget.appStateController,
              onEpisodeSelected: (video) => _openStreamPicker(
                item: item,
                type: 'series',
                id: video.id,
                title: video.title.isNotEmpty ? video.title : item.name,
                video: video,
              ),
            );
          }
          return _MovieBody(
            item: item,
            isLoading: isLoading,
            onGetStreams: () => _openStreamPicker(
              item: item,
              type: 'movie',
              id: item.id,
              title: item.name,
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movie body — mirrors VodDetailsScreen layout
// ---------------------------------------------------------------------------

class _MovieBody extends StatefulWidget {
  const _MovieBody({
    required this.item,
    required this.isLoading,
    required this.onGetStreams,
  });

  final AIOStreamsItem item;
  final bool isLoading;
  final VoidCallback onGetStreams;

  @override
  State<_MovieBody> createState() => _MovieBodyState();
}

class _MovieBodyState extends State<_MovieBody> {
  static const double _wideBreakpoint = 600;

  /// Focus node for the "Get Streams" button, so the wide-layout cast strip
  /// can hop back up to it (mirrors VodDetailsScreen's playFocusNode).
  final FocusNode _getStreamsFocusNode = FocusNode(
    debugLabel: 'aioGetStreams',
  );

  @override
  void dispose() {
    _getStreamsFocusNode.dispose();
    super.dispose();
  }

  AIOStreamsItem get _item => widget.item;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        if (constraints.maxWidth < _wideBreakpoint) {
          return _buildNarrow(context, theme);
        }
        return _buildWide(context, theme);
      },
    );
  }

  Widget _buildWide(BuildContext context, ThemeData theme) {
    final l = AppLocalizations.of(context);
    final richCast = _item.richCast;
    // Poster + scrolling info column fill the height; the rich cast strip is
    // pinned full-width below, out of that scroll view so left/right card
    // navigation never drags the page - identical to VodDetailsScreen._buildWide.
    final content = Padding(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 220,
                  child: AspectRatio(
                    aspectRatio: 0.68,
                    child: ResilientMediaImage(
                      imageUrl: _item.poster,
                      fallbackIcon: Icons.movie,
                      borderRadius: MediaBrowsingMetrics.cardRadius,
                      fallbackTitle: _item.name,
                    ),
                  ),
                ),
                const SizedBox(width: MediaBrowsingMetrics.pagePadding),
                Expanded(
                  child: SingleChildScrollView(
                    child: _infoColumn(context, theme),
                  ),
                ),
              ],
            ),
          ),
          CastRevealSlot(
            topPadding: MediaBrowsingMetrics.contentPadding,
            castRow: (richCast == null || richCast.isEmpty)
                ? null
                : Semantics(
                    label: l.vodCast,
                    container: true,
                    child: CastStrip(
                      members: richCast,
                      onNavigateUp: _getStreamsFocusNode.requestFocus,
                    ),
                  ),
          ),
        ],
      ),
    );

    return BackdropDetailHero(
      backdropUrl: _item.background,
      contentPadding: const EdgeInsets.only(top: 24, bottom: 24),
      content: content,
    );
  }

  Widget _buildNarrow(BuildContext context, ThemeData theme) {
    final poster = SizedBox(
      width: 120,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: ResilientMediaImage(
          imageUrl: _item.poster,
          fallbackIcon: Icons.movie,
          borderRadius: MediaBrowsingMetrics.cardRadius,
          fallbackTitle: _item.name,
        ),
      ),
    );
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          poster,
          const SizedBox(height: 16),
          _infoColumn(context, theme, fullWidthButton: true, compact: true),
        ],
      ),
    );

    final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
    return BackdropDetailHero(
      backdropUrl: _item.background,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      contentPadding: EdgeInsets.only(top: bandHeight * 0.44, bottom: 24),
      content: content,
    );
  }

  Widget _infoColumn(
    BuildContext context,
    ThemeData theme, {
    bool fullWidthButton = false,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context);
    final richCast = _item.richCast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ItemMetaInfo(
          name: _item.name,
          clearLogoUrl: _item.clearLogoUrl,
          primaryActionFocusNode: _getStreamsFocusNode,
          chips: [
            if (_item.year != null) _item.year!,
            if (_item.imdbRating != null) '★ ${_item.imdbRating}',
            ?_runtimeChip(_item.runtime),
            ..._item.genres.take(3),
          ],
          buttonLabel: l.aiostreamsGetStreams,
          onPlay: widget.onGetStreams,
          fullWidthButton: fullWidthButton,
          isLoading: widget.isLoading,
          plot: _item.description,
          credits: [
            if (_item.director != null)
              MetaCreditLine(label: 'Director', value: _item.director!),
            if (_item.writer != null)
              MetaCreditLine(label: 'Writer', value: _item.writer!),
            // The comma-separated `cast` string only earns a credit line when
            // there is no rich cast row - otherwise it just repeats it.
            if ((richCast == null || richCast.isEmpty) && _item.cast != null)
              MetaCreditLine(label: 'Cast', value: _item.cast!),
          ],
        ),
        // Wide renders the cast strip full-width below the poster (see
        // _buildWide); narrow keeps it inline here as a compact picker chip.
        if (compact)
          CastRevealSlot(
            topPadding: MediaBrowsingMetrics.contentPadding,
            castRow: (richCast == null || richCast.isEmpty)
                ? null
                : CastMemberRow(
                    members: richCast,
                    semanticLabel: l.vodCast,
                    compact: true,
                    onShowAll: () => showAllCast(context, richCast),
                    allCastSemanticLabel: l.castShowAll,
                  ),
          ),
      ],
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
  });

  final AIOStreamsItem item;
  final void Function(AIOStreamsVideo video) onEpisodeSelected;
  final AppStateController? appStateController;

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
    final numbers = <int>{
      ...widget.item.seasons.map((s) => s.number),
      ..._videosBySeason.keys,
    }.toList()..sort();
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
    final item = widget.item;
    final seasons = _seasons;
    final seasonNumber = _resolvedSeason;
    final seasonObj = _resolvedSeasonObj;
    final episodes = _episodesForSeason(seasonNumber);
    final progress = _progressForSeries;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < _kAioSeriesCompactBreakpoint;
    final posterWidth = compact ? 120.0 : 200.0;
    final plotMaxWidth = compact ? double.infinity : screenWidth * 0.6;
    final cardWidth = compact
        ? kEpisodeCardWidthCompact
        : kEpisodeCardWidthWide;
    final stripHeight = cardWidth * 9 / 16 + kEpisodeCardTextHeight;

    final l = AppLocalizations.of(context);
    final richCast = item.richCast;
    final seasonCover = seasonObj?.coverUrl;
    final description = (seasonObj?.overview?.trim().isNotEmpty ?? false)
        ? seasonObj!.overview!.trim()
        : item.description;

    final poster = SizedBox(
      width: posterWidth,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: ResilientMediaImage(
          key: ValueKey<String>('aio-season-$seasonNumber'),
          imageUrl: seasonCover ?? item.poster,
          fallbackImageUrls: <String>[
            if (seasonCover != null && item.poster != null) item.poster!,
            if (item.background != null) item.background!,
          ],
          fallbackIcon: Icons.tv,
          borderRadius: MediaBrowsingMetrics.cardRadius,
          fallbackTitle: item.name,
        ),
      ),
    );

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

    final header = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [poster, const SizedBox(height: 16), meta],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              poster,
              const SizedBox(width: MediaBrowsingMetrics.pagePadding),
              Expanded(child: meta),
            ],
          );

    final upper = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        const SizedBox(height: 20),
        Wrap(
          spacing: MediaBrowsingMetrics.itemGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SeasonPicker(
              seasons: seasons,
              selectedSeason: seasonNumber,
              canMarkWatched: false,
              compact: compact,
              focusNode: _seasonFocusNode,
              episodeCountFor: _episodeCountFor,
              fallbackPosterUrl: item.poster,
              onSeasonSelected: (s) => setState(() => _selectedSeason = s),
              onMarkSeason: (_) {},
            ),
            if (compact && richCast != null && richCast.isNotEmpty)
              CastMemberRow(
                members: richCast,
                semanticLabel: l.seriesCast,
                compact: true,
                onShowAll: () => showAllCast(context, richCast),
                allCastSemanticLabel: l.castShowAll,
              ),
          ],
        ),
      ],
    );

    final episodeSection = episodes.isEmpty
        ? Align(
            alignment: Alignment.centerLeft,
            child: Text(l.aiostreamsNoStreams),
          )
        : EpisodeStrip(
            episodes: episodes,
            progressList: progress,
            progressResolver: _progressForEpisode,
            cardWidth: cardWidth,
            horizontal: !compact,
            onEpisodeSelected: (episode, {startPosition}) =>
                _selectEpisode(episode),
            onMarkEpisode: (_, {required watched}) {},
          );

    if (compact) {
      final content = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MediaBrowsingMetrics.pagePadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [upper, const SizedBox(height: 12), episodeSection],
        ),
      );
      final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
      return BackdropDetailHero(
        backdropUrl: item.background,
        backdropHeight: bandHeight,
        contentAlignment: Alignment.topLeft,
        contentPadding: EdgeInsets.only(top: bandHeight * 0.44, bottom: 24),
        content: content,
      );
    }

    final wideContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.pagePadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          upper,
          const SizedBox(height: 12),
          Expanded(
            child: RowScrollRegion(
              onExitTop: _seasonFocusNode.requestFocus,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: stripHeight, child: episodeSection),
                  if (richCast != null && richCast.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      l.seriesCast,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CastRow(members: richCast),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return BackdropDetailHero(
      backdropUrl: item.background,
      contentPadding: const EdgeInsets.only(top: 24, bottom: 24),
      content: wideContent,
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
