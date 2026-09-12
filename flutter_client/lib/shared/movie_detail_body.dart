import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_reveal_slot.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart'
    show detailAppBarHeight;
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Shared layout scaffold for a movie-style detail page - poster + meta +
/// cast strip over a colour-matched BackdropDetailHero. Used by both the
/// Xtream VOD detail and the AIOStreams movie detail so the two
/// cannot drift on poster sizing, breakpoint, scrim, synopsis measure, or
/// cast composition (VodDetailsScreen / AIOStreamsDetailScreen). Per-source
/// behaviour (what the primary button does,
/// where the data comes from) stays with the caller and arrives here as
/// plain values + callbacks.
class MovieDetailBody extends StatefulWidget {
  const MovieDetailBody({
    super.key,
    required this.name,
    required this.chips,
    required this.credits,
    required this.castSemanticLabel,
    required this.primaryButtonLabel,
    required this.onPrimary,
    required this.isLoading,
    required this.colorMatchReady,
    this.posterUrl,
    this.backdropUrl,
    this.clearLogoUrl,
    this.plot,
    this.richCast,
    this.onStartOver,
    this.progressValue,
    this.dominantColor,
    this.fallbackIcon = Icons.movie,
  });

  final String name;
  final String? posterUrl;
  final String? backdropUrl;
  final String? clearLogoUrl;
  final List<String> chips;
  final String? plot;
  final List<MetaCreditLine> credits;
  final List<CastMember>? richCast;
  final String castSemanticLabel;

  final String primaryButtonLabel;
  final VoidCallback onPrimary;

  /// Resume affordances - only VOD passes these; AIOStreams leaves them null.
  final VoidCallback? onStartOver;
  final double? progressValue;

  final bool isLoading;
  final IconData fallbackIcon;

  /// Palette-extracted backdrop tone + whether it has resolved. Drives the
  /// held-then-cross-faded hero (see [BackdropDetailHero.colorMatchReady]).
  final Color? dominantColor;
  final bool colorMatchReady;

  @override
  State<MovieDetailBody> createState() => _MovieDetailBodyState();
}

class _MovieDetailBodyState extends State<MovieDetailBody> {
  static const double _wideBreakpoint = 600;

  /// Focus target for the wide cast strip's "up" hop - the primary button.
  final FocusNode _primaryFocusNode = FocusNode(
    debugLabel: 'movieDetailPrimary',
  );

  @override
  void dispose() {
    _primaryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final compact = constraints.maxWidth < _wideBreakpoint;
        final swatch = widget.dominantColor;
        final bg = swatch != null
            ? deepBackdropTone(swatch, vivid: compact)
            : theme.colorScheme.surface;
        return compact
            ? _buildNarrow(context, theme, bg)
            : _buildWide(context, theme, bg);
      },
    );
  }

  Widget _buildWide(BuildContext context, ThemeData theme, Color bg) {
    final richCast = widget.richCast;
    final scale = FontSizeScope.scaleOf(context);
    // Poster + scrolling info column fill the height; the rich cast strip is
    // pinned full-width below, out of that scroll view so left/right card
    // navigation never drags the page.
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
                  width: 220 * scale,
                  child: AspectRatio(
                    aspectRatio: 0.68,
                    child: ResilientMediaImage(
                      imageUrl: widget.posterUrl,
                      fallbackIcon: widget.fallbackIcon,
                      borderRadius: MediaBrowsingMetrics.cardRadius,
                      fallbackTitle: widget.name,
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
                    label: widget.castSemanticLabel,
                    container: true,
                    child: CastStrip(
                      members: richCast,
                      onNavigateUp: _primaryFocusNode.requestFocus,
                    ),
                  ),
          ),
        ],
      ),
    );

    return BackdropDetailHero(
      backdropUrl: widget.backdropUrl,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      colorMatchReady: widget.colorMatchReady,
      contentPadding: EdgeInsets.only(
        top: 24 + detailAppBarHeight(context),
        bottom: 24,
      ),
      content: content,
    );
  }

  Widget _buildNarrow(BuildContext context, ThemeData theme, Color bg) {
    final scale = FontSizeScope.scaleOf(context);
    final poster = SizedBox(
      width: 120 * scale,
      child: AspectRatio(
        aspectRatio: 0.68,
        child: ResilientMediaImage(
          imageUrl: widget.posterUrl,
          fallbackIcon: widget.fallbackIcon,
          borderRadius: MediaBrowsingMetrics.cardRadius,
          fallbackTitle: widget.name,
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
      backdropUrl: widget.backdropUrl,
      backdropHeight: bandHeight,
      contentAlignment: Alignment.topLeft,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.2), bg.withValues(alpha: 0.8), bg],
      colorMatchReady: widget.colorMatchReady,
      contentPadding: EdgeInsets.only(
        top: bandHeight * 0.44 + detailAppBarHeight(context),
        bottom: 24,
      ),
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
    final richCast = widget.richCast;
    // Keep the synopsis to a comfortable measure on TV/desktop, full width on
    // a phone - matches SeriesDetailBody.
    final plotMaxWidth = compact
        ? double.infinity
        : MediaQuery.sizeOf(context).width * 0.6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ItemMetaInfo(
          name: widget.name,
          clearLogoUrl: widget.clearLogoUrl,
          primaryActionFocusNode: _primaryFocusNode,
          chips: widget.chips,
          buttonLabel: widget.primaryButtonLabel,
          onPlay: widget.onPrimary,
          onStartOver: widget.onStartOver,
          progressValue: widget.progressValue,
          fullWidthButton: fullWidthButton,
          isLoading: widget.isLoading,
          plot: widget.plot,
          plotMaxWidth: plotMaxWidth,
          plotMaxLines: 4,
          credits: widget.credits,
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
                    semanticLabel: widget.castSemanticLabel,
                    compact: true,
                    onShowAll: () => showAllCast(context, richCast),
                    allCastSemanticLabel: l.castShowAll,
                  ),
          ),
      ],
    );
  }
}
