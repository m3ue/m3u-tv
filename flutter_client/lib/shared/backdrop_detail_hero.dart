import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/cached_backdrop_image.dart';

/// Backdrop that stays visually fixed in place while [content] scrolls over
/// it, fading into the page background via a vertical gradient scrim.
/// Shared "hero" chrome for every item detail screen (VOD, Series,
/// AIOStreams movie) - previously copy-pasted per screen and quietly
/// drifted (different breakpoints, gradients, poster sizes, scroll
/// behavior).
///
/// TV/desktop (default [contentAlignment] of `Alignment.bottomLeft`): the
/// backdrop fills the whole hero and [content] sits pinned to the bottom
/// edge. [content] is placed as-is, so a caller that needs it to scroll when
/// the window is short passes a [content] that manages its own scrolling.
/// Mobile ([contentAlignment] of `Alignment.topLeft`, paired with
/// [backdropHeight]): the backdrop is capped to a band at the top instead of
/// stretching full-height, and [content] always scrolls (starting below the
/// band, via [contentPadding]) - the band itself never moves, since it lives
/// outside the scroll view.
///
/// When [backdropUrl] is null and [alwaysShowScrim] is false, [content] is
/// returned bare with no Stack/scrim at all (VOD/AIOStreams movie default).
/// Series always wants its dominant-color background even without a
/// backdrop image, so it passes `alwaysShowScrim: true`.
///
/// Colour-match reveal: callers doing the palette-extraction treatment
/// (VOD, Series) pass [colorMatchReady] - false while the dominant colour is
/// still resolving, true once it has (or has definitively failed). Until
/// that is true *and* the backdrop image has decoded, the hero shows a flat
/// theme-surface background; then the whole composite (image + colour wash +
/// scrim) cross-fades in as one over [revealDuration], so nothing snaps in
/// piecemeal. Callers with no palette step (AIOStreams) leave
/// [colorMatchReady] null and the backdrop renders immediately as before.
class BackdropDetailHero extends StatefulWidget {
  const BackdropDetailHero({
    super.key,
    required this.content,
    this.backdropUrl,
    this.backdropHeight,
    this.alwaysShowScrim = false,
    this.showBackgroundColorLayer = false,
    this.backgroundColor,
    this.scrimColors,
    this.scrimStops = const [0.0, 0.5, 1.0],
    this.contentAlignment = Alignment.bottomLeft,
    this.contentPadding = EdgeInsets.zero,
    this.colorMatchReady,
    this.revealDuration = const Duration(milliseconds: 420),
    this.scrollController,
    this.parallaxFactor = 0.35,
  });

  final Widget content;
  final String? backdropUrl;

  /// When set (wide/TV Series, whose [content] now scrolls the whole hero),
  /// the backdrop translates at [parallaxFactor] of this controller's
  /// offset - background moves slower than content. Null (default) keeps
  /// the backdrop static, as every other caller still wants.
  final ScrollController? scrollController;
  final double parallaxFactor;

  /// Caps the backdrop image + scrim to a fixed-height band pinned to the
  /// top of the hero (mobile, e.g. half the viewport) instead of the image
  /// stretching the full available height (TV/desktop, the default null).
  final double? backdropHeight;

  /// Keep the Stack/scrim even when [backdropUrl] is null (Series). When
  /// false, no backdrop means [content] renders with no chrome at all.
  final bool alwaysShowScrim;

  /// Paints an opaque [backgroundColor] layer under the backdrop/scrim so a
  /// translucent scrim top stop doesn't let the raw Scaffold background
  /// show through. Series opts in; VOD/AIOStreams keep their existing look.
  final bool showBackgroundColorLayer;

  /// Base surface color the scrim fades into. Defaults to the theme
  /// surface; Series/VOD pass the palette-extracted dominant tone.
  final Color? backgroundColor;

  /// Gradient stop colors, top to bottom. Defaults to the classic
  /// black-to-surface scrim (AIOStreams); Series/VOD pass a
  /// dominant-color-tinted set instead.
  final List<Color>? scrimColors;
  final List<double> scrimStops;

  /// Where [content] sits. `Alignment.bottomLeft` (default, TV/desktop)
  /// pins it to the backdrop's bottom edge. `Alignment.topLeft` (mobile,
  /// pair with [backdropHeight]) lets it scroll top-down like a normal
  /// page, starting below the band.
  final Alignment contentAlignment;

  /// Padding around [content]. On mobile this is what pushes content below
  /// the (fixed) backdrop band - typically `top: backdropHeight - overlap`.
  final EdgeInsetsGeometry contentPadding;

  /// Null (default) = render the backdrop as soon as it decodes, no hold and
  /// no fade (AIOStreams). Non-null = the palette-extraction treatment: false
  /// while the dominant colour is still resolving, true once it has resolved
  /// or failed. See the class doc for the reveal behaviour it drives.
  final bool? colorMatchReady;

  /// How long the composite takes to cross-fade in once it is revealed.
  final Duration revealDuration;

