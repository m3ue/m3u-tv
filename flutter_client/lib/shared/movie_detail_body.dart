import 'dart:async';

import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/backdrop_detail_hero.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/cast_reveal_slot.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart'
    show detailAppBarHeight;
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart'
    show CastRow, RelatedRow, RowScrollRegion;

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
    this.richRelated,
    this.onRelatedTap,
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

  /// TMDB recommendations already in the user's library, shown as the
  /// "Related" row directly below the cast row. Null/empty renders nothing.
  final List<RelatedItem>? richRelated;

  /// Required whenever [richRelated] is non-empty - opens that item's own
  /// detail screen. The caller (Xtream vs AIOStreams) owns the navigation,
  /// this widget only reports the tap.
  final ValueChanged<RelatedItem>? onRelatedTap;

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

  /// Focus target for the wide layout's top-row exit (RowScrollRegion's
  /// onExitTop) - the primary button.
  final FocusNode _primaryFocusNode = FocusNode(
    debugLabel: 'movieDetailPrimary',
  );

  /// Owned externally (rather than left to RowScrollRegion to create its own)
  /// so this state can drive it directly - see [_scrollToTop] - mirroring
  /// SeriesDetailBody's `_SeriesScrollHost`.
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _primaryFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// The poster/title/meta block is always the very top of the page, so any
  /// focus landing anywhere inside it (including the Play button) means
  /// "show the top of the page" - matches SeriesDetailBody's `_scrollToTop`.
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
    final l = AppLocalizations.of(context);
    final richCast = widget.richCast;
    final hasCast = richCast != null && richCast.isNotEmpty;
    final richRelated = widget.richRelated;
    final hasRelated = richRelated != null && richRelated.isNotEmpty;
    final scale = FontSizeScope.scaleOf(context);
    final upper = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 220 * scale),
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
        Expanded(child: _infoColumn(context, theme)),
      ],
    );

    // The whole page (poster + meta + cast + related) scrolls together via
    // RowScrollRegion, matching SeriesDetailBody - the poster/meta block
    // renders at its natural size and the page grows to fit a taller
    // footer, rather than the footer squeezing the poster into less height
    // than its aspect ratio wants. No contentPadding on BackdropDetailHero
    // (unlike the narrow layout below) - the top/bottom insets live *inside*
    // the scrolled column instead, so they scroll away with everything else
    // rather than clipping the first/last row against a fixed boundary, and
    // the hero/poster can run all the way up behind the transparent AppBar.
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.pagePadding,
      ),
      child: RowScrollRegion(
        controller: _scrollController,
        onExitTop: _primaryFocusNode.requestFocus,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: detailAppBarHeight(context) + 32),
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) _scrollToTop();
              },
              child: upper,
            ),
            CastRevealSlot(
              topPadding: MediaBrowsingMetrics.contentPadding,
              castRow: (!hasCast && !hasRelated)
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasCast)
                          Semantics(
                            label: widget.castSemanticLabel,
                            container: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DetailRowHeader(
                                  icon: Icons.people,
                                  label: widget.castSemanticLabel,
                                ),
                                const SizedBox(height: 8),
                                CastRow(members: richCast),
                              ],
                            ),
                          ),
                        if (hasRelated) ...[
                          if (hasCast)
                            const SizedBox(
                              height: MediaBrowsingMetrics.contentPadding,
                            ),
                          DetailRowHeader(
                            icon: Icons.recommend,
                            label: l.relatedTitle,
                          ),
                          const SizedBox(height: 8),
                          RelatedRow(
                            items: richRelated,
                            onTap: (item) => widget.onRelatedTap?.call(item),
                          ),
                        ],
                      ],
                    ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );

    return BackdropDetailHero(
      backdropUrl: widget.backdropUrl,
      alwaysShowScrim: true,
      showBackgroundColorLayer: true,
      backgroundColor: bg,
      scrimColors: [bg.withValues(alpha: 0.35), bg.withValues(alpha: 0.92), bg],
      colorMatchReady: widget.colorMatchReady,
      scrollController: _scrollController,
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
        if (compact &&
            widget.richRelated != null &&
            widget.richRelated!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              top: MediaBrowsingMetrics.contentPadding,
            ),
            child: MediaPreviewSection(
              title: l.relatedTitle,
              titleIcon: Icons.recommend,
              emptyLabel: '',
              posterStyle: true,
              items: [
                for (final item in widget.richRelated!)
                  MediaPreviewItem(
                    title: item.title,
                    imageUrl: item.posterUrl,
                    fallbackIcon: item.isSeries ? Icons.tv : Icons.movie,
                    onTap: () => widget.onRelatedTap?.call(item),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
