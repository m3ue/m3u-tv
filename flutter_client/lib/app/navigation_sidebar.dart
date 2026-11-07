import 'package:dpad/dpad.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Sidebar navigation for TV/desktop. Shows a vertical list of destinations
/// with focus support and D-pad traversal.
class NavigationSidebar extends StatelessWidget {
  const NavigationSidebar({
    super.key,
    required this.currentIndex,
    required this.routes,
    required this.sidebarActive,
    required this.focusNodes,
    required this.scopeNode,
    this.unreadNotificationCount = 0,
    required this.onNavigate,
    required this.onActivateSidebar,
    required this.onDeactivateSidebar,
  });

  final int currentIndex;
  final List<String> routes;
  final bool sidebarActive;
  final List<FocusNode> focusNodes;
  final FocusScopeNode scopeNode;
  final int unreadNotificationCount;
  final ValueChanged<int> onNavigate;
  final VoidCallback onActivateSidebar;
  final VoidCallback onDeactivateSidebar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = sidebarActive;
    final scale = FontSizeScope.scaleOf(context);
    final width = (expanded ? 200.0 : kSidebarRailInset) * scale;

    return MouseRegion(
      onEnter: (_) => onActivateSidebar(),
      onExit: (_) => onDeactivateSidebar(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: width,
        clipBehavior: Clip.hardEdge,
        // Expanded: a card-coloured panel with a hairline edge and a soft,
        // wide shadow over the content. Collapsed: no panel, no edge.
        decoration: BoxDecoration(
          color: expanded
              ? theme.colorScheme.surfaceContainerLow
              : Colors.transparent,
          border: Border(
            right: BorderSide(
              color: expanded
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
                  : Colors.transparent,
            ),
          ),
          boxShadow: expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 32,
                    offset: const Offset(8, 0),
                  ),
                ]
              : null,
        ),
        child: FocusScope(
          node: scopeNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              onDeactivateSidebar();
              return KeyEventResult.handled;
            }
            return _handleVerticalKey(event);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 72 * scale,
                child: Padding(
                  // Horizontal (14) scales to keep the logo centered in
                  // the collapsed rail, matching how SidebarDestinationItem
                  // centers its icons (outer + inner padding + icon size
                  // summing symmetrically around the rail's midpoint) - at
                  // scale 1, 64 (kSidebarRailInset) - 14 - 36 (logo width)
                  // = 14, so left inset equals right space. Leaving this
                  // unscaled while the logo itself scaled was the bug: the
                  // logo drifted off-center as scale grew.
                  padding: EdgeInsets.fromLTRB(14 * scale, 20, 14 * scale, 16),
                  child: OverflowBox(
                    maxWidth: 200 * scale,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/logo.svg',
                          width: 36 * scale,
                          height: 36 * scale,
                        ),
                        if (expanded) ...[
                          const SizedBox(width: 12),
                          Text(
                            'M3U TV',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _SidebarScrollArea(
                  children: [
                    const SizedBox(height: 12),
                    for (var index = 0; index < footerStart; index++)
                      _destination(context, index, expanded, scale),
                  ],
                ),
              ),
              // A hairline sets Notifications and Settings apart from
              // the content destinations.
              if (footerStart < routes.length)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * scale,
                    vertical: 6 * scale,
                  ),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                  ),
                ),
              for (var index = footerStart; index < routes.length; index++)
                _destination(context, index, expanded, scale),
            ],
          ),
        ),
      ),
    );
  }

  /// Up/Down step through the list by index. dpad's traversal goes by where
  /// things are on screen, and a destination scrolled out of view still has a
  /// position - behind the logo or the pinned footer - so it would pick those
  /// hidden items over the visible neighbor.
  KeyEventResult _handleVerticalKey(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (step == 0) return KeyEventResult.ignored;
    final current = focusNodes.indexWhere((node) => node.hasPrimaryFocus);
    if (current == -1) return KeyEventResult.ignored;
    final next = current + step;
    if (next >= 0 && next < routes.length) focusNodes[next].requestFocus();
    return KeyEventResult.handled;
  }

  /// Index of the first trailing Notifications/Settings destination, which
  /// sit below a divider; the length of [routes] when there are none.
  int get footerStart {
    var start = routes.length;
    while (start > 0 &&
        (routes[start - 1] == RouteNames.settings ||
            routes[start - 1] == RouteNames.notifications)) {
      start--;
    }
    return start;
  }

  Widget _destination(
    BuildContext context,
    int index,
    bool expanded,
    double scale,
  ) {
    final route = routes[index];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
      child: SidebarDestinationItem(
        // Keyed by route: gated destinations (DVR, Requests, ...) appear
        // after the first build, and without a key Flutter would hand an
        // existing item's state (and its focus listener) to a different
        // destination.
        key: ValueKey(route),
        label: navigationRouteLabel(context, route),
        icon: navigationRouteIcon(route),
        selected: index == currentIndex,
        expanded: expanded,
        focusNode: focusNodes[index],
        badgeCount: route == RouteNames.notifications
            ? unreadNotificationCount
            : 0,
        onTap: () => onNavigate(index),
      ),
    );
  }
}

