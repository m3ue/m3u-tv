import 'dart:async';

import 'package:dpad/dpad.dart' show DpadFocusState;
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart' show SelectHold;
import 'package:material_ui/material_ui.dart';

const double _kCardWidth = MediaBrowsingMetrics.posterCardWidth;
const double _kCardAspectRatio = 0.68;
const double _kCardGap = 12;
// Breathing room between the poster/title and the focus border - without it
// the border is drawn flush against (and visually overlaps) the content.
const double _kCardVerticalPadding = 4;
const double _kCardHorizontalPadding = 4;
const double _kCardImageTextGap = 6;
const double _kBorderRadius = MediaBrowsingMetrics.cardRadius;

/// A "locked focus" horizontal poster row, shared by every screen that shows
/// a scrollable strip of poster cards (Related titles, an actor's
/// filmography, ...) so the layout, spacing, corner radii, and D-pad
/// behaviour can't drift apart between them - change it once here and every
/// caller picks it up.
///
/// Follows the exact focus-handling pattern of `CastStrip`
/// (cast_strip.dart): one plain [Focus] stop that owns every arrow/select key
/// itself and always consumes it, so nothing reaches dpad's directional
/// traversal. Left/right move an internal index; up/down are handed to
/// [onNavigateUp] / [onNavigateDown] (always consumed). Selecting a poster
/// opens that item via [onTap] - unless [available] says it can't be (an
/// actor filmography credit not in the caller's library, say), in which case
/// selection is a no-op, same as a disabled `MediaPreviewCard`.
class PosterStrip<T> extends StatefulWidget {
  const PosterStrip({
    super.key,
    required this.items,
    required this.itemKey,
    required this.title,
    required this.posterUrl,
    required this.fallbackIcon,
    required this.onTap,
    this.subtitle,
    this.available,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onReveal,
    this.autofocus = false,
    this.debugLabel = 'posterStrip',
  });

  final List<T> items;

  /// Uniquely identifies an item across rebuilds (`ValueKey` source) - e.g. a
  /// TMDB id.
  final Object Function(T item) itemKey;
  final String Function(T item) title;
  final String? Function(T item) posterUrl;
  final IconData Function(T item) fallbackIcon;
  final ValueChanged<T> onTap;

  /// Optional second line under the title (e.g. a release year). Reserving
  /// its line height is all-or-nothing per strip, not per item - pass it
  /// whenever any item in this strip may have one.
  final String? Function(T item)? subtitle;

  /// Null means every item is always available (the common case - Related
  /// titles). Unavailable items render dimmed and ignore selection.
  final bool Function(T item)? available;

  /// Up pressed while the row holds focus. Always consumed regardless.
  final VoidCallback? onNavigateUp;

  /// Down pressed while the row holds focus. Always consumed regardless.
  final VoidCallback? onNavigateDown;

  /// Called with this strip's [BuildContext] whenever it gains focus, so a
  /// host scroll region can bring it into view. Null when the row is always
  /// on-screen.
  final void Function(BuildContext context)? onReveal;

  final bool autofocus;
  final String debugLabel;

  @override
  State<PosterStrip<T>> createState() => PosterStripState<T>();
}

