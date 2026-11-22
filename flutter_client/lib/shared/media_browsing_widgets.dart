import 'dart:async';
import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart' show OptimizeFor;
import 'package:m3u_tv/shared/app_button.dart' show kStadiumFocusEffects;
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_image_provider.dart';
import 'package:m3u_tv/shared/sized_image_url.dart';
import 'package:material_ui/material_ui.dart';

class CategoryTabData {
  const CategoryTabData({required this.id, required this.name});

  final String id;
  final String name;
}

class MediaBrowsingMetrics {
  const MediaBrowsingMetrics._();

  static const double pagePadding = 24;
  static const double contentPadding = 16;
  static const double itemGap = 12;
  static const double chipGap = 8;
  static const double chipRadius = 20;
  static const double cardRadius = 12;
  static const double posterRadius = 8;
  static const double logoSize = 56;
  static const double previewCardWidth = 172;
  static const double previewCardHeight = 148;
  static const double posterCardWidth = 180;
  static const double posterCardHeight = 300;
  // Landscape "Continue Watching" cards: 16:9 thumbnail + text area.
  static const double landscapeCardWidth = 280;
  static const double landscapeCardHeight = 205; // 157.5 (9/16×280) + 47 text
  // Width of the TV/Desktop interstitial search+category strip
  // (MediaCategoryNav) between the sidebar and a screen's content grid.
  static const double interstitialNavWidth = 200;
}

/// Columns for a vertical poster grid (the Movies/Series pages' layout): as
/// few as keep each card at most [maxCardWidth] wide, but never so many that
/// a card drops below [minCardWidth]. Both are unscaled; [scale] is
/// `FontSizeScope.scaleOf`.
int posterGridColumnCount(
  double availableWidth,
  double scale, {
  double minCardWidth = 120,
  double maxCardWidth = 220,
}) {
  const gap = MediaBrowsingMetrics.itemGap;
  final minimumColumns = ((availableWidth + gap) / (maxCardWidth * scale + gap))
      .ceil();
  final maximumColumns = ((availableWidth + gap) / (minCardWidth * scale + gap))
      .floor();
  return minimumColumns.clamp(1, maximumColumns.clamp(1, 100));
}

