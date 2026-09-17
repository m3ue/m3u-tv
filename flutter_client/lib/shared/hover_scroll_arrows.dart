import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/dpad_tab_bar.dart' show isDesktopPlatform;

/// Wraps a horizontally-scrolling child with hover-activated left / right
/// navigation arrows for mouse users.
///
/// The detail screens' episode + cast strips hide the scrollbar (it reacts to
/// every scroll-position change and races a semantics assertion under D-pad
/// key-repeat on TV), which left desktop mouse users with only shift + wheel.
/// These arrows restore a discoverable affordance. Modelled on Plezy's
/// `HorizontalScrollWithArrows`.
///
/// Off desktop (TV / phone) the [child] passes straight through with no
/// `MouseRegion` / `Stack` overhead - D-pad and touch drive the scroll there.
class HoverScrollArrows extends StatefulWidget {
  const HoverScrollArrows({
    super.key,
    required this.controller,
    required this.child,
    this.viewportFraction = 0.8,
  });

  /// Must be the SAME controller the wrapped scrollable is driven by.
  final ScrollController controller;

  final Widget child;

  /// How far one arrow press travels, as a fraction of the viewport width.
  final double viewportFraction;

  @override
  State<HoverScrollArrows> createState() => _HoverScrollArrowsState();
}

class _HoverScrollArrowsState extends State<HoverScrollArrows> {
  bool _hovering = false;
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
  }

  @override
  void didUpdateWidget(HoverScrollArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncEdges);
      widget.controller.addListener(_syncEdges);
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncEdges());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncEdges);
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted) return;
    var canLeft = false;
    var canRight = false;
    if (widget.controller.positions.length == 1) {
      final position = widget.controller.position;
      if (position.hasContentDimensions &&
          position.hasPixels &&
          position.maxScrollExtent > 0) {
        canLeft = position.pixels > 0.5;
        canRight = position.pixels < position.maxScrollExtent - 0.5;
      }
    }
    if (canLeft != _canLeft || canRight != _canRight) {
      setState(() {
        _canLeft = canLeft;
        _canRight = canRight;
      });
    }
  }

  void _nudge(int direction) {
    if (widget.controller.positions.length != 1) return;
    final position = widget.controller.position;
    final target =
        (position.pixels +
                direction *
                    position.viewportDimension *
                    widget.viewportFraction)
            .clamp(0.0, position.maxScrollExtent);
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopPlatform(context)) return widget.child;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _syncEdges();
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            _EdgeArrow(
              alignment: Alignment.centerLeft,
              icon: Icons.chevron_left,
              visible: _hovering && _canLeft,
              onTap: () => _nudge(-1),
            ),
            _EdgeArrow(
              alignment: Alignment.centerRight,
              icon: Icons.chevron_right,
              visible: _hovering && _canRight,
              onTap: () => _nudge(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _EdgeArrow extends StatelessWidget {
  const _EdgeArrow({
    required this.alignment,
    required this.icon,
    required this.visible,
    required this.onTap,
  });

  final Alignment alignment;
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            child: IgnorePointer(
              ignoring: !visible,
              child: Material(
                color: scheme.surface.withValues(alpha: 0.92),
                shape: const CircleBorder(),
                elevation: 4,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(icon, size: 28, color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
