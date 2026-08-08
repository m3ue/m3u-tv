import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Visual treatment for a [RowAction]. `danger` reads as destructive (red
/// ghost button / red menu item) - for actions like Stop or Delete.
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
/// * **Compact** (`inline: false` - touch/mobile): a single "more" button
///   that opens a [MenuAnchor] dropdown, as before. Touch can reach a
///   floating menu fine, so this stays the space-efficient choice there.
/// * **Inline** (`inline: true` - desktop/TV): the "more" button toggles a
///   row of icon buttons that grow out to its left in place (animated via
///   [AnimatedSize], collapsing again once focus leaves the row or an
///   action fires). Every action becomes directly d-pad-focusable - the
///   whole reason this presentation exists, since a [MenuAnchor]'s overlay
///   content isn't reliably d-pad-navigable (see the comment on
///   `_useInlineRowActions` in `dvr_recordings_screen.dart` for how callers
///   are expected to detect TV/desktop correctly, including Android TV).
///
/// Trailing padding is baked in (not left to callers) so the trigger never
/// sits flush against a list's scrollbar - including on TV/mobile, where
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

class _RowActionMenuState extends State<RowActionMenu> {
  static const _menuEffects = <DpadEffect>[
    GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
  ];
  static const _menuWidth = 180.0;
  static const _menuStyle = MenuStyle(
    minimumSize: WidgetStatePropertyAll(Size(_menuWidth, 0)),
  );
  static const _expandDuration = Duration(milliseconds: 220);
  // Keeps the trigger clear of a list's scrollbar track, which reserves
  // this much space at the edge even while its thumb is hidden.
  static const _trailingPadding = 16.0;

  final MenuController _menuController = MenuController();
  bool _expanded = false;

  void _toggleMenu() {
    if (_menuController.isOpen) {
      _menuController.close();
    } else {
      _menuController.open();
    }
  }

  void _toggleExpanded() => setState(() => _expanded = !_expanded);

  void _collapse() {
    if (_expanded) setState(() => _expanded = false);
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
    // hit the list region's edge (stop) and never reach them - reachable
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
          ClipRect(
            child: AnimatedSize(
              duration: _expandDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerRight,
              child: _expanded
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final action in widget.actions)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: AppIconButton(
                              icon: action.icon,
                              tooltip: action.label,
                              variant: action.isDanger
                                  ? AppButtonVariant.destructive
                                  : AppButtonVariant.tonal,
                              onPressed: () {
                                _collapse();
                                action.onPressed();
                              },
                            ),
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          AppIconButton(
            autofocus: widget.autofocus,
            icon: _expanded ? Icons.close : Icons.more_vert,
            tooltip: widget.moreLabel,
            onPressed: _toggleExpanded,
          ),
        ],
      ),
    );
  }
}