class PosterStripState<T> extends State<PosterStrip<T>> {
  final ScrollController _controller = ScrollController();
  late final FocusNode _focusNode = FocusNode(debugLabel: widget.debugLabel);
  final SelectHold _selectHold = SelectHold();
  int _focusedIndex = 0;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(PosterStrip<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusedIndex >= widget.items.length) {
      _focusedIndex = widget.items.isEmpty ? 0 : widget.items.length - 1;
      if (widget.items.isNotEmpty) _centerFocused(animate: false);
    }
  }

  @override
  void dispose() {
    _selectHold.dispose();
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _centerFocused(animate: false);
      widget.onReveal?.call(context);
    }
  }

  /// Take focus, park the cursor, and ask the host to reveal the row. Public
  /// so a sibling row / screen can hop focus here.
  void focusRow() {
    _focusNode.requestFocus();
    _centerFocused(animate: false);
    widget.onReveal?.call(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (SelectHold.isSelectKey(key)) {
      return _selectHold.handle(
        event,
        isActive: () => mounted,
        onTap: _selectFocused,
      );
    }
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isDown) _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown) _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onNavigateUp == null) return KeyEventResult.ignored;
      if (isDown) widget.onNavigateUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.onNavigateDown == null) return KeyEventResult.ignored;
      if (isDown) widget.onNavigateDown!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _scale => FontSizeScope.scaleOf(context);
  double get _cardWidth => _kCardWidth * _scale;
  double get _cardGap => _kCardGap * _scale;
  double get _itemExtent => _cardWidth + _cardGap;

  void _centerFocused({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final target =
          (_focusedIndex * _itemExtent +
                  _cardWidth / 2 -
                  position.viewportDimension / 2)
              .clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      if (animate) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
        );
      } else {
        position.jumpTo(target);
      }
    });
  }

  void _moveFocus(int delta) {
    if (widget.items.isEmpty) return;
    final target = (_focusedIndex + delta).clamp(0, widget.items.length - 1);
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _centerFocused();
  }

  bool _isAvailable(T item) => widget.available?.call(item) ?? true;

  void _selectFocused() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.items.length) return;
    final item = widget.items[_focusedIndex];
    if (!_isAvailable(item)) return;
    widget.onTap(item);
  }

  /// Mouse/touch tap on a card - the row is a single locked focus stop for
  /// D-pad purposes, so this bypasses that and activates directly rather
  /// than routing through key-based selection.
  void _selectByMouse(int index) {
    _focusNode.requestFocus();
    setState(() => _focusedIndex = index);
    final item = widget.items[index];
    if (!_isAvailable(item)) return;
    widget.onTap(item);
  }

  // Measures the title/subtitle text style's actual rendered line height
  // rather than guessing a fixed pixel value, which drifts out of sync with
  // real font metrics across locales/devices (and is easy to get wrong once,
  // let alone twice, per caller).
  double _textLineHeight(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    final painter = TextPainter(
      text: TextSpan(text: 'Mg', style: style),
      textDirection: Directionality.of(context),
    )..layout();
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final lineCount = widget.subtitle == null ? 1 : 2;
    // No Scrollbar wrapper - see CastStrip.build for why (fast key-repeat
    // races the ListView's own ignore-pointer toggling into a semantics
    // assertion storm).
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox(
        height:
            _cardWidth / _kCardAspectRatio +
            _kCardVerticalPadding * 2 +
            _kCardImageTextGap +
            lineCount * _textLineHeight(context) +
            2,
        child: HoverScrollArrows(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Padding(
                padding: EdgeInsets.only(right: _cardGap),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _selectByMouse(index),
                  child: _PosterStripCard(
                    key: ValueKey(widget.itemKey(item)),
                    title: widget.title(item),
                    subtitle: widget.subtitle?.call(item),
                    posterUrl: widget.posterUrl(item),
                    fallbackIcon: widget.fallbackIcon(item),
                    width: _cardWidth,
                    focused: _hasFocus && index == _focusedIndex,
                    available: _isAvailable(item),
                    staggerIndex: index,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a card up into place, staggered by [staggerIndex] so the
/// row cascades in one card at a time rather than popping in as a single
/// block.
class _PosterStripCard extends StatefulWidget {
  const _PosterStripCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.fallbackIcon,
    required this.width,
    required this.focused,
    required this.available,
    required this.staggerIndex,
  });

  final String title;
  final String? subtitle;
  final String? posterUrl;
  final IconData fallbackIcon;
  final double width;
  final bool focused;
  final bool available;
  final int staggerIndex;

  @override
  State<_PosterStripCard> createState() => _PosterStripCardState();
}

class _PosterStripCardState extends State<_PosterStripCard> {
  static const _staggerStep = Duration(milliseconds: 45);
  static const _maxStaggeredIndex = 8;

  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final delay =
        _staggerStep * widget.staggerIndex.clamp(0, _maxStaggeredIndex);
    _timer = Timer(delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = widget.width;
    final focused = widget.focused;
    final body = Opacity(
      opacity: widget.available ? 1 : 0.4,
      child: Padding(
        // Keep the focus border off the poster / title.
        padding: const EdgeInsets.symmetric(
          vertical: _kCardVerticalPadding,
          horizontal: _kCardHorizontalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _kCardAspectRatio,
              // Default borderRadius (MediaBrowsingMetrics.posterRadius) is
              // deliberately smaller than the outer focus border's
              // (_kBorderRadius, MediaBrowsingMetrics.cardRadius) by the
              // card's inset padding above, so the two corners are
              // concentric instead of visibly mismatched.
              child: ResilientMediaImage(
                imageUrl: widget.posterUrl,
                fallbackIcon: widget.fallbackIcon,
              ),
            ),
            const SizedBox(height: _kCardImageTextGap),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.15),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        child: SizedBox(
          width: width,
          child:
              GradientBorderEffect(
                borderRadius: BorderRadius.circular(_kBorderRadius),
              ).build(
                context,
                DpadFocusState(focused: focused, pressed: false),
                body,
              ),
        ),
      ),
    );
  }
}
