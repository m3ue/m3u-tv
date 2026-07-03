import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

/// A [TabBar] replacement that integrates with the D-pad focus system.
///
/// Unlike Material's [TabBar], each tab uses [DpadFocusable] so:
/// - Hover and D-pad focus show the same background tint (no border effect).
/// - A mouse click transfers keyboard focus to the clicked tab.
class DpadTabBar extends StatelessWidget {
  const DpadTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<String> tabs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < tabs.length; i++)
                Expanded(
                  child: _DpadTab(
                    label: tabs[i],
                    isSelected: controller.index == i,
                    onTap: () => controller.animateTo(i),
                  ),
                ),
            ],
          ),
          Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
        ],
      ),
    );
  }
}

class _DpadTab extends StatefulWidget {
  const _DpadTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_DpadTab> createState() => _DpadTabState();
}

class _DpadTabState extends State<_DpadTab> {
  final _focusNode = FocusNode();
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onTap() {
    _focusNode.requestFocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelColor = widget.isSelected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: DpadFocusable(
        focusNode: _focusNode,
        onSelect: _onTap,
        builder: (context, state, child) {
          final highlighted = state.focused || _hovered || state.pressed;
          return Material(
            color: highlighted
                ? colorScheme.onSurface.withValues(alpha: 0.04)
                : Colors.transparent,
            child: InkWell(
              onTap: _onTap,
              // Suppress InkWell's own overlay — background color is handled above.
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              child: child,
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Text(
                widget.label,
                style: theme.textTheme.titleSmall?.copyWith(color: labelColor),
              ),
            ),
            Container(
              height: 3,
              color: widget.isSelected
                  ? colorScheme.primary
                  : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
