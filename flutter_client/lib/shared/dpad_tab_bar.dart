import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// A [TabBar] replacement that integrates with the D-pad focus system.
///
/// Unlike Material's [TabBar], each tab uses [DpadFocusable] so:
/// - Hover and D-pad focus show the same background tint (no border effect).
/// - A mouse click transfers keyboard focus to the clicked tab.
class DpadTabBar extends StatefulWidget {
  const DpadTabBar({
    super.key,
    required this.controller,
    required this.tabs,
  });

  final TabController controller;
  final List<String> tabs;

  @override
  State<DpadTabBar> createState() => DpadTabBarState();
}

/// Public so callers holding a `GlobalKey<DpadTabBarState>` can pull d-pad
/// focus onto the selected tab directly via [requestFocus].
///
/// Needed when content below the bar sits inside its own [FocusScope] (e.g.
/// `MediaCategoryNav`'s sidebar strip). Plain directional traversal can
/// never cross that boundary since `dpad`'s traversal policy bounds
/// candidates to the current [FocusScopeNode]'s own descendants, so a
/// screen combining both must reach up here with an explicit
/// [FocusNode.requestFocus] instead of relying on Up-arrow traversal.
class DpadTabBarState extends State<DpadTabBar> {
  List<FocusNode> _focusNodes = const [];

  @override
  void initState() {
    super.initState();
    _focusNodes = _createFocusNodes();
  }

  @override
  void didUpdateWidget(DpadTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tabs.length != oldWidget.tabs.length) {
      for (final node in _focusNodes) {
        node.dispose();
      }
      _focusNodes = _createFocusNodes();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  List<FocusNode> _createFocusNodes() => [
    for (int i = 0; i < widget.tabs.length; i++)
      FocusNode(debugLabel: 'DpadTabBar tab $i'),
  ];

  /// Focuses the currently selected tab.
  void requestFocus() {
    final index = widget.controller.index;
    if (index >= 0 && index < _focusNodes.length) {
      _focusNodes[index].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (int i = 0; i < widget.tabs.length; i++)
                Expanded(
                  child: _DpadTab(
                    focusNode: _focusNodes[i],
                    label: widget.tabs[i],
                    isSelected: widget.controller.index == i,
                    onTap: () => widget.controller.animateTo(i),
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

/// A [TabBarView] that disables swipe-to-switch on desktop.
///
/// On desktop, a click-drag that starts on a right-aligned action button
/// (e.g. a row action on the DVR Recordings screen) is picked up by
/// [TabBarView]'s default [PageView] physics as a horizontal drag, so the
/// page nudges left and snaps back before the click registers. Desktop
/// users switch tabs by clicking [DpadTabBar] directly, so swipe gains
/// nothing there. Touch and D-pad/TV navigation are unaffected — TV never
/// drives this via mouse drag, and touch swipe is a primary affordance on
/// mobile.
class DpadTabBarView extends StatelessWidget {
  const DpadTabBarView({
    super.key,
    required this.controller,
    required this.children,
  });

  final TabController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: controller,
      physics: isDesktopPlatform(context)
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      children: children,
    );
  }
}

/// True for mouse-and-keyboard desktop windows (Linux/macOS/Windows, not
/// tvOS and not directional/D-pad navigation mode). Kept local rather than
/// reusing `device_type_resolver.dart`'s `DeviceType` to avoid importing
/// `app_shell.dart` transitively — the same import-cycle concern documented
/// on `_useInlineRowActions` in `dvr_recordings_screen.dart`.
bool isDesktopPlatform(BuildContext context) {
  if (HostPlatform.isTvOS) return false;
  if (MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional) {
    return false;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}

class _DpadTab extends StatefulWidget {
  const _DpadTab({
    required this.focusNode,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final FocusNode focusNode;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_DpadTab> createState() => _DpadTabState();
}

class _DpadTabState extends State<_DpadTab> {
  bool _hovered = false;

  void _onTap() {
    widget.focusNode.requestFocus();
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
        focusNode: widget.focusNode,
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
