import 'dart:async';

import 'package:dpad/dpad.dart' show DpadFocusState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart' show SelectHold;

// Matches MediaPreviewCard's posterStyle width elsewhere in the app (Movies/
// Series grids, AIOStreams catalog rows) - a "related" card is the same kind
// of poster tile, not a smaller cast-avatar-style thumbnail.
const double _kCardWidth = MediaBrowsingMetrics.posterCardWidth;
const double _kCardAspectRatio = 0.68;
const double _kCardTextHeight = 20;
const double _kCardGap = 12;
// Breathing room between the poster/title and the focus border - without it
// the border is drawn flush against (and visually overlaps) the content.
const double _kCardVerticalPadding = 4;
const double _kCardHorizontalPadding = 4;

/// A "locked focus" horizontal poster row for the "Related" titles shown
/// below the cast row on a movie/series detail screen.
///
/// Follows the exact focus-handling pattern of `CastStrip`
/// (cast_strip.dart): one plain [Focus] stop that owns every arrow/select key
/// itself and always consumes it, so nothing reaches dpad's directional
/// traversal. Left/right move an internal index; up/down are handed to
/// [onNavigateUp] / [onNavigateDown] (always consumed). Unlike `CastStrip`,
/// each card here is actionable - selecting a poster opens that title's own
/// detail screen via [onTap].
///
/// Shared by the Series and VOD/movie detail screens (Xtream and AIOStreams)
/// so a related-items row cannot drift on layout/behaviour between them.
class RelatedStrip extends StatefulWidget {
  const RelatedStrip({
    super.key,
    required this.items,
    required this.onTap,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onReveal,
    this.autofocus = false,
    this.debugLabel = 'relatedStrip',
  });

  final List<RelatedItem> items;
  final ValueChanged<RelatedItem> onTap;

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
  State<RelatedStrip> createState() => RelatedStripState();
}

class RelatedStripState extends State<RelatedStrip> {
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
  void didUpdateWidget(RelatedStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusedIndex >= widget.items.length) {
      _focusedIndex = widget.items.isEmpty ? 0 : widget.items.length - 1;
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

  void _selectFocused() {
    if (_focusedIndex < 0 || _focusedIndex >= widget.items.length) return;
    widget.onTap(widget.items[_focusedIndex]);
  }

  /// Mouse/touch tap on a card - the row is a single locked focus stop for
  /// D-pad purposes, so this bypasses that and activates directly rather
  /// than routing through key-based selection.
  void _selectByMouse(int index) {
    _focusNode.requestFocus();
    setState(() => _focusedIndex = index);
    widget.onTap(widget.items[index]);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
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
            _kCardTextHeight * FontSizeScope.scaleOf(context),
        child: HoverScrollArrows(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            itemCount: items.length,
            itemBuilder: (context, index) => Padding(
              padding: EdgeInsets.only(right: _cardGap),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectByMouse(index),
                child: _RelatedStripCard(
                  key: ValueKey(items[index].id),
                  item: items[index],
                  width: _cardWidth,
                  focused: _hasFocus && index == _focusedIndex,
                  staggerIndex: index,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a card up into place, staggered by [staggerIndex] so the
/// row cascades in one card at a time rather than popping in as a single
/// block (matches how CastRevealSlot's own arrival reads as one gentle
/// motion rather than a jump-cut).
class _RelatedStripCard extends StatefulWidget {
  const _RelatedStripCard({
    super.key,
    required this.item,
    required this.width,
    required this.focused,
    required this.staggerIndex,
  });

  final RelatedItem item;
  final double width;
  final bool focused;
  final int staggerIndex;

  @override
  State<_RelatedStripCard> createState() => _RelatedStripCardState();
}

class _RelatedStripCardState extends State<_RelatedStripCard> {
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
    final item = widget.item;
    final width = widget.width;
    final focused = widget.focused;
    final body = Padding(
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
            child: ResilientMediaImage(
              imageUrl: item.posterUrl,
              fallbackIcon: item.isSeries ? Icons.tv : Icons.movie,
              borderRadius: MediaBrowsingMetrics.cardRadius,
              fallbackTitle: item.title,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
                borderRadius: BorderRadius.circular(
                  MediaBrowsingMetrics.cardRadius,
                ),
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
