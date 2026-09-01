import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class VodDetailsScreen extends StatefulWidget {
  const VodDetailsScreen({
    super.key,
    required this.item,
    this.xtreamService,
    this.progressList = const [],
    this.onPlay,
    this.onSidebarActivate,
  });

  final VodItem item;
  final XtreamService? xtreamService;
  final List<Progress> progressList;
  final void Function(PlayerArgs)? onPlay;
  final VoidCallback? onSidebarActivate;

  @override
  State<VodDetailsScreen> createState() => _VodDetailsScreenState();
}

class _VodDetailsScreenState extends State<VodDetailsScreen> {
  late final Future<VodInfo?>? _future = widget.xtreamService
      ?.getVodInfo(widget.item.id)
      .then((info) {
        unawaited(
          _resolveDominantColor(
            _notEmpty(info.backdropUrl) ??
                _notEmpty(info.coverUrl) ??
                widget.item.logoUrl,
          ),
        );
        return info;
      });

  Color? _dominantColor;

  @override
  void initState() {
    super.initState();
    // No xtreamService means the FutureBuilder branch never runs (and never
    // resolves a colour from fetched VodInfo) - fall back to the item's own
    // poster so this path still gets the colour-match treatment.
    if (_future == null) {
      unawaited(_resolveDominantColor(widget.item.logoUrl));
    }
  }

  /// Extracts a dominant tone from the backdrop (or poster, if no backdrop)
  /// so the hero can bleed it past the image edge, matching the Series
  /// detail page. Any failure just leaves the theme surface as-is.
  Future<void> _resolveDominantColor(String? url) async {
    final color = await resolveDominantBackdropColor(url);
    if (color != null && mounted) setState(() => _dominantColor = color);
  }

  @override
  Widget build(BuildContext context) {
    return ItemDetailScaffold(
      title: widget.item.name,
      onSidebarActivate: widget.onSidebarActivate,
      body: _future == null
          ? _VodDetailsBody(
              item: widget.item,
              progressList: widget.progressList,
              onPlay: widget.onPlay,
              dominantColor: _dominantColor,
            )
          : FutureBuilder<VodInfo?>(
              future: _future,
              builder: (context, snapshot) {
                return _VodDetailsBody(
                  item: widget.item,
                  info: snapshot.hasError ? null : snapshot.data,
                  isLoading: snapshot.connectionState != ConnectionState.done,
                  progressList: widget.progressList,
                  onPlay: widget.onPlay,
                  dominantColor: _dominantColor,
                );
              },
            ),
    );
  }
}

class _VodDetailsBody extends StatelessWidget {
  const _VodDetailsBody({
    required this.item,
    this.info,
    this.isLoading = false,
    this.progressList = const [],
    this.onPlay,
    this.dominantColor,
  });

  final VodItem item;
  final VodInfo? info;
  final bool isLoading;
  final List<Progress> progressList;
  final void Function(PlayerArgs)? onPlay;

  /// Palette-extracted tone from the backdrop/poster; falls back to the
  /// theme surface. Matches the Series detail page's colour-match treatment.
  final Color? dominantColor;

