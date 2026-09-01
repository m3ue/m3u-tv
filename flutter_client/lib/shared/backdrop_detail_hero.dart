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
/// edge, scrolling as one block only if it's taller than the viewport (see
/// [scrollWhenTall]). Mobile ([contentAlignment] of `Alignment.topLeft`,
/// paired with [backdropHeight]): the backdrop is capped to a band at the
/// top instead of stretching full-height, and [content] always scrolls
/// (starting below the band, via [contentPadding]) - the band itself never
/// moves, since it lives outside the scroll view.
///
/// When [backdropUrl] is null and [alwaysShowScrim] is false, [content] is
/// returned bare with no Stack/scrim at all (VOD/AIOStreams movie default).
/// Series always wants its dominant-color background even without a
/// backdrop image, so it passes `alwaysShowScrim: true`.
class BackdropDetailHero extends StatelessWidget {
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
    this.contentPaddingBuilder,
    this.scrollWhenTall = false,
  });

  final Widget content;
  final String? backdropUrl;

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
  /// Ignored when [contentPaddingBuilder] is set.
  final EdgeInsetsGeometry contentPadding;

  /// Same as [contentPadding] but computed from the hero's own layout
  /// constraints (Series needs `bottom: constraints.maxHeight * 0.05` on
  /// the bottom-aligned path, which isn't known until [scrollWhenTall]'s
  /// LayoutBuilder runs).
  final EdgeInsetsGeometry Function(BoxConstraints constraints)?
  contentPaddingBuilder;

  /// Bottom-aligned content taller than the viewport scrolls instead of
  /// overflowing (Series, so the poster/title stay reachable on a short
  /// window). Ignored when [contentAlignment] is `topLeft` - that content
  /// always scrolls. VOD/AIOStreams manage their own inner scrolling on the
  /// bottom-aligned path and pass false.
  final bool scrollWhenTall;

  @override
  Widget build(BuildContext context) {
    if (backdropUrl == null && !alwaysShowScrim) return content;

    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.surface;
    final colors =
        scrimColors ??
        [
          Colors.black.withValues(alpha: 0.2),
          Colors.black.withValues(alpha: 0.85),
          bg,
        ];

    Widget backdropLayer = Stack(
      fit: StackFit.expand,
      children: [
        if (backdropUrl != null) CachedBackdropImage(backdropUrl!),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: scrimStops,
            ),
          ),
        ),
      ],
    );
    final bandHeight = backdropHeight;
    if (bandHeight != null) {
      backdropLayer = Align(
        alignment: Alignment.topCenter,
        child: SizedBox(height: bandHeight, child: backdropLayer),
      );
    }

    final isTopAligned = contentAlignment == Alignment.topLeft;

    Widget paddedContent(EdgeInsetsGeometry padding) =>
        Padding(padding: padding, child: content);

    Widget contentLayer;
    if (isTopAligned) {
      // Content lives outside the (fixed) backdrop layer entirely, so
      // scrolling it never moves the band underneath.
      contentLayer = SingleChildScrollView(
        child: paddedContent(
          contentPaddingBuilder?.call(const BoxConstraints()) ?? contentPadding,
        ),
      );
    } else if (scrollWhenTall) {
      contentLayer = LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Align(
              alignment: contentAlignment,
              child: paddedContent(
                contentPaddingBuilder?.call(constraints) ?? contentPadding,
              ),
            ),
          ),
        ),
      );
    } else {
      contentLayer = Align(
        alignment: contentAlignment,
        child: paddedContent(
          contentPaddingBuilder?.call(const BoxConstraints()) ?? contentPadding,
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackgroundColorLayer) ColoredBox(color: bg),
        backdropLayer,
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