  @override
  State<BackdropDetailHero> createState() => _BackdropDetailHeroState();
}

class _BackdropDetailHeroState extends State<BackdropDetailHero> {
  bool _imageLoaded = false;

  @override
  void didUpdateWidget(BackdropDetailHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backdropUrl != widget.backdropUrl) _imageLoaded = false;
  }

  void _handleImageLoaded() {
    if (!_imageLoaded && mounted) setState(() => _imageLoaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.backdropUrl == null && !w.alwaysShowScrim) return w.content;

    final theme = Theme.of(context);
    final bg = w.backgroundColor ?? theme.colorScheme.surface;
    final colors =
        w.scrimColors ??
        [
          Colors.black.withValues(alpha: 0.2),
          Colors.black.withValues(alpha: 0.85),
          bg,
        ];

    Widget imageAndScrim = Stack(
      fit: StackFit.expand,
      children: [
        if (w.backdropUrl != null)
          CachedBackdropImage(w.backdropUrl!, onLoaded: _handleImageLoaded),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: w.scrimStops,
            ),
          ),
        ),
      ],
    );
    final bandHeight = w.backdropHeight;
    if (bandHeight != null) {
      imageAndScrim = Align(
        alignment: Alignment.topCenter,
        child: SizedBox(height: bandHeight, child: imageAndScrim),
      );
    }

    final scrollController = w.scrollController;
    if (scrollController != null) {
      imageAndScrim = AnimatedBuilder(
        animation: scrollController,
        builder: (context, child) {
          final offset = scrollController.hasClients
              ? scrollController.offset
              : 0.0;
          return Transform.translate(
            offset: Offset(0, -offset * w.parallaxFactor),
            child: child,
          );
        },
        child: imageAndScrim,
      );
    }

    // The dominant-colour wash spans the full hero (below a capped band too),
    // so it sits outside [imageAndScrim] but inside the same fade.
    final backdropComposite = Stack(
      fit: StackFit.expand,
      children: [
        if (w.showBackgroundColorLayer) ColoredBox(color: bg),
        imageAndScrim,
      ],
    );

    final isTopAligned = w.contentAlignment == Alignment.topLeft;
    final paddedContent = Padding(padding: w.contentPadding, child: w.content);
    final contentLayer = isTopAligned
        // Content lives outside the (fixed) backdrop layer entirely, so
        // scrolling it never moves the band underneath.
        ? SingleChildScrollView(child: paddedContent)
        : Align(alignment: w.contentAlignment, child: paddedContent);

    final gated = w.colorMatchReady != null;
    if (!gated) {
      return Stack(
        fit: StackFit.expand,
        children: [backdropComposite, contentLayer],
      );
    }

    final imageReady = w.backdropUrl == null || _imageLoaded;
    final revealed = w.colorMatchReady! && imageReady;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Flat hold until the art and its colour-match are both ready.
        ColoredBox(color: theme.colorScheme.surface),
        AnimatedOpacity(
          opacity: revealed ? 1 : 0,
          duration: w.revealDuration,
          curve: Curves.easeOut,
          child: backdropComposite,
        ),
        contentLayer,
      ],
    );
  }
}

/// Fixed-height backdrop band fading into the page background - the
/// narrow-layout hero shared by VOD and AIOStreams movie detail screens.
/// [cornerPoster] (VOD) overlays a small poster bottom-left; AIOStreams
/// instead substitutes the poster as the band image itself via
/// [backdropFallback] and passes no [cornerPoster].
class CompactBackdropBand extends StatelessWidget {
  const CompactBackdropBand({
    super.key,
    required this.height,
    this.backdropUrl,
    this.backdropFallback,
    this.cornerPoster,
    this.gradientStops = const [0.4, 1.0],
    this.backgroundColor,
    this.showBackgroundColorLayer = false,
  });

  final double height;
  final String? backdropUrl;

  /// Shown in place of the backdrop image when [backdropUrl] is null.
  final Widget? backdropFallback;

  /// Small poster overlaid bottom-left, on top of the gradient.
  final Widget? cornerPoster;
  final List<double> gradientStops;

  /// Colour the gradient fades into. Defaults to the theme surface;
  /// Series passes the palette-extracted dominant tone.
  final Color? backgroundColor;

  /// Paints an opaque [backgroundColor] layer under the backdrop/gradient so
  /// a null/still-loading backdrop shows solid colour instead of the raw
  /// Scaffold background peeking through the gradient's translucent top.
  /// VOD/AIOStreams keep their existing look (false); Series opts in.
  final bool showBackgroundColorLayer;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).colorScheme.surface;
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showBackgroundColorLayer) ColoredBox(color: bg),
          if (backdropUrl != null)
            CachedBackdropImage(backdropUrl!)
          else
            ?backdropFallback,
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, bg],
                  stops: gradientStops,
                ),
              ),
            ),
          ),
          if (cornerPoster != null)
            Positioned(left: 16, bottom: 16, child: cornerPoster!),
        ],
      ),
    );
  }
}
