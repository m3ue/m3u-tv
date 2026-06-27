import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// A [DpadFocusable] + [Material] + [InkWell] composite that guarantees the
/// focus border appears on tap and fast-tap, not just D-pad navigation.
///
/// The root cause of the fast-tap miss: [DpadFocusable] calls `requestFocus()`
/// in `onTapDown`, but `setState(_focused = true)` is scheduled and may be
/// overtaken by the action's own `setState` before the frame renders.
/// Calling `requestFocus()` again synchronously inside `onTap` (before the
/// action) ensures the focus manager records the right node.
///
/// All interactive TV widgets that show a border-on-focus should use this
/// instead of the manual `DpadFocusable + Material + InkWell` pattern.
class DpadInkWell extends StatefulWidget {
  const DpadInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongTap,
    this.effects,
    this.autofocus = false,
    this.entry = false,
    this.color,
    this.borderRadius,
    this.scrollPadding,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final List<DpadEffect>? effects;
  final bool autofocus;
  final bool entry;
  final Color? color;
  final BorderRadius? borderRadius;
  final double? scrollPadding;
  final Clip clipBehavior;

  @override
  State<DpadInkWell> createState() => _DpadInkWellState();
}

class _DpadInkWellState extends State<DpadInkWell> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onTap() {
    _focusNode.requestFocus();
    widget.onTap?.call();
  }

  bool get _isInteractive => widget.onTap != null || widget.onLongTap != null;

  void _setHovered(bool hovered) {
    if (!_isInteractive || _hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  void didUpdateWidget(DpadInkWell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hovered && !_isInteractive) setState(() => _hovered = false);
  }

  @override
  Widget build(BuildContext context) {
    final effects =
        widget.effects ??
        [
          GradientBorderEffect(
            borderRadius:
                widget.borderRadius ??
                const BorderRadius.all(Radius.circular(8)),
          ),
        ];
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: DpadFocusable(
        focusNode: _focusNode,
        onSelect: widget.onTap == null ? null : _onTap,
        onLongSelect: widget.onLongTap,
        builder: (context, state, child) => DpadEffect.wrap(
          context,
          effects,
          DpadFocusState(
            focused: state.focused || _hovered,
            pressed: state.pressed,
          ),
          child,
        ),
        autofocus: widget.autofocus,
        entry: widget.entry,
        scrollPadding: widget.scrollPadding,
        child: Material(
          color: widget.color ?? Colors.transparent,
          borderRadius: widget.borderRadius,
          clipBehavior: widget.clipBehavior,
          child: InkWell(
            onTap: widget.onTap == null ? null : _onTap,
            onLongPress: widget.onLongTap,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
