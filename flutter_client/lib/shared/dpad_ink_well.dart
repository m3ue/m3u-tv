import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.enabled = true,
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
  final bool enabled;
  final bool entry;
  final Color? color;
  final BorderRadius? borderRadius;
  final double? scrollPadding;
  final Clip clipBehavior;

  /// Count of [HardwareKeyboard] global handlers this class currently has
  /// registered and not yet released. Exposed for leak-detection tests.
  @visibleForTesting
  static int debugActiveGlobalHandlers = 0;

  @override
  State<DpadInkWell> createState() => _DpadInkWellState();
}

class _DpadInkWellState extends State<DpadInkWell> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;

  // The long-select menu opens at the threshold mid-hold. A freshly-mounted
  // autofocused child inside that menu must NOT act on the select button
  // the user is still physically holding: Android TV's auto-repeat delivers
  // fresh `KeyDownEvent`s (not `KeyRepeatEvent`, which the dpad package
  // swallows) to the newly focused widget, and a child with `onLongSelect`
  // wired would see its 500ms timer re-armed on every repeat.
  //
  // Only the autofocused item inside the newly-built menu can ever receive
  // that routed phantom KeyDownEvent, so only it needs to arm the guard.
  // On mount, we sample the specific select key(s) already held (not just
  // "a select key is held") and arm a global handler that clears each held
  // key on its own KeyUp. The guard disarms only once none of the keys held
  // at mount are still down, so an unrelated select-mapped key (e.g. a
  // keyboard Enter pressed alongside a held remote select button) can't
  // prematurely disarm it. Widgets mounted with no key held are never
  // armed, so a blanket ignore-window does not regress normal D-pad taps.
  Set<LogicalKeyboardKey> _heldSelectKeys = const {};
  bool _guardChecked = false;
  bool _handlerRegistered = false;
  DpadKeySet? _cachedKeySet;

  bool get _ignoreSelect => _heldSelectKeys.isNotEmpty;

  @override
  void dispose() {
    if (_handlerRegistered) {
      HardwareKeyboard.instance.removeHandler(_onGlobalKey);
      _handlerRegistered = false;
      DpadInkWell.debugActiveGlobalHandlers--;
    }
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_guardChecked) return;
    _guardChecked = true;
    // Only the autofocused item in a freshly-built menu can receive the
    // routed phantom KeyDownEvent, so only it needs the guard armed.
    if (!widget.autofocus) return;
    final keys = Dpad.keySetOf(context);
    _cachedKeySet = keys;
    final heldSelectKeys = HardwareKeyboard.instance.logicalKeysPressed.where(
      keys.isSelect,
    );
    if (heldSelectKeys.isNotEmpty) {
      _heldSelectKeys = heldSelectKeys.toSet();
      HardwareKeyboard.instance.addHandler(_onGlobalKey);
      _handlerRegistered = true;
      DpadInkWell.debugActiveGlobalHandlers++;
    }
  }

  bool _onGlobalKey(KeyEvent event) {
    final keys = _cachedKeySet;
    if (event is KeyUpEvent &&
        keys != null &&
        keys.isSelect(event.logicalKey) &&
        _heldSelectKeys.remove(event.logicalKey) &&
        _heldSelectKeys.isEmpty &&
        _handlerRegistered) {
      HardwareKeyboard.instance.removeHandler(_onGlobalKey);
      _handlerRegistered = false;
      DpadInkWell.debugActiveGlobalHandlers--;
    }
    // Always let the event continue to propagate; this is a guard, not a
    // consumer.
    return false;
  }

  void _onTap() {
    if (!widget.enabled) return;
    _focusNode.requestFocus();
    widget.onTap?.call();
  }

  void _onDpadSelect() {
    if (_ignoreSelect) return;
    _onTap();
  }

  void _onDpadLongSelect() {
    if (_ignoreSelect) return;
    final onLongTap = widget.onLongTap;
    if (onLongTap == null) return;
    // Fire synchronously. The dpad package invokes onLongSelect from a Timer
    // callback, never from build, so opening a route here is safe.
    // addPostFrameCallback is NOT safe here: it registers a callback but does
    // not schedule a frame, so on a real device the menu sat queued until the
    // key release triggered the next rebuild — the "menu only opens on
    // release" bug. Widget tests miss this because pump() forces frames.
    _focusNode.requestFocus();
    onLongTap();
  }

  bool get _isInteractive =>
      widget.enabled && (widget.onTap != null || widget.onLongTap != null);

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
        onSelect: widget.onTap == null ? null : _onDpadSelect,
        onLongSelect: widget.onLongTap == null ? null : _onDpadLongSelect,
        enabled: widget.enabled,
        // InkWell handles touch taps; DpadFocusable.onSelect handles D-pad key
        // events. The default tapToSelect: true wraps the child in a
        // GestureDetector whose onTapDown calls requestFocus() before the
        // gesture arena resolves. On a scroll gesture this schedules a
        // DpadScroll.ensureVisible that can interrupt a fling with an
        // animateTo() counter-animation.
        tapToSelect: false,
        builder: (context, state, child) {
          return DpadEffect.wrap(
            context,
            effects,
            DpadFocusState(
              focused: state.focused || _hovered,
              pressed: state.pressed,
            ),
            child,
          );
        },
        autofocus: widget.autofocus,
        entry: widget.entry,
        scrollPadding: widget.scrollPadding,
        child: Material(
          color: widget.color ?? Colors.transparent,
          borderRadius: widget.borderRadius,
          clipBehavior: widget.clipBehavior,
          child: InkWell(
            // Touch path is intentionally NOT guarded — the guard exists
            // for inherited D-pad holds from a parent long-press, not for
            // touch input.
            onTap: widget.enabled && widget.onTap != null ? _onTap : null,
            onLongPress: widget.enabled ? widget.onLongTap : null,
            borderRadius: widget.borderRadius,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
