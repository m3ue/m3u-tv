import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Visual treatment for a [RowAction]. `danger` reads as destructive (red
/// ghost button / red menu item) — for actions like Stop or Delete.
enum RowActionType { normal, danger }

/// A single action offered by [RowActionMenu].
class RowAction {
  const RowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.type = RowActionType.normal,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final RowActionType type;

  bool get isDanger => type == RowActionType.danger;
}

/// Row-level action menu with two presentations for the same [actions],
/// so list rows can offer several actions without hiding them behind a
/// floating menu a d-pad can't reach into:
///
/// * **Compact** (`inline: false` — touch/mobile): a single "more" button
///   that opens a [MenuAnchor] dropdown, as before. Touch can reach a
///   floating menu fine, so this stays the space-efficient choice there.
/// * **Inline** (`inline: true` — desktop/TV): the "more" button (which
///   rotates a quarter turn rather than swapping icons) toggles a row of
///   icon buttons that slide and fade out to its left in a staggered
///   sequence, collapsing again once focus leaves the row or an action
///   fires. Every action becomes directly d-pad-focusable — the whole
///   reason this presentation exists, since a [MenuAnchor]'s overlay
///   content isn't reliably d-pad-navigable (see the comment on
///   `_useInlineRowActions` in `dvr_recordings_screen.dart` for how callers
///   are expected to detect TV/desktop correctly, including Android TV).
///
/// Trailing padding is baked in (not left to callers) so the trigger never
/// sits flush against a list's scrollbar — including on TV/mobile, where
/// the scrollbar track is present but invisible until scrolled.
class RowActionMenu extends StatefulWidget {
  const RowActionMenu({
    super.key,
    required this.actions,
    required this.moreLabel,
    required this.inline,
    this.autofocus = false,
  });

  final List<RowAction> actions;
  final String moreLabel;
  final bool inline;
  final bool autofocus;

  @override
  State<RowActionMenu> createState() => _RowActionMenuState();
}

class _RowActionMenuState extends State<RowActionMenu>
    with SingleTickerProviderStateMixin {
  static const _menuEffects = <DpadEffect>[
    GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
  ];
  static const _menuWidth = 180.0;
  static const _menuStyle = MenuStyle(
    minimumSize: WidgetStatePropertyAll(Size(_menuWidth, 0)),
  );
  static const _expandDuration = Duration(milliseconds: 320);
  // Matches AppIconButton's fixed 56x56 footprint plus the 8px gap each
  // action is padded with below, so the reserved space can be computed
  // without measuring — it's what lets the reveal grow without clipping
  // (see _buildInline).
  static const _actionSlotWidth = 64.0;
  static const _actionRowHeight = 56.0;
  // Fraction of the timeline each later action's own slide/fade is offset
  // by, so they visibly follow one another instead of moving in lockstep.
  static const _staggerStep = 0.12;
  // How much of the timeline a single action's slide/fade animates over.
  static const _itemSpan = 0.6;
  // Keeps the trigger clear of a list's scrollbar track, which reserves
  // this much space at the edge even while its thumb is hidden.
  static const _trailingPadding = 16.0;

  final MenuController _menuController = MenuController();
  late final AnimationController _expandController;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Constructed eagerly (not lazily via `late final = ...`): the compact
    // (touch) presentation never calls into inline-only code, so a lazy
    // initializer wouldn't run until `dispose()` first touched the field —
    // by then the element is deactivated and creating the ticker crashes.
    _expandController = AnimationController(
      vsync: this,
      duration: _expandDuration,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      unawaited(_expandController.forward());
    } else {
      unawaited(_expandController.reverse());
    }
  }

  void _collapse() {
    if (_expanded) {
      setState(() => _expanded = false);
      unawaited(_expandController.reverse());
    }
  }

  /// Eased 0..1 progress for action [index]'s own slide/fade, offset by
  /// [_staggerStep] per index so they reveal in sequence rather than all at
  /// once.
  double _actionProgress(int index) {
    final start = (index * _staggerStep).clamp(0.0, 1.0 - _itemSpan);
    final raw = ((_expandController.value - start) / _itemSpan).clamp(
      0.0,
      1.0,
    );
    return Curves.easeOutCubic.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: _trailingPadding),
      child: widget.inline ? _buildInline(context) : _buildCompact(context),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = [
      for (final action in widget.actions)
        SizedBox(
          width: _menuWidth,
          child: MenuItemButton(
            leadingIcon: Icon(
              action.icon,
              color: action.isDanger ? colorScheme.error : null,
            ),
            onPressed: () {
              _menuController.close();
              action.onPressed();
            },
            child: Text(
              action.label,
              style: action.isDanger
                  ? TextStyle(color: colorScheme.error)
                  : null,
            ),
          ),
        ),
    ];

    return DpadFocusable(
      autofocus: widget.autofocus,
      onSelect: _toggleMenu,
      effects: _menuEffects,
      child: MenuAnchor(
        controller: _menuController,
        style: _menuStyle,
        menuChildren: items,
        child: IconButton(
          tooltip: widget.moreLabel,
          onPressed: _toggleMenu,
          icon: const Icon(Icons.more_vert),
        ),
      ),
    );
  }

  Widget _buildInline(BuildContext context) {
    // Deliberately a plain `Focus` node, not a `DpadRegion`: a nested region
    // would exclude these buttons from the enclosing list region's
    // candidate set entirely, so d-pad right from the row content would
    // hit the list region's edge (stop) and never reach them — reachable
    // only by direct tap/click. `Focus` still reports focus-enter/exit for
    // the collapse-on-blur behavior without partitioning traversal.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) _collapse();
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _expandController,
            builder: (context, _) {
              if (_expandController.value == 0) {
                return const SizedBox.shrink();
              }
              final reservedWidth =
                  Curves.easeOutCubic.transform(_expandController.value) *
                  widget.actions.length *
                  _actionSlotWidth;
              return SizedBox(
                width: reservedWidth,
                height: _actionRowHeight,
                // No ClipRect: each action slides/fades in on its own
                // timeline below, so it's never visually chopped by a
                // growing box edge the way wiping the whole row in via
                // AnimatedSize used to look. Stack lets the not-yet-fully-
                // grown box's Positioned children overflow its bounds
                // instead of clipping to them.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < widget.actions.length; i++)
                            _InlineAction(
                              action: widget.actions[i],
                              progress: _actionProgress(i),
                              onPressed: () {
                                _collapse();
                                widget.actions[i].onPressed();
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          AnimatedRotation(
            turns: _expanded ? 0.25 : 0,
            duration: _expandDuration,
            curve: Curves.easeOutCubic,
            child: AppIconButton(
              autofocus: widget.autofocus,
              icon: Icons.more_vert,
              tooltip: widget.moreLabel,
              onPressed: _toggleExpanded,
            ),
          ),
        ],
      ),
    );
  }
}

/// One action inside the inline row's expanded reveal — slides in from
/// behind the trigger button while fading in, per [progress] (0 hidden, 1
/// fully in place).
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.action,
    required this.progress,
    required this.onPressed,
  });

  final RowAction action;
  final double progress;
  final VoidCallback onPressed;

  // Starting slide offset, in logical pixels — how far right of its final
  // position an action starts before easing in.
  static const _slideDistance = 20.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset((1 - progress) * _slideDistance, 0),
          child: IgnorePointer(
            ignoring: progress < 1,
            child: AppIconButton(
              icon: action.icon,
              tooltip: action.label,
              variant: action.isDanger
                  ? AppButtonVariant.destructive
                  : AppButtonVariant.tonal,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