/// The destinations that scroll between the pinned logo and footer, with a
/// soft shadow on each edge that has more above or below it.
class _SidebarScrollArea extends StatefulWidget {
  const _SidebarScrollArea({required this.children});

  final List<Widget> children;

  @override
  State<_SidebarScrollArea> createState() => _SidebarScrollAreaState();
}

class _SidebarScrollAreaState extends State<_SidebarScrollArea> {
  final ScrollController _controller = ScrollController();
  bool _moreAbove = false;
  bool _moreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncEdges);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    final moreAbove = position.extentBefore > 0;
    final moreBelow = position.extentAfter > 0;
    if (moreAbove == _moreAbove && moreBelow == _moreBelow) return;
    setState(() {
      _moreAbove = moreAbove;
      _moreBelow = moreBelow;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shadowHeight = 20 * FontSizeScope.scaleOf(context);
    // Also fires on first layout and when the list or the screen resizes,
    // which a scroll listener alone would miss.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        _syncEdges();
        return false;
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: shadowHeight,
            child: _SidebarEdgeShadow(
              visible: _moreAbove,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: shadowHeight,
            child: _SidebarEdgeShadow(
              visible: _moreBelow,
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarEdgeShadow extends StatelessWidget {
  const _SidebarEdgeShadow({
    required this.visible,
    required this.begin,
    required this.end,
  });

  final bool visible;
  final Alignment begin;
  final Alignment end;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [
                Colors.black.withValues(alpha: 0.4),
                Colors.black.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single sidebar destination item with focus highlight.
class SidebarDestinationItem extends StatefulWidget {
  const SidebarDestinationItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.focusNode,
    required this.onTap,
    this.expanded = true,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;

  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool expanded;
  final int badgeCount;

  @override
  State<SidebarDestinationItem> createState() => _SidebarDestinationItemState();
}

class _SidebarDestinationItemState extends State<SidebarDestinationItem> {
  bool _focused = false;
  bool _hovered = false;
  // Timestamp debounce: prevents double-fire when a platform (e.g. tvOS Siri
  // Remote, desktop Enter key) generates both a KeyDownEvent (onKeyEvent) AND
  // a synthesized pointer tap (InkWell.onTap) for the same physical press.
  // Order-independent: works whether key arrives before or after pointer.
  int _lastActivationMs = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    if (widget.selected) _scheduleReveal();
  }

  @override
  void didUpdateWidget(SidebarDestinationItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _focused = widget.focusNode.hasFocus;
    }
    if (widget.selected && !oldWidget.selected) _scheduleReveal();
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _focused = widget.focusNode.hasFocus;
    });
    if (_focused) _scheduleReveal();
  }

  /// Keeps this item, and enough room for the next one to show, on screen.
  /// Covers every way here: Up/Down, the sidebar opening on the current
  /// destination, and navigating from elsewhere with the rail collapsed.
  /// Instant, like the app's other D-pad scrolling (see main.dart's Dpad
  /// theme).
  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DpadScroll.ensureVisible(
        widget.focusNode,
        padding: 56 * FontSizeScope.scaleOf(context),
        duration: Duration.zero,
      );
    });
  }

  void _setHovered(bool v) {
    if (_hovered == v) return;
    setState(() => _hovered = v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Current destination: brand colour on a soft neutral tint, with the
    // brand gradient as a short bar on the leading edge (as in the editor's
    // sidebar). Idle destinations are muted; focus and hover lift them to
    // full strength on the same neutral tint.
    final activeColor = colorScheme.primary;
    final Color backgroundColor;
    final Color foregroundColor;
    if (widget.selected) {
      backgroundColor = colorScheme.onSurface.withValues(alpha: 0.08);
      foregroundColor = activeColor;
    } else if (_focused || _hovered) {
      backgroundColor = colorScheme.onSurface.withValues(alpha: 0.06);
      foregroundColor = colorScheme.onSurface;
    } else {
      backgroundColor = colorScheme.onSurface.withValues(alpha: 0);
      foregroundColor = colorScheme.onSurface.withValues(alpha: 0.68);
    }

    final scale = FontSizeScope.scaleOf(context);
    final hPad = 12.0 * scale;
    final itemHeight = 48.0 * scale;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Focus(
        focusNode: widget.focusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.select ||
              event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastActivationMs < 350) return KeyEventResult.handled;
            _lastActivationMs = now;
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: InkWell(
          onTap: () {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastActivationMs < 350) return;
            _lastActivationMs = now;
            widget.focusNode.requestFocus();
            widget.onTap();
          },
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: itemHeight,
                padding: EdgeInsets.symmetric(horizontal: hPad),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: OverflowBox(
                  maxWidth: 200 * scale,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Badge(
                        isLabelVisible: widget.badgeCount > 0,
                        label: Text('${widget.badgeCount}'),
                        child: Icon(
                          widget.icon,
                          color: foregroundColor,
                          size: 24 * scale,
                        ),
                      ),
                      if (widget.expanded) ...[
                        SizedBox(width: hPad),
                        Flexible(
                          child: Text(
                            widget.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foregroundColor,
                              fontWeight: widget.selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: itemHeight * 0.28,
                bottom: itemHeight * 0.28,
                width: 3,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: widget.selected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [colorScheme.secondary, colorScheme.primary],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // D-pad/keyboard focus ring, also on the current destination
              // so focus stays visible when it lands there. Mouse hover only
              // gets the tint: on desktop the pointer can rest over one item
              // while the keyboard moves focus to another, and two rings would
              // make it unclear which one is focused.
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _focused ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    child: CustomPaint(
                      painter: GradientBorderPainter(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(8),
                        ),
                        width: 2.5,
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [
                            colorScheme.primary,
                            colorScheme.secondary,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData navigationRouteIcon(String route) => switch (route) {
  RouteNames.home => Icons.home_rounded,
  RouteNames.search => Icons.search_rounded,
  RouteNames.liveTv => Icons.live_tv_rounded,
  RouteNames.sports => Icons.stadium_rounded,
  RouteNames.vod => Icons.movie_rounded,
  RouteNames.series => Icons.tv_rounded,
  RouteNames.aiostreams => Icons.subscriptions_rounded,
  RouteNames.dvr => Icons.video_library_rounded,
  RouteNames.requests => Icons.playlist_add_rounded,
  RouteNames.notifications => Icons.notifications_rounded,
  RouteNames.settings => Icons.settings_rounded,
  _ => Icons.circle,
};

String navigationRouteLabel(BuildContext context, String route) {
  final l = AppLocalizations.of(context);
  return switch (route) {
    RouteNames.home => l.navHome,
    RouteNames.search => l.navSearch,
    RouteNames.liveTv => l.navLiveTv,
    RouteNames.sports => l.navSports,
    RouteNames.vod => l.navVod,
    RouteNames.series => l.navSeries,
    RouteNames.aiostreams => l.navAioStreams,
    RouteNames.dvr => l.navDvr,
    RouteNames.requests => l.navRequests,
    RouteNames.notifications => l.navNotifications,
    RouteNames.settings => l.navSettings,
    _ => RouteNames.routeLabels[route] ?? route,
  };
}