/// Small icon + label header used above a detail-page row (Cast, Related).
/// Mirrors [MediaPreviewSection]'s own title-row styling so a header reads
/// consistently whether the row sits inside a preview section or a locked
/// D-pad row (CastRow/RelatedRow) on the Movie/Series detail pages.
class DetailRowHeader extends StatelessWidget {
  const DetailRowHeader({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20 * scale, color: theme.textTheme.titleSmall?.color),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class InlineMediaSearchField extends StatefulWidget {
  const InlineMediaSearchField({
    required this.query,
    required this.onChanged,
    this.hintText = 'Search...',
    this.autofocus = false,
    this.focusNode,
    this.textInputAction = TextInputAction.search,
    this.activateOnSelect = false,
    super.key,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final String hintText;

  /// When [activateOnSelect] is false: autofocuses the real text field
  /// (opens the keyboard immediately). When [activateOnSelect] is true:
  /// autofocuses the inactive, button-like facade instead - see
  /// [activateOnSelect].
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;

  /// TV/desktop d-pad screens embed this field alongside other browsable
  /// content (category chips, a content grid) rather than on a
  /// dedicated search screen. A plain [TextField] can't tell "the user
  /// d-padded past this on their way elsewhere" apart from "the user wants
  /// to type" - both just focus it, which opens the keyboard and starts
  /// eating Left/Right for cursor movement instead of navigation.
  ///
  /// When true, the field starts as a non-editing, [DpadInkWell]-focusable
  /// button showing the current query (or hint); only pressing Select on it
  /// opens the real text field and grabs keyboard focus. Back/Escape while
  /// editing returns to the button instead of falling through to the
  /// screen's own Back handling. [autofocus] then targets that button, not
  /// the text field. Screens with a dedicated search purpose (e.g.
  /// `SearchScreen`) should leave this false.
  final bool activateOnSelect;

  @override
  State<InlineMediaSearchField> createState() => _InlineMediaSearchFieldState();
}

class _InlineMediaSearchFieldState extends State<InlineMediaSearchField> {
  late final TextEditingController _controller;
  FocusNode? _internalFocusNode;
  // Wraps the TextField + Clear button as one focus scope. Listening on this
  // instead of _focusNode directly lets us tell "d-padded from the TextField
  // to its own Clear button" (a descendant of this node still has focus)
  // apart from "d-padded away from the field entirely" (nothing under this
  // node has focus) - see _handleFocusChange.
  final FocusNode _containerFocusNode = FocusNode(
    debugLabel: 'InlineMediaSearchField container',
  );
  final FocusNode _clearFocusNode = FocusNode(
    debugLabel: 'InlineMediaSearchField clear button',
  );
  bool _focused = false;
  late bool _activated = !widget.activateOnSelect;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _containerFocusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(InlineMediaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _containerFocusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _clearFocusNode.dispose();
    _internalFocusNode?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _containerFocusNode.hasFocus);
    // Losing focus for any reason (d-pad navigating away, not just an
    // explicit Escape/Back press) reverts to the inactive facade - a live
    // TextField left mounted-but-unfocused looks and behaves differently
    // from the facade button it should have become again. Checking the
    // container node (rather than the TextField's own _focusNode) means
    // moving focus onto the adjacent Clear button - still a descendant of
    // this node - does not count as leaving.
    if (!_containerFocusNode.hasFocus) _deactivate();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  void _activate() {
    setState(() => _activated = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _deactivate() {
    if (!widget.activateOnSelect || !_activated) return;
    setState(() => _activated = false);
  }

  /// [TextField]'s default `onTapOutside` unfocuses on mouse pointer-DOWN
  /// (not tap-up) for any point outside the [TextField] itself - it has no
  /// notion of the Clear button being logically part of this component. Left
  /// as default, a mouse-down on Clear counts as "outside", unfocuses
  /// _focusNode, deactivates the field and unmounts the Clear button before
  /// its own tap-up ever fires, so the click appears to do nothing. Only
  /// unfocus for a point genuinely outside this whole widget (i.e. still let
  /// clicking elsewhere on screen close the field, matching Escape/Back).
  void _handleTapOutside(PointerDownEvent event) {
    final renderObject = _containerFocusNode.context?.findRenderObject();
    if (renderObject is RenderBox && renderObject.attached) {
      final local = renderObject.globalToLocal(event.position);
      if (renderObject.paintBounds.contains(local)) return;
    }
    _focusNode.unfocus();
  }

  KeyEventResult _handleEditingKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _deactivate();
      return KeyEventResult.handled;
    }
    // EditableText's own Shortcuts consume Left/Right (and, on multi-line
    // fields, Up) for cursor/selection movement before they ever bubble out
    // to the app's d-pad traversal, so there is otherwise no d-pad path from
    // a focused TextField to the adjacent Clear button - Down is the one
    // arrow a single-line field never claims, so it doubles as "jump to
    // Clear" while editing.
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        widget.query.isNotEmpty &&
        _focusNode.hasFocus) {
      _clearFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(
      Radius.circular(MediaBrowsingMetrics.cardRadius),
    );
    final scale = FontSizeScope.scaleOf(context);

    // Fixed so the facade button and the real TextField below are pixel
    // identical in height - letting each derive its own height from font
    // metrics/padding produced a visible size jump on activate/deactivate.
    // Scaled with the display-size setting so the field doesn't clip its
    // own (already-scaling) text/icons at Large/Very Large.
    final fieldHeight = 52.0 * scale;
    final hintStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    if (widget.activateOnSelect && !_activated) {
      return SizedBox(
        height: fieldHeight,
        child: DpadInkWell(
          onTap: _activate,
          autofocus: widget.autofocus,
          borderRadius: radius,
          color: colorScheme.surfaceContainerHigh,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12 * scale),
            child: Row(
              children: [
                Icon(
                  Icons.search,
                  size: 24 * scale,
                  color: colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 8 * scale),
                Expanded(
                  child: Text(
                    widget.query.isEmpty ? widget.hintText : widget.query,
                    overflow: TextOverflow.ellipsis,
                    style: widget.query.isEmpty
                        ? hintStyle
                        : hintStyle?.copyWith(color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: fieldHeight,
      child: Stack(
        children: [
          Positioned.fill(
            // Built the same way as the facade's Row (below) rather than
            // via InputDecoration's prefixIcon/isCollapsed machinery - that
            // machinery lays its content out top-aligned once the decorator
            // is stretched taller than its content, and there's no
            // vertical-centering knob for it. A plain Row centers its
            // children by default, so it just works.
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: radius,
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12 * scale,
                  right: (widget.query.isEmpty ? 12 : 4) * scale,
                ),
                child: Focus(
                  focusNode: _containerFocusNode,
                  canRequestFocus: false,
                  skipTraversal: true,
                  // Handles Escape/Back and the Clear-button jump regardless
                  // of whether the TextField or the Clear button itself
                  // holds focus - both are descendants of this node.
                  onKeyEvent: widget.activateOnSelect
                      ? _handleEditingKey
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 24 * scale,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(width: 8 * scale),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          autofocus:
                              !widget.activateOnSelect && widget.autofocus,
                          onTapOutside: widget.activateOnSelect
                              ? _handleTapOutside
                              : null,
                          textInputAction: widget.textInputAction,
                          style: hintStyle?.copyWith(
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration.collapsed(
                            hintText: widget.hintText,
                            hintStyle: hintStyle,
                          ),
                          onChanged: widget.onChanged,
                          onSubmitted: (_) => _deactivate(),
                        ),
                      ),
                      if (widget.query.isNotEmpty)
                        DpadFocusable(
                          focusNode: _clearFocusNode,
                          onSelect: _clear,
                          effects: kStadiumFocusEffects,
                          child: IconButton(
                            tooltip: AppLocalizations.of(
                              context,
                            ).mediaClearSearch,
                            icon: Icon(Icons.clear, size: 24 * scale),
                            onPressed: _clear,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _focused ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: CustomPaint(
                  painter: GradientBorderPainter(
                    borderRadius: radius,
                    width: 2.5,
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [colorScheme.primary, colorScheme.secondary],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ResilientMediaImage extends StatefulWidget {
  const ResilientMediaImage({
    required this.imageUrl,
    required this.fallbackIcon,
    this.fallbackImageUrls = const <String>[],
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.fallbackTitle,
    this.borderRadius = MediaBrowsingMetrics.posterRadius,
    this.backgroundColor,
    this.oversample = 1,
    super.key,
  });

  final String? imageUrl;

  /// Alternate URLs to try, in order, once [imageUrl] has failed its retries
  /// (a season poster that 404s falling back to the series poster, then the
  /// backdrop). Only the icon fallback shows once every URL is exhausted.
  final List<String> fallbackImageUrls;
  final IconData fallbackIcon;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? aspectRatio;
  final String? fallbackTitle;
  final double borderRadius;
  final Color? backgroundColor;

  /// Decode multiplier on top of the display's raw pixel density. Leave at 1
  /// (decode at display size) for photographic art - posters, backdrops, cast
  /// photos - where a 2x oversample just quadruples each decoded bitmap and
  /// makes the image cache thrash on a 4K TV. Pass 2 for small channel logos
  /// with thin text/wordmarks, where the box is tiny (memory cost negligible)
  /// but a display-size decode of a large source looks blocky and aliased.
  /// [ResizeImage] never upscales past the source's intrinsic size.
  final double oversample;

  @override
  State<ResilientMediaImage> createState() => _ResilientMediaImageState();
}

class _ResilientMediaImageState extends State<ResilientMediaImage> {
  // On a cold app start, every row on the home screen fires its poster
  // requests at once, which blows past flutter_cache_manager's hardcoded
  // concurrentFetches limit (10). Requests queued behind that limit can lose
  // the race against transient network hiccups, and neither
  // cached_network_image nor flutter_cache_manager retry on their own - the
  // failed entry is simply evicted, so the image sits on the fallback icon
  // until something (e.g. a manual app reload) asks for it again. Retrying
  // here with backoff closes that gap without needing to touch the shared
  // cache manager's concurrency settings.

  int _attempt = 0;
  bool _retryScheduled = false;

  /// Index into [_urlChain] currently being displayed.
  int _urlIndex = 0;

  /// Once this cell has resolved an image for the current URL, a fling
  /// starting afterward must not blank it back out to the fallback -
  /// [DeferImageLoadingScope] only withholds *new* decodes, never already
  /// -resolved ones.
  bool _hasResolvedOnce = false;

  List<String> get _urlChain => [
    ?_nonEmpty(widget.imageUrl),
    ...widget.fallbackImageUrls.map(_nonEmpty).whereType<String>(),
  ];

  static String? _nonEmpty(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value;

  String? get _currentUrl {
    final chain = _urlChain;
    return _urlIndex < chain.length ? chain[_urlIndex] : null;
  }

  @override
  void didUpdateWidget(covariant ResilientMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        !listEquals(oldWidget.fallbackImageUrls, widget.fallbackImageUrls)) {
      _attempt = 0;
      _urlIndex = 0;
      _retryScheduled = false;
      _hasResolvedOnce = false;
    }
  }

  void _scheduleRetry() {
    if (_retryScheduled) return;
    final hasNextUrl = _urlIndex < _urlChain.length - 1;
    // In speed mode, cap retries at 1 to avoid redundant decode storms;
    // quality mode keeps the full 3-retry budget for transient-failure recovery.
    final isSpeed =
        ImageQualityScope.of(context)?.optimizeFor == OptimizeFor.speed;
    final maxRetries = isSpeed ? 1 : 3;
    // Give the last URL the full retry budget (transient-failure recovery);
    // when a better candidate is waiting, fail over after a single quick retry.
    final retryBudget = hasNextUrl ? 1 : maxRetries;
    if (_attempt >= retryBudget) {
      if (!hasNextUrl) return;
      _retryScheduled = true;
      unawaited(
        Future.microtask(() {
          _retryScheduled = false;
          if (mounted) {
            setState(() {
              _urlIndex++;
              _attempt = 0;
            });
          }
        }),
      );
      return;
    }
    _retryScheduled = true;
    final delay = Duration(milliseconds: 500 * (1 << _attempt));
    _attempt++;
    Future.delayed(delay, () {
      _retryScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = _MediaImageFallback(
      icon: widget.fallbackIcon,
      title: widget.fallbackTitle,
    );
    final url = _currentUrl;
    // Decode at display size by default (see [ResilientMediaImage.oversample]).
    // The user's quality scope multiplies the per-widget oversample: speed
    // mode keeps the memory footprint low, quality mode sharpens fixed-size
    // logos. ResizeImage never upscales past the source's intrinsic size.
    final oversample =
        ImageQualityScope.oversampleOf(context) * widget.oversample;
    final filterQuality = ImageQualityScope.filterQualityOf(context);
    final devicePixelRatio =
        MediaQuery.devicePixelRatioOf(context) * oversample;
    final shouldDefer = !_hasResolvedOnce && DeferImageLoadingScope.of(context);
    final loadUrl = url == null || url.isEmpty || shouldDefer ? null : url;
    if (loadUrl != null) _hasResolvedOnce = true;

    Widget buildSized(double? decodeWidth, double? decodeHeight) {
      final cacheWidth = decodeWidth == null
          ? null
          : (decodeWidth * devicePixelRatio).round();
      final cacheHeight = decodeHeight == null
          ? null
          : (decodeHeight * devicePixelRatio).round();
      final provider = mediaImageProvider(
        sizedImageUrl(loadUrl!, decodeWidth: cacheWidth),
      );
      return _buildImage(
        provider,
        fallback,
        cacheWidth,
        cacheHeight,
        filterQuality,
      );
    }

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                widget.backgroundColor ?? colorScheme.surfaceContainerHighest,
          ),
          child: loadUrl == null
              ? fallback
              // A fixed size needs no LayoutBuilder, which also keeps this
              // usable under IntrinsicHeight/IntrinsicWidth (a LayoutBuilder
              // can't report intrinsics and fails the whole subtree's layout).
              : widget.width != null && widget.height != null
              ? buildSized(widget.width, widget.height)
              // Callers that size the art through layout (e.g. a poster grid
              // cell's Expanded slot) pass no width/height; fall back to the
              // bounded constraints so those still decode at display size.
              // Without this a grid poster decoded at full source resolution
              // (~15-24MB each for TMDB originals), which on a 3GB SHIELD put
              // ~800MB on the GPU within seconds of scrolling and got the app
              // and the launcher killed by the low-memory killer.
              : LayoutBuilder(
                  builder: (context, constraints) => buildSized(
                    widget.width ??
                        (constraints.hasBoundedWidth
                            ? constraints.maxWidth
                            : null),
                    widget.height ??
                        (constraints.hasBoundedHeight
                            ? constraints.maxHeight
                            : null),
                  ),
                ),
        ),
      ),
    );
    if (widget.aspectRatio == null) return image;
    return AspectRatio(aspectRatio: widget.aspectRatio!, child: image);
  }

  Widget _buildImage(
    ImageProvider provider,
    Widget fallback,
    int? cacheWidth,
    int? cacheHeight,
    FilterQuality filterQuality,
  ) {
    return Image(
      image: cacheWidth == null && cacheHeight == null
          ? provider
          : ResizeImage(
              provider,
              width: cacheWidth,
              height: cacheHeight,
              policy: ResizeImagePolicy.fit,
            ),
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return fallback;
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return fallback;
      },
      errorBuilder: (_, _, _) {
        _scheduleRetry();
        return fallback;
      },
    );
  }
}

/// A `CatalogWindowGrid.placeholderBuilder` for a not-yet-loaded poster
/// slot: same rounded rect as a resolved [MediaPreviewCard]'s art, filled
/// with the theme's card background, so a page landing a frame later does
/// not shift focus or layout under the user.
class CatalogGridPlaceholder extends StatelessWidget {
  const CatalogGridPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.posterRadius),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _MediaImageFallback extends StatelessWidget {
  const _MediaImageFallback({required this.icon, this.title});

  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallbackTitle = title;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Icon(
            icon,
            size: 48 * FontSizeScope.scaleOf(context),
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (fallbackTitle != null && fallbackTitle.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colorScheme.surface.withValues(alpha: 0.82),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
                child: Text(
                  fallbackTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ScrollableCategoryBar extends StatefulWidget {
  const ScrollableCategoryBar({
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    this.leading,
    this.padding = const EdgeInsets.symmetric(
      horizontal: MediaBrowsingMetrics.contentPadding,
      vertical: 8,
    ),
    super.key,
  });

  final List<CategoryTabData> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Widget? leading;

  /// Defaults to the bar's own edge inset (for full-bleed use on Series/VOD
  /// browse screens). Pass a zero-horizontal padding when embedding the bar
  /// inside a page that already applies its own horizontal padding, so the
  /// bar lines up flush with sibling form fields instead of doubling up.
  final EdgeInsets padding;

  @override
  State<ScrollableCategoryBar> createState() => _ScrollableCategoryBarState();
}

class _ScrollableCategoryBarState extends State<ScrollableCategoryBar> {
  final ScrollController _controller = ScrollController();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_controller.hasClients) {
      return;
    }

    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }

    final position = _controller.position;
    final target = (_controller.offset + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.jumpTo(target);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: MediaBrowsingMetrics.chipGap),
          ],
          Expanded(
            child: SizedBox(
              height: 36,
              child: ExcludeSemantics(
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: Scrollbar(
                    controller: _controller,
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.zero,
                      itemCount: widget.tabs.length,
                      separatorBuilder: (_, _) => const SizedBox(
                        width: MediaBrowsingMetrics.chipGap,
                      ),
                      itemBuilder: (context, index) {
                        final tab = widget.tabs[index];
                        return CategoryFilterChip(
                          label: tab.name,
                          isSelected: widget.selectedId == tab.id,
                          onTap: () => widget.onSelected(tab.id),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryFilterChip extends StatelessWidget {
  const CategoryFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(
      Radius.circular(MediaBrowsingMetrics.chipRadius),
    );
    return DpadInkWell(
      onTap: onTap,
      effects: const [GradientBorderEffect(borderRadius: radius)],
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class ScrollbarGridView extends StatefulWidget {
  const ScrollbarGridView({
    required this.itemCount,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding = const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry padding;

  @override
  State<ScrollbarGridView> createState() => _ScrollbarGridViewState();
}

class _ScrollbarGridViewState extends State<ScrollbarGridView> {
  final ScrollController _controller = ScrollController();
  bool _deferImageLoading = false;

  // `ScrollPosition.recommendDeferredLoading` only ever reports true for a
  // physics-driven fling (BallisticScrollActivity). D-pad navigation moves
  // the grid via `DpadScroll.ensureVisible`'s `position.animateTo` - a driven
  // animation, not a fling - so that check alone never engages on TV, which
  // is exactly where fast, repeated D-pad presses can otherwise queue a
  // decode burst large enough to OOM. Track recent scroll offsets ourselves
  // so a rapid run of driven scrolls is caught the same way a fling is.
  final List<(Duration, double)> _recentOffsets = <(Duration, double)>[];
  final Stopwatch _clock = Stopwatch()..start();

  static const Duration _velocityWindow = Duration(milliseconds: 180);
  static const double _fastScrollVelocityThreshold = 2400; // logical px/sec

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _recentOffsets.clear();
      if (_deferImageLoading) setState(() => _deferImageLoading = false);
      return false;
    }

    var defer =
        _controller.hasClients &&
        _controller.position.recommendDeferredLoading(context);

    if (notification is ScrollUpdateNotification) {
      final now = _clock.elapsed;
      final pixels = notification.metrics.pixels;
      _recentOffsets
        ..add((now, pixels))
        ..removeWhere((sample) => now - sample.$1 > _velocityWindow);
      if (_recentOffsets.length > 1) {
        final oldest = _recentOffsets.first;
        final dtMicros = (now - oldest.$1).inMicroseconds;
        if (dtMicros > 0) {
          final velocity = (pixels - oldest.$2).abs() * 1e6 / dtMicros;
          if (velocity > _fastScrollVelocityThreshold) defer = true;
        }
      }
    }

    if (defer != _deferImageLoading) {
      setState(() => _deferImageLoading = defer);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: DeferImageLoadingScope(
            defer: _deferImageLoading,
            child: GridView.builder(
              controller: _controller,
              padding: widget.padding,
              gridDelegate: widget.gridDelegate,
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
            ),
          ),
        ),
      ),
    );
  }
}

class ScrollbarListView extends StatefulWidget {
  const ScrollbarListView({
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;

  @override
  State<ScrollbarListView> createState() => _ScrollbarListViewState();
}

class _ScrollbarListViewState extends State<ScrollbarListView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: ListView.builder(
          controller: _controller,
          padding: widget.padding,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}

class MediaPreviewItem {
  const MediaPreviewItem({
    required this.title,
    required this.fallbackIcon,
    required this.onTap,
    this.onLongTap,
    this.isFavorite = false,
    this.imageUrl,
    this.subtitle,
    this.imageFit = BoxFit.cover,
    this.imageAspectRatio,
    this.fallbackTitle,
    this.imagePadding = EdgeInsets.zero,
    this.imageBackgroundColor,
    this.progressFraction,
    this.overlayBadges = const <String>[],
    this.overlayLabel,
    this.emphasisLabel,
    this.upNextLabel,
    this.ratingLabel,
    this.cornerBadgeIcon,
    this.cornerBadgeColor,
    this.onFocused,
    this.onHoverChanged,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final IconData fallbackIcon;
  final VoidCallback onTap;
  final VoidCallback? onLongTap;
  final bool isFavorite;

  /// Fires when D-pad/mouse focus lands on this card. The rich Home uses it
  /// to drive its spotlight hero; null (every other rail) adds nothing to the
  /// card's widget tree.
  final VoidCallback? onFocused;

  /// Mouse hover over this card; see [HoverIntentCallback]. Like
  /// [onFocused], null adds nothing.
  final HoverIntentCallback? onHoverChanged;

  /// Icon shown as a small circular corner badge over the poster (top-left),
  /// the same treatment [isFavorite] gives its star. Only rendered by
  /// default/poster cards, and only when [isFavorite] is false - the two
  /// share one corner and isFavorite (the more common case) takes priority.
  /// Lets callers like Requests (already-requested/already-available) flag a
  /// card's state without forking the card widget itself.
  final IconData? cornerBadgeIcon;

  /// Background color for [cornerBadgeIcon]'s circle. Defaults to the
  /// theme's primary color when null.
  final Color? cornerBadgeColor;
  final BoxFit imageFit;
  final double? imageAspectRatio;
  final String? fallbackTitle;
  final EdgeInsets imagePadding;
  final Color? imageBackgroundColor;

  /// 0.0-1.0 progress shown as a bar along the bottom of the image.
  final double? progressFraction;

  /// When non-null, landscape cards show this text as a primary-colour badge in
  /// the top-right corner (where the progress percent normally sits) and
  /// suppress the bottom progress bar. Used for synthetic "up next" episode
  /// entries; the caller supplies the localized string.
  final String? upNextLabel;

  /// Short rating string (e.g. `★ 8.1`) appended to the muted line under the
  /// title on default/poster cards, after [subtitle] and a `•` separator when
  /// both are present. Read only by `_buildDefaultContent`.
  final String? ratingLabel;

  /// Short text labels rendered as chips overlaid on the image (right-aligned).
  final List<String> overlayBadges;

  /// Optional label shown left-aligned opposite the overlay badges.
  final String? overlayLabel;

  /// A short, high-value string rendered between the title and subtitle on
  /// default/poster cards at title-scale weight - for a 10-foot UI, the one
  /// datum that must survive a glance from the couch (here: when a programme
  /// airs). Null on every existing rail, which renders exactly today's tree.
  ///
  /// Rendered ONLY by `_buildDefaultContent`. Landscape cards have no room and
  /// deliberately ignore it - see the assert in `build`. Note the precedent:
  /// `overlayLabel`, `overlayBadges` and `progressFraction` are declared here
  /// but read only by `_buildLandscapeContent` (L745-878), so they silently do
  /// nothing on default cards. Do not add to that trap.
  final String? emphasisLabel;
}

/// Mouse hover over a card. Fires with `hovered: true` each time the pointer
/// itself moves over the card (so a caller can wait for it to rest), and
/// `hovered: false` when it leaves. Content sliding under a pointer that
/// hasn't moved (a row docking or auto-scrolling for the keyboard) does not
/// count as hovering. `focusCard` moves D-pad focus to the card.
typedef HoverIntentCallback =
    void Function({required bool hovered, required VoidCallback focusCard});

/// Non-focusable wrapper that reports focus entering [child] and mouse hover
/// over it, and can move focus to [child]'s own focus node on request. Shared
/// by preview cards and the Home Live row's channel tiles.
class PreviewFocusAnchor extends StatefulWidget {
  const PreviewFocusAnchor({
    super.key,
    required this.child,
    this.onFocused,
    this.onHoverChanged,
    this.contentKey,
  });

  final Widget child;
  final VoidCallback? onFocused;
  final HoverIntentCallback? onHoverChanged;

  /// Identity of what [child] shows. When it changes while [child] holds
  /// focus, [onFocused] fires again, since nothing about focus changed.
  final Object? contentKey;

  @override
  State<PreviewFocusAnchor> createState() => _PreviewFocusAnchorState();
}

class _PreviewFocusAnchorState extends State<PreviewFocusAnchor> {
  final FocusNode _anchor = FocusNode(
    debugLabel: 'preview-focus-anchor',
    canRequestFocus: false,
    skipTraversal: true,
  );

  @override
  void didUpdateWidget(PreviewFocusAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final onFocused = widget.onFocused;
    if (onFocused == null ||
        !_anchor.hasFocus ||
        widget.contentKey == oldWidget.contentKey) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _anchor.hasFocus) onFocused();
    });
  }

  @override
  void dispose() {
    _anchor.dispose();
    super.dispose();
  }

  void _focusChild() {
    final node = _anchor.traversalDescendants.firstOrNull;
    if (node != null && !node.hasFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final onHoverChanged = widget.onHoverChanged;
    return Focus(
      focusNode: _anchor,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocused?.call();
      },
      child: onHoverChanged == null
          ? widget.child
          : MouseRegion(
              opaque: false,
              // onHover, not onEnter: onEnter also fires when a card slides
              // under a pointer that never moved.
              onHover: (_) =>
                  onHoverChanged(hovered: true, focusCard: _focusChild),
              onExit: (_) =>
                  onHoverChanged(hovered: false, focusCard: _focusChild),
              child: widget.child,
            ),
    );
  }
}

/// Builds one card of a [MediaPreviewSection.builder] row at [cardSize].
typedef PreviewCardBuilder =
    Widget Function(
      BuildContext context,
      int index,
      Size cardSize, {
      required bool autofocus,
    });

class MediaPreviewSection extends StatefulWidget {
  const MediaPreviewSection({
    required this.title,
    required this.emptyLabel,
    required this.items,
    this.titleIcon,
    this.posterStyle = false,
    this.landscapeStyle = false,
    this.isLoading = false,
    this.viewAll,
    this.useSidebarLayout = false,
    this.onSidebarActivate,
    this.onTopEdge,
    this.maxItems = maxVisibleItems,
    this.autofocusFirst = true,
    super.key,
  }) : itemCount = null,
       itemBuilder = null,
       baseCardWidth = null,
       baseCardHeight = null;

  /// A row of caller-built cards (e.g. the Home Live TV row's
  /// `ChannelGridTile`s) that keeps this section's header, D-pad region,
  /// hover scroll arrows and width-responsive card sizing. [itemBuilder] receives the
  /// final card size and must size its card to it; the first card should
  /// honor `autofocus`.
  const MediaPreviewSection.builder({
    required this.title,
    required this.emptyLabel,
    required int this.itemCount,
    required PreviewCardBuilder this.itemBuilder,
    required double this.baseCardWidth,
    required double this.baseCardHeight,
    this.titleIcon,
    this.isLoading = false,
    this.viewAll,
    this.useSidebarLayout = false,
    this.onSidebarActivate,
    this.onTopEdge,
    this.maxItems = maxVisibleItems,
    this.autofocusFirst = true,
    super.key,
  }) : items = const [],
       posterStyle = false,
       landscapeStyle = false;

  final String title;
  final IconData? titleIcon;
  final String emptyLabel;
  final List<MediaPreviewItem> items;
  final bool posterStyle;
  final bool landscapeStyle;

  /// Shows placeholder cards at the row's card size in place of its items,
  /// so the row keeps its height while its first page loads.
  final bool isLoading;

  /// A last card after the items that opens the full list. Only its title,
  /// subtitle, icon and tap/focus/hover callbacks are used.
  final MediaPreviewItem? viewAll;

  /// Set only by [MediaPreviewSection.builder].
  final int? itemCount;
  final PreviewCardBuilder? itemBuilder;
  final double? baseCardWidth;
  final double? baseCardHeight;

  /// Whether this row is hosted inside `AppShell`'s TV/desktop sidebar
  /// layout, where the content pane sits at a `left` inset equal to the
  /// collapsed rail's width (see [kSidebarRailInset]) instead of filling
  /// the full window width.
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;

  /// Up pressed in this row. Null lets directional traversal move focus to
  /// whatever sits above; a row under a tab bar sets this to land on the
  /// selected tab instead.
  final VoidCallback? onTopEdge;

  /// A preview row renders at most this many cards regardless of how many
  /// [items] it is handed. Callers building [items] from a large catalog
  /// should `.take(MediaPreviewSection.maxVisibleItems)` before mapping so a
  /// provider tick doesn't allocate a [MediaPreviewItem] per catalog entry on
  /// every rebuild.
  static const int maxVisibleItems = 12;

  /// The most cards this row renders: [maxVisibleItems] for a preview row
  /// with a [viewAll] card; a row that is itself the full list (no View All)
  /// passes its item count.
  final int maxItems;

  /// Whether the first card asks for focus when the row is built. Off for a
  /// row in its own `FocusScope` that appears while focus is elsewhere (e.g.
  /// search results arriving while the user types): autofocus applies
  /// whenever the row's scope has nothing focused, so the card would take
  /// focus from the search field.
  final bool autofocusFirst;

  @override
  State<MediaPreviewSection> createState() => _MediaPreviewSectionState();
}

/// Base (unscaled) width of `NavigationSidebar`'s collapsed rail and the
/// `left` inset `AppShell._buildTvLayout` gives its content pane outside of
/// the full-screen-detail transition (see [_MediaPreviewSectionState.build]).
/// The single source of truth for this value - shared with `app_shell.dart`
/// so the rail and the content pane it insets can't independently drift.
const double kSidebarRailInset = 64;

class _MediaPreviewSectionState extends State<MediaPreviewSection> {
  final ScrollController _controller = ScrollController();
  final GlobalKey<DpadRegionState> _regionKey = GlobalKey<DpadRegionState>();

  /// Up/Down out of the row lands on the nearest row in that direction.
  ///
  /// dpad's own pick favours anything directly under the focused card
  /// ("in the beam") over anything off to the side, however close. Focused
  /// far along a long row, a short row next to it (two cards and View all)
  /// has nothing under the card, so focus jumped over it to the row after.
  /// Here the beam is the whole row's width, so the closest row wins and
  /// then the card nearest across (or the one remembered) inside it.
  void _onVerticalEdge(TraversalDirection direction) {
    if (_focusAdjacentRow(direction)) return;
    // The next row may not be built yet in a lazy list: reveal it, retry.
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final position = scrollable?.position;
    if (position == null) return;
    final down = direction == TraversalDirection.down;
    final target =
        (position.pixels + (down ? 1 : -1) * position.viewportDimension * 0.6)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return;
    position.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAdjacentRow(direction);
    });
  }

  bool _focusAdjacentRow(TraversalDirection direction) {
    final region = _regionKey.currentState;
    final regionRect = region == null ? null : _globalRect(region.context);
    final current = FocusManager.instance.primaryFocus;
    final source = current == null ? null : _nodeRect(current);
    final scope = current?.nearestScope;
    if (region == null ||
        regionRect == null ||
        source == null ||
        scope == null) {
      return false;
    }
    final down = direction == TraversalDirection.down;
    // Candidates beyond this row that share its horizontal span, so the
    // sidebar or a side panel never counts as the row below.
    final byRegion = <Object, List<(FocusNode, Rect)>>{};
    double? nearestGap;
    for (final node in scope.traversalDescendants) {
      if (!node.canRequestFocus) continue;
      final targetRegion = DpadRegion.ofNode(node);
      if (identical(targetRegion, region)) continue;
      final rect = _nodeRect(node);
      // Off-screen lazy children can report NaN geometry, which would slip
      // past every comparison below.
      if (rect == null || !rect.isFinite || rect.isEmpty) continue;
      if (rect.right <= regionRect.left || rect.left >= regionRect.right) {
        continue;
      }
      final gap = down
          ? rect.top - regionRect.bottom
          : regionRect.top - rect.bottom;
      if (gap < -1) continue;
      (byRegion[targetRegion ?? node] ??= []).add((node, rect));
      if (nearestGap == null || gap < nearestGap) nearestGap = gap;
    }
    if (nearestGap == null) return false;
    // The closest row: the group holding the smallest gap.
    List<(FocusNode, Rect)>? row;
    for (final group in byRegion.values) {
      final gap = group
          .map(
            (entry) => down
                ? entry.$2.top - regionRect.bottom
                : regionRect.top - entry.$2.bottom,
          )
          .reduce(math.min);
      if (gap == nearestGap) {
        row = group;
        break;
      }
    }
    if (row == null) return false;
    // Inside it, the card closest across to the one focused now.
    var nearest = row.first;
    for (final entry in row.skip(1)) {
      if ((entry.$2.center.dx - source.center.dx).abs() <
          (nearest.$2.center.dx - source.center.dx).abs()) {
        nearest = entry;
      }
    }
    final targetRegion = DpadRegion.ofNode(nearest.$1);
    // dpad 3.3 marks resolveEnter @internal with no public equivalent; it is
    // the only way to honor the target region's enter/restore memory the
    // same way dpad's own cross-region move does.
    // ignore: invalid_use_of_internal_member
    (targetRegion?.resolveEnter(nearest.$1, [
              for (final entry in row) entry.$1,
            ]) ??
            nearest.$1)
        .requestFocus();
    return true;
  }

  static Rect? _nodeRect(FocusNode node) {
    final context = node.context;
    return context == null || !context.mounted ? null : _globalRect(context);
  }

  static Rect? _globalRect(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontScale = FontSizeScope.scaleOf(context);
    final visibleItems = widget.items
        .take(widget.maxItems)
        .toList(growable: false);
    final visibleCount = widget.itemBuilder != null
        ? widget.itemCount!.clamp(0, widget.maxItems)
        : visibleItems.length;
    final double baseWidth;
    final double baseHeight;
    if (widget.itemBuilder != null) {
      baseWidth = widget.baseCardWidth!;
      baseHeight = widget.baseCardHeight!;
    } else if (widget.landscapeStyle) {
      baseWidth = MediaBrowsingMetrics.landscapeCardWidth;
      baseHeight = MediaBrowsingMetrics.landscapeCardHeight;
    } else if (widget.posterStyle) {
      baseWidth = MediaBrowsingMetrics.posterCardWidth;
      baseHeight = MediaBrowsingMetrics.posterCardHeight;
    } else {
      baseWidth = MediaBrowsingMetrics.previewCardWidth;
      baseHeight = MediaBrowsingMetrics.previewCardHeight;
    }
    // Scale off the window width rather than this row's LayoutBuilder
    // constraints: pushing a full-screen detail route re-parents the content
    // pane's `left` from 64 to 0 (see AppShell._buildTvLayout), and this row
    // stays mounted underneath that transition, so a constraints-derived
    // cardWidth would change the ResizeImage cache key every animation
    // frame, forcing a fresh decode per frame and flickering the thumbnails.
    // Subtracting the fixed rail inset and the row's own horizontal page
    // padding up front keeps the result correct for the sidebar layout's
    // steady state without reintroducing that per-frame dependency.
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        (widget.useSidebarLayout ? kSidebarRailInset * fontScale : 0) -
        MediaBrowsingMetrics.pagePadding * 2;
    final scale = _previewCardScale(availableWidth);
    final cardWidth = baseWidth * scale;
    // MediaPreviewCard multiplies its own width by FontSizeScope.scaleOf
    // (see below) on top of `cardWidth`, so the row height reserved for it
    // must grow by the same factor or a larger font setting overflows the
    // card's Column (bigger image + taller scaled-up text in a row height
    // that never grew to match).
    final cardHeight = baseHeight * scale * fontScale;
    // A custom card wider than the row is centred on focus and cut off on
    // both sides (phones); leave room to show the next one is there.
    final customCardWidth = math.min(
      cardWidth * fontScale,
      availableWidth * 0.9,
    );
    final viewAll = widget.viewAll;
    final cardCount = visibleCount + (viewAll == null ? 0 : 1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.titleIcon != null) ...[
                Icon(
                  widget.titleIcon,
                  size: 20 * fontScale,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          if (widget.isLoading)
            SizedBox(
              height: cardHeight + 16,
              child: ExcludeSemantics(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: MediaPreviewSection.maxVisibleItems,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MediaBrowsingMetrics.itemGap),
                  itemBuilder: (_, _) => _PreviewCardSkeleton(
                    width: widget.itemBuilder != null
                        ? customCardWidth
                        : cardWidth * fontScale,
                    shape: widget.itemBuilder != null
                        ? _PreviewSkeletonShape.tile
                        : widget.landscapeStyle
                        ? _PreviewSkeletonShape.landscape
                        : _PreviewSkeletonShape.poster,
                  ),
                ),
              ),
            )
          else if (visibleCount == 0)
            Text(widget.emptyLabel)
          else
            SizedBox(
              height: cardHeight + 16,
              // ExcludeSemantics prevents the tvOS framework bug where
              // ScrollableState.setIgnorePointer calls markNeedsSemanticsUpdate
              // during the semantics flush phase, causing an assertion crash
              // when scrolling quickly.
              child: ExcludeSemantics(
                child: DpadRegion(
                  key: _regionKey,
                  memoryKey: 'preview-row/${widget.title}',
                  horizontalEdge: DpadEdgeBehavior.stop,
                  verticalEdge: DpadEdgeBehavior.stop,
                  onEdge: (direction) {
                    switch (direction) {
                      case TraversalDirection.left:
                        widget.onSidebarActivate?.call();
                      case TraversalDirection.up when widget.onTopEdge != null:
                        widget.onTopEdge!.call();
                      case TraversalDirection.up:
                      case TraversalDirection.down:
                        _onVerticalEdge(direction);
                      case TraversalDirection.right:
                        break;
                    }
                  },
                  // No Scrollbar, matching the detail screens' episode + cast
                  // strips: desktop mouse users get hover arrows instead, and
                  // TV / phone pass straight through.
                  child: HoverScrollArrows(
                    controller: _controller,
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 12),
                      itemCount: cardCount,
                      separatorBuilder: (_, _) => const SizedBox(
                        width: MediaBrowsingMetrics.itemGap,
                      ),
                      itemBuilder: (context, index) {
                        if (index == visibleCount) {
                          return PreviewActionCard(
                            item: viewAll!,
                            width: widget.itemBuilder != null
                                ? customCardWidth
                                : cardWidth * fontScale,
                          );
                        }
                        final cardBuilder = widget.itemBuilder;
                        if (cardBuilder != null) {
                          return cardBuilder(
                            context,
                            index,
                            Size(customCardWidth, cardHeight),
                            autofocus: widget.autofocusFirst && index == 0,
                          );
                        }
                        return MediaPreviewCard(
                          item: visibleItems[index],
                          posterStyle: widget.posterStyle,
                          landscapeStyle: widget.landscapeStyle,
                          autofocus: widget.autofocusFirst && index == 0,
                          cardWidth: cardWidth,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _previewCardScale(double availableWidth) {
    if (availableWidth >= 1600) return 1;
    return (availableWidth / 1280.0).clamp(1.0, 1.15);
  }
}

enum _PreviewSkeletonShape { poster, landscape, tile }

/// A [MediaPreviewSection.isLoading] card: the card's background with blocks
/// where its art and text will go.
class _PreviewCardSkeleton extends StatelessWidget {
  const _PreviewCardSkeleton({required this.width, required this.shape});

  final double width;
  final _PreviewSkeletonShape shape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final block = colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(4),
        ),
        child: SizedBox(height: height * scale),
      ),
    );
    const radius = Radius.circular(MediaBrowsingMetrics.cardRadius);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(radius),
        ),
        child: shape == _PreviewSkeletonShape.tile
            ? const SizedBox.expand()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (shape == _PreviewSkeletonShape.landscape)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: block,
                        borderRadius: const BorderRadius.vertical(top: radius),
                      ),
                      child: SizedBox(height: width * 9 / 16),
                    )
                  else
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: block,
                          borderRadius: const BorderRadius.all(radius),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(0.7, 10),
                        const SizedBox(height: 6),
                        bar(0.4, 8),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// [MediaPreviewSection.viewAll]: an icon and label centered on a card the
/// size of the row's others.
/// A card that leads somewhere rather than showing a title: a row's View all,
/// or a one-card entry row (DVR, AIOStreams). An icon and a label on a
/// faint wash of the theme colour, so it reads apart from the artwork cards.
class PreviewActionCard extends StatelessWidget {
  const PreviewActionCard({
    super.key,
    required this.item,
    required this.width,
    this.autofocus = false,
  });

  final MediaPreviewItem item;
  final double width;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final subtitle = item.subtitle;
    final radius = BorderRadius.circular(MediaBrowsingMetrics.cardRadius);
    final primary = colorScheme.primary;
    final base = colorScheme.surfaceContainerHigh;
    final card = SizedBox(
      width: width,
      child: DpadInkWell(
        onTap: item.onTap,
        autofocus: autofocus,
        color: base,
        borderRadius: radius,
        // Ink, so the press ripple still shows over the wash.
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(primary.withValues(alpha: 0.18), base),
                base,
              ],
            ),
            border: Border.all(color: primary.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
            child: Center(
              // Scales down rather than overflowing the shorter Live TV tiles
              // at large font sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(12 * scale),
                        child: Icon(
                          item.fallbackIcon,
                          size: 28 * scale,
                          color: Color.alphaBlend(
                            primary.withValues(alpha: 0.55),
                            colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: MediaBrowsingMetrics.chipGap),
                    Text(
                      item.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (item.onFocused == null && item.onHoverChanged == null) return card;
    return PreviewFocusAnchor(
      onFocused: item.onFocused,
      onHoverChanged: item.onHoverChanged,
      contentKey: (item.title, item.subtitle),
      child: card,
    );
  }
}

/// A one-card entry row's card (DVR, AIOStreams, Requests): Continue
/// Watching's landscape size and text, so the rows line up, with a styled
/// 16:9 face in place of a thumbnail - a tinted wash, the section's icon,
/// and either a fan of [artworkUrls] (recording posters) or the icon again,
/// large and faint.
class PreviewEntryTile extends StatelessWidget {
  const PreviewEntryTile({
    super.key,
    required this.item,
    required this.width,
    this.artworkUrls = const [],
    this.accent,
    this.autofocus = false,
  });

  final MediaPreviewItem item;
  final double width;
  final List<String> artworkUrls;

  /// Tint for the face. Defaults to the theme's primary colour.
  final Color? accent;
  final bool autofocus;

  static const int _maxArtwork = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final artHeight = width * 9 / 16;
    final card = SizedBox(
      width: width,
      child: DpadInkWell(
        onTap: item.onTap,
        autofocus: autofocus,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: width,
              height: artHeight,
              child: _EntryTileFace(
                icon: item.fallbackIcon,
                accent: accent ?? colorScheme.primary,
                artworkUrls: artworkUrls
                    .where((url) => url.trim().isNotEmpty)
                    .take(_maxArtwork)
                    .toList(growable: false),
                height: artHeight,
              ),
            ),
            // Same text block as a landscape MediaPreviewCard.
            Padding(
              padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (item.onFocused == null && item.onHoverChanged == null) return card;
    return PreviewFocusAnchor(
      onFocused: item.onFocused,
      onHoverChanged: item.onHoverChanged,
      contentKey: (item.title, item.subtitle),
      child: card,
    );
  }
}

class _EntryTileFace extends StatelessWidget {
  const _EntryTileFace({
    required this.icon,
    required this.accent,
    required this.artworkUrls,
    required this.height,
  });

  final IconData icon;
  final Color accent;
  final List<String> artworkUrls;
  final double height;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    final scale = FontSizeScope.scaleOf(context);
    final badge = 40 * scale;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Ink, so the press ripple still shows over the wash.
        Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(accent.withValues(alpha: 0.34), base),
                Color.alphaBlend(accent.withValues(alpha: 0.08), base),
              ],
            ),
          ),
        ),
        if (artworkUrls.isEmpty)
          Positioned(
            right: -height * 0.12,
            bottom: -height * 0.18,
            child: Transform.rotate(
              angle: -0.18,
              child: Icon(
                icon,
                size: height * 0.95,
                color: accent.withValues(alpha: 0.16),
              ),
            ),
          )
        else
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: height * 1.15,
            child: _EntryTileArtwork(urls: artworkUrls, height: height),
          ),
        Positioned(
          left: MediaBrowsingMetrics.chipGap * 1.5,
          top: MediaBrowsingMetrics.chipGap * 1.5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(10 * scale),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: SizedBox.square(
              dimension: badge,
              child: Icon(
                icon,
                size: badge * 0.55,
                color: Color.alphaBlend(
                  accent.withValues(alpha: 0.45),
                  Colors.white,
                ),
              ),
            ),
          ),
        ),
        // A soft top edge light, like the sheen on the other cards' art.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0),
                ],
                stops: const [0, 0.4],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Up to three posters fanned against the tile's right edge, dissolving to
/// the left so they sit behind the badge rather than crowd it.
class _EntryTileArtwork extends StatelessWidget {
  const _EntryTileArtwork({required this.urls, required this.height});

  final List<String> urls;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cardHeight = height * 0.78;
    final cardWidth = cardHeight * 2 / 3;
    final step = cardWidth * 0.42;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        stops: [0, 0.45],
      ).createShader(bounds),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back to front: the first poster ends up on top, at the right.
          for (var i = urls.length - 1; i >= 0; i--)
            Positioned(
              right: height * 0.1 + i * step,
              top: (height - cardHeight) / 2 + i * height * 0.03,
              child: Transform.rotate(
                angle: 0.06 - i * 0.05,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x73000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ResilientMediaImage(
                    imageUrl: urls[i],
                    fallbackIcon: Icons.movie_outlined,
                    width: cardWidth,
                    height: cardHeight,
                    borderRadius: 6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MediaPreviewCard extends StatefulWidget {
  const MediaPreviewCard({
    required this.item,
    this.posterStyle = false,
    this.landscapeStyle = false,
    this.autofocus = false,
    this.cardWidth,
    this.keepAlive = true,
    super.key,
  });

  final MediaPreviewItem item;
  final bool posterStyle;
  final bool landscapeStyle;
  final bool autofocus;
  final double? cardWidth;

  /// Horizontal preview rows keep cards alive so sideways scrolling does not
  /// re-decode their thumbnails. Vertical grids (Movies/Series listing pages)
  /// pass false: those lists can run to thousands of items, where keeping every
  /// scrolled-past card mounted is an unbounded memory cost.
  final bool keepAlive;

  @override
  State<MediaPreviewCard> createState() => _MediaPreviewCardState();
}

class _MediaPreviewCardState extends State<MediaPreviewCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    assert(
      !widget.landscapeStyle || item.emphasisLabel == null,
      'MediaPreviewItem.emphasisLabel is not rendered by landscape cards.',
    );
    final baseWidth =
        widget.cardWidth ??
        (widget.landscapeStyle
            ? MediaBrowsingMetrics.landscapeCardWidth
            : widget.posterStyle
            ? MediaBrowsingMetrics.posterCardWidth
            : MediaBrowsingMetrics.previewCardWidth);
    final width = baseWidth * FontSizeScope.scaleOf(context);

    final card = SizedBox(
      width: width,
      child: DpadInkWell(
        autofocus: widget.autofocus,
        onTap: item.onTap,
        onLongTap: item.onLongTap,
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        // Landscape cards still edge-clip their full-bleed thumbnail. Default/
        // poster cards deliberately do not clip: the card's rounded background
        // stays visible behind the poster, which carries its own matching
        // corner radius (see `_buildDefaultContent`) - the detail-page look.
        clipBehavior: widget.landscapeStyle ? Clip.antiAlias : Clip.none,
        child: widget.landscapeStyle
            ? _buildLandscapeContent(context, colorScheme, width)
            : _buildDefaultContent(context, colorScheme),
      ),
    );
    if (item.onFocused == null && item.onHoverChanged == null) return card;
    return PreviewFocusAnchor(
      onFocused: item.onFocused,
      onHoverChanged: item.onHoverChanged,
      // Rows rebuild cards in place by index, so a focused card can start
      // showing a different entry (e.g. Continue Watching dropping one after
      // syncing with the server) without focus changing.
      contentKey: (item.title, item.subtitle, item.imageUrl),
      child: card,
    );
  }

  Widget _buildLandscapeContent(
    BuildContext context,
    ColorScheme colorScheme,
    double width,
  ) {
    final item = widget.item;
    final imageHeight = width * 9 / 16;
    final hasBadges = widget.item.overlayBadges.isNotEmpty;
    final hasProgress = widget.item.progressFraction != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widget.item.imagePadding,
          child: SizedBox(
            width: width,
            height: imageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ResilientMediaImage(
                  imageUrl: item.imageUrl,
                  fallbackIcon: item.fallbackIcon,
                  width: width,
                  height: imageHeight,
                  fit: item.imageFit,
                  fallbackTitle: item.fallbackTitle,
                  backgroundColor: item.imageBackgroundColor,
                  borderRadius: 0,
                ),
                if (hasBadges || hasProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: imageHeight * 0.45,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (widget.item.overlayLabel != null)
                  Positioned(
                    left: 6,
                    bottom: hasProgress ? 9 : 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          widget.item.overlayLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                if (hasBadges)
                  Positioned(
                    right: 6,
                    bottom: hasProgress ? 9 : 6,
                    child: Row(
                      children: [
                        for (final badge in widget.item.overlayBadges)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  badge,
                                  style:
                                      Theme.of(
                                        context,
                                      ).textTheme.labelSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hasProgress)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          '${(widget.item.progressFraction! * 100).round()}%',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
                if (hasProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: widget.item.progressFraction,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      color: colorScheme.primary,
                    ),
                  ),
                if (widget.item.upNextLabel != null)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          widget.item.upNextLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultContent(BuildContext context, ColorScheme colorScheme) {
    final item = widget.item;
    final posterStyle = widget.posterStyle;
    // Year and rating share the muted line under the title, joined by a
    // separator when both are present (e.g. "2004 • ★ 8.1").
    final subtitleText = [
      if (item.subtitle != null && item.subtitle!.isNotEmpty) item.subtitle!,
      if (item.ratingLabel != null && item.ratingLabel!.isNotEmpty)
        item.ratingLabel!,
    ].join(' • ');
    final mediaImage = ResilientMediaImage(
      imageUrl: item.imageUrl,
      fallbackIcon: item.fallbackIcon,
      fit: item.imageFit,
      aspectRatio: item.imageAspectRatio,
      fallbackTitle: item.fallbackTitle,
      backgroundColor: item.imageBackgroundColor,
      borderRadius: MediaBrowsingMetrics.cardRadius,
    );
    final scale = FontSizeScope.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: widget.item.imagePadding,
            child: Stack(
              fit: StackFit.expand,
              children: [
                mediaImage,
                if (item.isFavorite)
                  Positioned(
                    top: 4 * scale,
                    left: 4 * scale,
                    child: Container(
                      padding: EdgeInsets.all(3 * scale),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.star,
                        color: Colors.white,
                        size: 14 * scale,
                      ),
                    ),
                  )
                else if (item.cornerBadgeIcon != null)
                  Positioned(
                    top: 4 * scale,
                    left: 4 * scale,
                    child: Container(
                      padding: EdgeInsets.all(3 * scale),
                      decoration: BoxDecoration(
                        color: item.cornerBadgeColor ?? colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.cornerBadgeIcon,
                        color: Colors.white,
                        size: 14 * scale,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: posterStyle ? FontWeight.normal : FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.emphasisLabel != null) ...[
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.emphasisLabel!,
                    maxLines: 1,
                    softWrap: false,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
              if (subtitleText.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
