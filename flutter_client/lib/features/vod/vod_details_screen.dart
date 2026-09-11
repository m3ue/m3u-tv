import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/movie_detail_body.dart';

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

  /// True once the palette extraction has resolved (with a colour or not).
  /// Gates the hero's backdrop reveal so the art and its colour-match fade
  /// in together instead of the backdrop popping and the tint snapping after.
  bool _colorMatchResolved = false;

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
    if (!mounted) return;
    setState(() {
      if (color != null) _dominantColor = color;
      _colorMatchResolved = true;
    });
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
              colorMatchReady: _colorMatchResolved,
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
                  // A failed info fetch means no backdrop and no palette step
                  // will run - reveal the (surface) hero rather than holding.
                  colorMatchReady: _colorMatchResolved || snapshot.hasError,
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
    this.colorMatchReady = false,
  });

  final VodItem item;
  final VodInfo? info;
  final bool isLoading;
  final List<Progress> progressList;
  final void Function(PlayerArgs)? onPlay;

  /// Passed straight to the shared body's colour-match reveal - true once the
  /// palette extraction has resolved.
  final bool colorMatchReady;

  /// Palette-extracted tone from the backdrop/poster; falls back to the theme
  /// surface inside the shared body.
  final Color? dominantColor;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final details = _ResolvedVodDetails(item, info);
    final progress = _resumeProgress;
    final richCast = details.richCast;
    final buttonLabel = progress == null
        ? l.vodPlayMovie
        : (_timeLeftLabel(context, progress) ?? l.vodContinueMovie);
    return MovieDetailBody(
      name: details.name,
      posterUrl: details.coverUrl,
      backdropUrl: details.backdropUrl,
      clearLogoUrl: details.clearLogoUrl,
      chips: [
        if (details.year != null) details.year!,
        if (details.genre != null) details.genre!,
        if (details.duration != null) details.duration!,
        if (details.rating != null) '★ ${details.rating}',
        if (details.containerExtension != null)
          details.containerExtension!.toUpperCase(),
      ],
      plot: details.plot ?? 'No synopsis available.',
      credits: [
        if (details.director != null)
          MetaCreditLine(label: 'Director', value: details.director!),
        // The comma-separated `cast` string only earns a credit line when
        // there is no rich cast row - otherwise it just repeats it.
        if (details.cast != null && (richCast == null || richCast.isEmpty))
          MetaCreditLine(label: 'Cast', value: details.cast!),
      ],
      richCast: richCast,
      castSemanticLabel: l.vodCast,
      primaryButtonLabel: buttonLabel,
      onPrimary: () =>
          _play(details, startPosition: progress?.positionSeconds.toDouble()),
      onStartOver: progress == null
          ? null
          : () => _play(details, startPosition: 0),
      progressValue: _progressValue(progress),
      isLoading: isLoading,
      dominantColor: dominantColor,
      colorMatchReady: colorMatchReady,
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
  List<CastMember>? get richCast => info?.richCast;
  String? get year => _notEmpty(info?.year) ?? _notEmpty(info?.releaseDate);
  String? get duration => _notEmpty(info?.duration);
  double? get rating => info?.rating ?? item.rating;
  String? get coverUrl => _notEmpty(info?.coverUrl) ?? _notEmpty(item.logoUrl);
  String? get backdropUrl => _notEmpty(info?.backdropUrl);
  String? get clearLogoUrl => _notEmpty(info?.clearLogoUrl);
  String? get containerExtension =>
      _notEmpty(info?.containerExtension) ?? item.containerExtension;
  int? get tmdbId => info?.tmdbId;
  String? get edlUrl => _notEmpty(info?.edlUrl);
}

String? _notEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