  static const double _wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dominantColor ?? theme.colorScheme.surface;
    final details = _ResolvedVodDetails(item, info);
    final progress = _resumeProgress;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return _buildNarrow(context, theme, bg, details, progress);
        }
        return _buildWide(context, theme, bg, details, progress);
      },
    );
  }

  Progress? get _resumeProgress {
    for (final progress in progressList) {
      if (progress.contentType == ContentType.vod &&
          progress.streamId == item.id &&
          progress.positionSeconds >= 30 &&
          !progress.completed) {
        return progress;
      }
    }
    return null;
  }

  Widget _buildWide(
    BuildContext context,
    ThemeData theme,
    Color bg,
    _ResolvedVodDetails details,
    Progress? progress,
  ) {
    final backdrop = details.backdropUrl;
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
                imageUrl: details.coverUrl,
                fallbackIcon: Icons.movie,
                borderRadius: MediaBrowsingMetrics.cardRadius,
                fallbackTitle: details.name,
              ),
            ),
          ),
          const SizedBox(width: MediaBrowsingMetrics.pagePadding),
          Expanded(
            child: SingleChildScrollView(
              child: _infoColumn(context, theme, details, progress),
            ),
          ),
        ],
      ),
    );

    // Always use the backdrop Stack layout so the poster stays bottom-aligned
    // before and after the backdrop URL loads in, avoiding a layout jump.
    // Colour-matched scrim, same treatment as the Series detail page.
    return BackdropDetailHero(
      backdropUrl: backdrop,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      contentPadding: EdgeInsets.only(
        bottom: MediaQuery.sizeOf(context).height * 0.1,
      ),
      content: content,
    );
  }

  Widget _buildNarrow(
    BuildContext context,
    ThemeData theme,
    Color bg,
    _ResolvedVodDetails details,
    Progress? progress,
  ) {
    final backdrop = details.backdropUrl;
    final poster = SizedBox(
      width: 120,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: ResilientMediaImage(
          imageUrl: details.coverUrl,
          fallbackIcon: Icons.movie,
          borderRadius: MediaBrowsingMetrics.cardRadius,
          fallbackTitle: details.name,
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
          _infoColumn(context, theme, details, progress, fullWidthButton: true),
        ],
      ),
    );

    // Backdrop capped to half the viewport (not full height) so the poster/
    // title/synopsis aren't pushed below the fold, and stays fixed in place
    // - `content` scrolls over/past it - matching the Series detail page's
    // mobile layout.
    final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
    return BackdropDetailHero(
      backdropUrl: backdrop,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      // Let the poster/title ride well up into the lower half of the
      // backdrop (standard mobile hero look) rather than clearing it.
      contentPadding: EdgeInsets.only(top: bandHeight * 0.55, bottom: 24),
      content: content,
    );
  }

  Widget _infoColumn(
    BuildContext context,
    ThemeData theme,
    _ResolvedVodDetails details,
    Progress? progress, {
    bool fullWidthButton = false,
  }) {
    final l = AppLocalizations.of(context);
    final buttonLabel = progress == null
        ? l.vodPlayMovie
        : (_timeLeftLabel(context, progress) ?? l.vodContinueMovie);
    return ItemMetaInfo(
      name: details.name,
      chips: [
        if (details.year != null) details.year!,
        if (details.genre != null) details.genre!,
        if (details.duration != null) details.duration!,
        if (details.rating != null) '★ ${details.rating}',
        if (details.containerExtension != null)
          details.containerExtension!.toUpperCase(),
      ],
      buttonLabel: buttonLabel,
      onPlay: () =>
          _play(details, startPosition: progress?.positionSeconds.toDouble()),
      onStartOver: progress == null
          ? null
          // ignore: prefer_int_literals
          : () => _play(details, startPosition: 0.0),
      fullWidthButton: fullWidthButton,
      progressValue: _progressValue(progress),
      isLoading: isLoading,
      plot: details.plot ?? 'No synopsis available.',
      credits: [
        if (details.director != null)
          MetaCreditLine(label: 'Director', value: details.director!),
        if (details.cast != null)
          MetaCreditLine(label: 'Cast', value: details.cast!),
      ],
    );
  }

  double? _progressValue(Progress? progress) {
    final duration = progress?.durationSeconds;
    if (progress == null || duration == null || duration <= 0) return null;
    return (progress.positionSeconds / duration).clamp(0.0, 1.0);
  }

  String? _timeLeftLabel(BuildContext context, Progress? progress) {
    final duration = progress?.durationSeconds;
    if (progress == null || duration == null || duration <= 0) return null;
    final remainingSeconds = (duration - progress.positionSeconds).clamp(
      0,
      duration,
    );
    final totalMinutes = (remainingSeconds / 60).ceil().clamp(1, duration);
    final l = AppLocalizations.of(context);
    if (totalMinutes < 60) return l.vodTimeLeftMinutes(totalMinutes);
    return l.vodTimeLeftHoursMinutes(totalMinutes ~/ 60, totalMinutes % 60);
  }

  void _play(_ResolvedVodDetails details, {double? startPosition}) {
    onPlay?.call(
      PlayerArgs(
        streamUrl: item.streamUrl,
        title: details.name,
        type: 'vod',
        streamId: item.id,
        startPosition: startPosition,
        metadata: <String, Object?>{
          'title': details.name,
          if (details.containerExtension != null)
            'container_extension': details.containerExtension,
          if (details.duration != null) 'duration': details.duration,
          if (details.rating != null) 'rating': '${details.rating}',
          if (details.backdropUrl != null) 'backdrop_url': details.backdropUrl,
          if (details.coverUrl != null) 'thumbnail_url': details.coverUrl,
          if (details.tmdbId != null) 'tmdb_id': details.tmdbId,
          if (details.plot != null) 'plot': details.plot,
          if (details.edlUrl != null) 'edl_url': details.edlUrl,
        },
      ),
    );
  }
}

class _ResolvedVodDetails {
  _ResolvedVodDetails(this.item, this.info);

  final VodItem item;
  final VodInfo? info;

  String get name => _notEmpty(info?.name) ?? item.name;
  String? get plot => _notEmpty(info?.plot);
  String? get genre => _notEmpty(info?.genre);
  String? get director => _notEmpty(info?.director);
  String? get cast => _notEmpty(info?.cast);
  String? get year => _notEmpty(info?.year) ?? _notEmpty(info?.releaseDate);
  String? get duration => _notEmpty(info?.duration);
  double? get rating => info?.rating ?? item.rating;
  String? get coverUrl => _notEmpty(info?.coverUrl) ?? _notEmpty(item.logoUrl);
  String? get backdropUrl => _notEmpty(info?.backdropUrl);
  String? get containerExtension =>
      _notEmpty(info?.containerExtension) ?? item.containerExtension;
  int? get tmdbId => info?.tmdbId;
  String? get edlUrl => _notEmpty(info?.edlUrl);
}

String? _notEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
