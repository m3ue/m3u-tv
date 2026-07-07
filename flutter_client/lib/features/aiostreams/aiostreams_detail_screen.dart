import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class AIOStreamsDetailScreen extends StatefulWidget {
  const AIOStreamsDetailScreen({
    super.key,
    required this.item,
    required this.integrationId,
    required this.apiService,
    required this.onPlay,
    this.onSidebarActivate,
  });

  final AIOStreamsItem item;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(PlayerArgs) onPlay;
  final VoidCallback? onSidebarActivate;

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
    required String type,
    required String id,
    required String title,
  }) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _StreamPickerSheet(
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
                // AIOStreams streams are on-demand VOD/series regardless of
                // how the type is labelled in the Stremio catalog.
                type: type == 'series' ? 'series' : 'vod',
                headers: _proxyRequestHeaders(stream.behaviorHints),
                metadata: <String, Object?>{
                  'aiostreams': true,
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
    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.item.name),
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
                onEpisodeSelected: (episodeId, episodeTitle) =>
                    _openStreamPicker(
                      type: 'series',
                      id: episodeId,
                      title: episodeTitle,
                    ),
              );
            }
            return _MovieBody(
              item: item,
              isLoading: isLoading,
              onGetStreams: () => _openStreamPicker(
                type: 'movie',
                id: item.id,
                title: item.name,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movie body — mirrors VodDetailsScreen layout
// ---------------------------------------------------------------------------

class _MovieBody extends StatelessWidget {
  const _MovieBody({
    required this.item,
    required this.isLoading,
    required this.onGetStreams,
  });

  final AIOStreamsItem item;
  final bool isLoading;
  final VoidCallback onGetStreams;

  static const double _wideBreakpoint = 600;

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
    final backdrop = item.background;
    final content = Padding(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 220,
            child: AspectRatio(
              aspectRatio: 0.68,
              child: ResilientMediaImage(
                imageUrl: item.poster,
                fallbackIcon: Icons.movie,
                borderRadius: MediaBrowsingMetrics.cardRadius,
                fallbackTitle: item.name,
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
    );

    if (backdrop == null) return content;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(backdrop, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.85),
                theme.colorScheme.surface,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.sizeOf(context).height * 0.1,
            ),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final theme = Theme.of(context);
    final backdrop = item.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null)
                Image.network(backdrop, fit: BoxFit.cover)
              else
                ResilientMediaImage(
                  imageUrl: item.poster,
                  fallbackIcon: Icons.movie,
                  borderRadius: 0,
                  fallbackTitle: item.name,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, theme.colorScheme.surface],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _infoColumn(context, theme, fullWidthButton: true),
          ),
        ),
      ],
    );
  }

  Widget _infoColumn(
    BuildContext context,
    ThemeData theme, {
    bool fullWidthButton = false,
  }) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.name, style: theme.textTheme.headlineMedium),
        const SizedBox(height: MediaBrowsingMetrics.itemGap),
        Wrap(
          spacing: MediaBrowsingMetrics.itemGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            if (item.year != null) _MetadataChip(label: item.year!),
            if (item.imdbRating != null)
              _MetadataChip(label: '★ ${item.imdbRating}'),
            ...item.genres.take(3).map((g) => _MetadataChip(label: g)),
          ],
        ),
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        if (fullWidthButton)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              autofocus: true,
              onPressed: isLoading ? null : onGetStreams,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.aiostreamsGetStreams),
            ),
          )
        else
          FilledButton.icon(
            autofocus: true,
            onPressed: isLoading ? null : onGetStreams,
            icon: const Icon(Icons.play_arrow),
            label: Text(l.aiostreamsGetStreams),
          ),
        const SizedBox(height: MediaBrowsingMetrics.pagePadding),
        if (isLoading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        if (item.description != null && item.description!.isNotEmpty)
          Text(
            item.description!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Series body — mirrors SeriesDetailsScreen layout
// ---------------------------------------------------------------------------

class _SeriesBody extends StatefulWidget {
  const _SeriesBody({
    required this.item,
    required this.onEpisodeSelected,
  });

  final AIOStreamsItem item;
  final void Function(String episodeId, String episodeTitle) onEpisodeSelected;

  @override
  State<_SeriesBody> createState() => _SeriesBodyState();
}

class _SeriesBodyState extends State<_SeriesBody> {
  int? _selectedSeason;

  Map<int, List<AIOStreamsVideo>> get _episodesBySeason {
    final map = <int, List<AIOStreamsVideo>>{};
    for (final v in widget.item.videos) {
      map.putIfAbsent(v.season, () => []).add(v);
    }
    for (final episodes in map.values) {
      episodes.sort((a, b) => a.episode.compareTo(b.episode));
    }
    return map;
  }

  List<int> get _sortedSeasons => _episodesBySeason.keys.toList()..sort();

  int? get _resolvedSeason {
    final seasons = _sortedSeasons;
    if (seasons.isEmpty) return null;
    return _selectedSeason ?? seasons.first;
  }

  List<AIOStreamsVideo> _episodes(int? season) =>
      season == null ? const [] : _episodesBySeason[season] ?? const [];

  void _onEpisodeTap(AIOStreamsVideo video) {
    final title = video.title.isNotEmpty ? video.title : widget.item.name;
    widget.onEpisodeSelected(video.id, title);
  }

  static const double _wideBreakpoint = 600;

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
    final seasons = _sortedSeasons;
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
    final item = widget.item;
    final backdrop = item.background;

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
                imageUrl: item.poster,
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
                Text(item.name, style: theme.textTheme.headlineMedium),
                if (item.imdbRating != null) ...[
                  const SizedBox(height: 8),
                  Chip(
                    label: Text('★ ${item.imdbRating}'),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ],
                if (item.description != null &&
                    item.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    item.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                if (seasons.isNotEmpty)
                  _AIOSeasonChips(
                    seasons: seasons,
                    selectedSeason: seasonNumber,
                    onSeasonSelected: (s) =>
                        setState(() => _selectedSeason = s),
                  ),
                const SizedBox(height: 16),
                Expanded(
                  child: episodes.isEmpty
                      ? Center(
                          child: Text(
                            AppLocalizations.of(context).aiostreamsNoStreams,
                          ),
                        )
                      : _AIOEpisodeList(
                          episodes: episodes,
                          onEpisodeSelected: _onEpisodeTap,
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
                        colors: [
                          Colors.transparent,
                          theme.colorScheme.surface,
                        ],
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
                        colors: [
                          Colors.transparent,
                          theme.colorScheme.surface,
                        ],
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
    final seasons = _sortedSeasons;
    final seasonNumber = _resolvedSeason;
    final episodes = _episodes(seasonNumber);
    final item = widget.item;
    final backdrop = item.background;

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
                        imageUrl: item.poster,
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
                            item.name,
                            style: theme.textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (item.imdbRating != null) ...[
                            const SizedBox(height: 4),
                            Chip(
                              label: Text('★ ${item.imdbRating}'),
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
        if (item.description != null && item.description!.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                item.description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _AIOSeasonChips(
              seasons: seasons,
              selectedSeason: seasonNumber,
              onSeasonSelected: (s) => setState(() => _selectedSeason = s),
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
                final ep = episodes[index];
                return _AIOEpisodeTile(
                  video: ep,
                  autofocus: index == 0,
                  onTap: () => _onEpisodeTap(ep),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Season chip row — mirrors _SeasonChips from series_details_screen.dart
// ---------------------------------------------------------------------------

class _AIOSeasonChips extends StatefulWidget {
  const _AIOSeasonChips({
    required this.seasons,
    required this.selectedSeason,
    required this.onSeasonSelected,
  });

  final List<int> seasons;
  final int? selectedSeason;
  final ValueChanged<int> onSeasonSelected;

  @override
  State<_AIOSeasonChips> createState() => _AIOSeasonChipsState();
}

class _AIOSeasonChipsState extends State<_AIOSeasonChips> {
  final ScrollController _controller = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    final position = _controller.position;
    _controller.jumpTo(
      (_controller.offset + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.seasons.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Row(
            children: widget.seasons
                .map(
                  (season) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CategoryFilterChip(
                      label: l.homeSeason(season),
                      isSelected: season == widget.selectedSeason,
                      onTap: () => widget.onSeasonSelected(season),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode list — scrollable wrapper for wide layout
// ---------------------------------------------------------------------------

class _AIOEpisodeList extends StatelessWidget {
  const _AIOEpisodeList({
    required this.episodes,
    required this.onEpisodeSelected,
  });

  final List<AIOStreamsVideo> episodes;
  final ValueChanged<AIOStreamsVideo> onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: episodes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final ep = episodes[index];
        return _AIOEpisodeTile(
          video: ep,
          autofocus: index == 0,
          onTap: () => onEpisodeSelected(ep),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Episode tile — mirrors _EpisodeTile without progress bar
// ---------------------------------------------------------------------------

class _AIOEpisodeTile extends StatefulWidget {
  const _AIOEpisodeTile({
    required this.video,
    required this.autofocus,
    required this.onTap,
  });

  final AIOStreamsVideo video;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  State<_AIOEpisodeTile> createState() => _AIOEpisodeTileState();
}

class _AIOEpisodeTileState extends State<_AIOEpisodeTile> {
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final video = widget.video;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: DpadFocusable(
        autofocus: widget.autofocus,
        focusNode: _focusNode,
        onSelect: widget.onTap,
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
          child: InkWell(
            onTap: () {
              _focusNode.requestFocus();
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 120,
                      height: 68,
                      child: video.thumbnail != null
                          ? Image.network(
                              video.thumbnail!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  _episodeNumberBadge(colorScheme),
                            )
                          : _episodeNumberBadge(colorScheme),
                    ),
                  ),
                  const SizedBox(width: 12),
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
                                      text: 'E${video.episode} · ',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    TextSpan(text: video.title),
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
                        if (video.released != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            video.released!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (video.description != null &&
                            video.description!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            video.description!,
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
        ),
      ),
    );
  }

  Widget _episodeNumberBadge(ColorScheme colorScheme) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          'E${widget.video.episode}',
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

// ---------------------------------------------------------------------------
// Stream picker bottom sheet
// ---------------------------------------------------------------------------

class _StreamPickerSheet extends StatefulWidget {
  const _StreamPickerSheet({
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
  State<_StreamPickerSheet> createState() => _StreamPickerSheetState();
}

class _StreamPickerSheetState extends State<_StreamPickerSheet> {
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

// ---------------------------------------------------------------------------
// Shared chip widget (mirrors _MetadataChip in vod_details_screen.dart)
// ---------------------------------------------------------------------------

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}
