import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_reveal_slot.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
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

  /// True once the palette extraction has resolved (with a colour or not).
  /// Gates the hero's backdrop reveal so the art and its colour-match fade
  /// in together instead of the backdrop popping and the tint snapping after.
  bool _colorMatchResolved = false;

  /// Wired into the wide-layout cast row so pressing up off the cast cards
  /// returns focus to the primary Play button (the raw-`Focus` [CastStrip]
  /// consumes every arrow key, so it must hand vertical navigation back
  /// explicitly).
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'vodPlayButton');

  @override
  void dispose() {
    _playFocusNode.dispose();
    super.dispose();
  }

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
              playFocusNode: _playFocusNode,
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
                  playFocusNode: _playFocusNode,
                );
              },
            ),
    );
  }
}

class _VodDetailsBody extends StatelessWidget {
  const _VodDetailsBody({
    required this.item,
    required this.playFocusNode,
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

  /// Passed straight to [BackdropDetailHero.colorMatchReady] - true once the
  /// palette extraction has resolved, so the hero can fade the backdrop and
  /// its colour-match in together.
  final bool colorMatchReady;

  /// Focus target for the wide cast row's "up" hop - the primary Play button.
  final FocusNode playFocusNode;

  /// Palette-extracted tone from the backdrop/poster; falls back to the
  /// theme surface. Matches the Series detail page's colour-match treatment.
  /// Raw dominant swatch from [resolveDominantBackdropColor]; toned per
  /// layout below (a phone needs a lighter, more saturated wash than a TV).
  final Color? dominantColor;

  static const double _wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = _ResolvedVodDetails(item, info);
    final progress = _resumeProgress;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < _wideBreakpoint;
        final swatch = dominantColor;
        final bg = swatch != null
            ? deepBackdropTone(swatch, vivid: compact)
            : theme.colorScheme.surface;
        if (compact) {
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
    final richCast = details.richCast;
    final l = AppLocalizations.of(context);
    // The poster + details Row fills the available height (its own info column
    // scrolls); the rich cast row is pinned full-width below it, kept out of
    // that vertical scrollable so left/right card navigation never drags the
    // page. Mirrors the Series detail layout.
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
          ),
          CastRevealSlot(
            topPadding: MediaBrowsingMetrics.contentPadding,
            // Same scrollable locked-focus row the Series detail uses. It is
            // pinned here (always on-screen), so no reveal callback; up hops
            // back to the Play button. Eases in once VodInfo resolves.
            castRow: (richCast == null || richCast.isEmpty)
                ? null
                : Semantics(
                    label: l.vodCast,
                    container: true,
                    child: CastStrip(
                      members: richCast,
                      onNavigateUp: playFocusNode.requestFocus,
                    ),
                  ),
          ),
        ],
      ),
    );

    // Colour-matched scrim, same treatment as the Series detail page.
    return BackdropDetailHero(
      backdropUrl: backdrop,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      colorMatchReady: colorMatchReady,
      contentPadding: const EdgeInsets.only(top: 24, bottom: 24),
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
          _infoColumn(
            context,
            theme,
            details,
            progress,
            fullWidthButton: true,
            compact: true,
          ),
        ],
      ),
    );

    // Backdrop capped to half the viewport (not full height) so the poster/
    // title/synopsis aren't pushed below the fold, and stays fixed in place
    // - `content` scrolls over/past it - matching the Series detail page's
    // mobile layout. A lighter top/mid scrim than the wide layout so the
    // real backdrop colour still reads in the band (portrait shows so little
    // of it that a heavy scrim leaves it near-black).
    final bandHeight = MediaQuery.sizeOf(context).height * 0.5;
    return BackdropDetailHero(
      backdropUrl: backdrop,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.8), bg],
      colorMatchReady: colorMatchReady,
      // Let the poster/title ride well up into the lower half of the
      // backdrop (standard mobile hero look) rather than clearing it.
      contentPadding: EdgeInsets.only(top: bandHeight * 0.44, bottom: 24),
      content: content,
    );
  }

  Widget _infoColumn(
    BuildContext context,
    ThemeData theme,
    _ResolvedVodDetails details,
    Progress? progress, {
    bool fullWidthButton = false,
    bool compact = false,
  }) {
    final l = AppLocalizations.of(context);
    final buttonLabel = progress == null
        ? l.vodPlayMovie
        : (_timeLeftLabel(context, progress) ?? l.vodContinueMovie);
    final richCast = details.richCast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ItemMetaInfo(
          name: details.name,
          clearLogoUrl: details.clearLogoUrl,
          primaryActionFocusNode: playFocusNode,
          chips: [
            if (details.year != null) details.year!,
            if (details.genre != null) details.genre!,
            if (details.duration != null) details.duration!,
            if (details.rating != null) '★ ${details.rating}',
            if (details.containerExtension != null)
              details.containerExtension!.toUpperCase(),
          ],
          buttonLabel: buttonLabel,
          onPlay: () => _play(
            details,
            startPosition: progress?.positionSeconds.toDouble(),
          ),
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
            // The comma-separated `cast` string only earns a credit line when
            // there is no rich cast row (wide: below the poster; narrow: the
            // picker chip under the synopsis) - otherwise it just repeats it.
            if (details.cast != null && (richCast == null || richCast.isEmpty))
              MetaCreditLine(label: 'Cast', value: details.cast!),
          ],
        ),
        // Wide layout renders the cast row full-width below the poster +
        // details block (see _buildWide); only the narrow layout keeps it
        // inline here, as a compact picker chip under the synopsis.
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
