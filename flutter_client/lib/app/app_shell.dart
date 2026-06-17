import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/player/resume_modal.dart';
import 'package:m3u_tv/features/search/search_screen.dart';
import 'package:m3u_tv/features/series/series_screen.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Device type enum matching the RN useDeviceType hook.
enum DeviceType { tv, desktop, tablet, phone }

/// Whether a device type should use sidebar navigation.
bool shouldUseSidebar(DeviceType deviceType) =>
    deviceType == DeviceType.tv || deviceType == DeviceType.desktop;

/// Root shell with adaptive scaffold: sidebar for TV/desktop, bottom nav for
/// phone/tablet. Includes TV focus traversal, D-pad/keyboard shortcuts, back
/// handling, and focus restoration.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.deviceType,
    this.appState,
    this.playbackOrchestratorBuilder,
    this.playerRouteBuilder,
  });

  final DeviceType deviceType;
  final AppStateController? appState;
  final PlaybackOrchestrator Function()? playbackOrchestratorBuilder;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _sidebarActive = false;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppStateController _appState;
  late final bool _ownsAppState;

  DateTime? _lastBackPress;

  PlayerArgs? _playerArgs;
  PlaybackOrchestrator? _playerOrchestrator;
  FocusNode? _focusBeforePlayer;

  // Focus nodes for sidebar items
  final List<FocusNode> _sidebarFocusNodes = [];
  final FocusScopeNode _contentFocusNode = FocusScopeNode();
  final FocusScopeNode _sidebarScopeNode = FocusScopeNode();

  List<String> get _mainRoutes => RouteNames.mainRoutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appState = widget.appState ?? AppStateController();
    _ownsAppState = widget.appState == null;
    _appState.addListener(_onAppStateChanged);
    if (!_appState.isConfigured) {
      unawaited(_appState.boot());
    }
    _initSidebarFocusNodes();
  }

  @override
  Future<bool> didPopRoute() async {
    if (_handleBackPress()) return true;

    // Double-back to exit: require two back presses within 2 seconds.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return false; // Let Android exit the app.
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _initSidebarFocusNodes() {
    for (var i = 0; i < _mainRoutes.length; i++) {
      _sidebarFocusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerOrchestrator?.dispose().ignore();
    for (final node in _sidebarFocusNodes) {
      node.dispose();
    }
    _contentFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _appState.removeListener(_onAppStateChanged);
    if (_ownsAppState) _appState.dispose();
    super.dispose();
  }

  void _navigateTo(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    unawaited(
      _navigatorKey.currentState?.pushReplacementNamed(_mainRoutes[index]),
    );
    // On TV, navigating from sidebar collapses it
    if (shouldUseSidebar(widget.deviceType)) {
      _sidebarActive = false;
      // Move focus to content after navigation
      unawaited(
        Future.microtask(() {
          if (mounted) _contentFocusNode.requestFocus();
        }),
      );
    }
  }

  void _activateSidebar() {
    setState(() {
      _sidebarActive = true;
    });
    // Focus the current sidebar item
    if (_sidebarFocusNodes.isNotEmpty) {
      final node =
          _sidebarFocusNodes[_currentIndex.clamp(
            0,
            _sidebarFocusNodes.length - 1,
          )];
      unawaited(
        Future.microtask(() {
          if (mounted) node.requestFocus();
        }),
      );
    }
  }

  void _deactivateSidebar() {
    setState(() {
      _sidebarActive = false;
    });
    unawaited(
      Future.microtask(() {
        if (mounted) _contentFocusNode.requestFocus();
      }),
    );
  }

  Future<void> _openPlayer(BuildContext context, PlayerArgs args) async {
    var resolvedArgs = args;
    if (resolvedArgs.type != 'live' &&
        resolvedArgs.startPosition == null &&
        resolvedArgs.streamId != null) {
      final target = resolvedArgs.type == 'series'
          ? ContentType.episode
          : ContentType.vod;
      final progress = _appState.progressList.firstWhereOrNull(
        (p) =>
            p.streamId == resolvedArgs.streamId &&
            p.contentType == target &&
            p.positionSeconds >= 30 &&
            !p.completed,
      );
      if (progress != null && context.mounted) {
        final startPos = await showResumeModal(
          context,
          title: resolvedArgs.title,
          positionSeconds: progress.positionSeconds,
        );
        if (startPos == null) return;
        if (startPos > 0) {
          resolvedArgs = resolvedArgs.copyWith(startPosition: startPos);
        }
      }
    }
    _openPlayerDirect(resolvedArgs);
  }

  void _openPlayerDirect(PlayerArgs args) {
    final oldOrch = _playerOrchestrator;
    final newOrch =
        widget.playbackOrchestratorBuilder?.call() ??
        buildPlaybackOrchestrator();
    // Save the focused node so we can restore it precisely after the player
    // closes. _contentFocusNode.requestFocus() alone is unreliable: when
    // PlayerScreen disposes _screenFocusNode, Flutter's _willDisposeFocusNode
    // calls requestFocusWithin() on the root scope, which finds the FIRST
    // focusable in the tree (often the initial route, not the current one)
    // and corrupts _contentFocusNode._focusedChild before our postFrameCallback
    // gets a chance to run.
    final focus = FocusManager.instance.primaryFocus;
    _focusBeforePlayer = _isInContentScope(focus) ? focus : null;
    setState(() {
      _playerArgs = args;
      _playerOrchestrator = newOrch;
    });
    // Dispose old orchestrator after the frame so it can finish stopping.
    if (oldOrch != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => oldOrch.dispose().ignore(),
      );
    }
  }

  bool _isInContentScope(FocusNode? node) {
    var current = node;
    while (current != null) {
      if (current == _contentFocusNode) return true;
      current = current.parent;
    }
    return false;
  }

  void _closePlayer() {
    final orch = _playerOrchestrator;
    final savedFocus = _focusBeforePlayer;
    _focusBeforePlayer = null;
    setState(() {
      _playerArgs = null;
      _playerOrchestrator = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      orch?.dispose().ignore();
      if (!mounted) return;
      // Restore to the exact node that had focus before the player opened.
      // If that node is gone, fall back to the content scope (which uses
      // whatever _focusedChild it still has).
      if (savedFocus != null && savedFocus.canRequestFocus) {
        savedFocus.requestFocus();
      } else {
        _contentFocusNode.requestFocus();
      }
    });
  }

  bool _handleBackPress() {
    if (_playerArgs != null) {
      _closePlayer();
      return true;
    }

    final nav = _navigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }

    // On TV/desktop: if content is focused, activate sidebar
    if (shouldUseSidebar(widget.deviceType) && !_sidebarActive) {
      _activateSidebar();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final useSidebar = shouldUseSidebar(widget.deviceType);

    void openPlayer(PlayerArgs args) => unawaited(_openPlayer(context, args));

    final shell = Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.contextMenu): const _MenuIntent(),
        LogicalKeySet(LogicalKeyboardKey.f1): const _MenuIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _BackIntent: _BackAction(_handleBackPress),
          _MenuIntent: _MenuAction(_activateSidebar),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            // Only intercept left arrow when content scope has no focused
            // descendant (empty/unconfigured state). When content has focus,
            // let dpad handle traversal via its Shortcuts before we intercept.
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                useSidebar &&
                !_contentFocusNode.hasFocus) {
              _activateSidebar();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: useSidebar
              ? _buildTvLayout(openPlayer)
              : _buildMobileLayout(openPlayer),
        ),
      ),
    );

    final args = _playerArgs;
    final orch = _playerOrchestrator;
    if (args == null || orch == null) return shell;

    final viewerId = _appState.activeViewer?.ulid ?? '';

    return Stack(
      children: [
        shell,
        Positioned.fill(
          child:
              widget.playerRouteBuilder?.call(args) ??
              PlayerScreen(
                key: ValueKey(args.streamUrl),
                args: args,
                orchestrator: orch,
                epgService: _appState.epgService,
                xtreamService: _appState.xtreamService,
                viewerId: viewerId,
                progressReporter: (progress) {
                  if (_appState.sourceType == AppSourceType.xtream) {
                    unawaited(
                      _appState.xtreamService
                          .updateProgress(progress)
                          .catchError((_) {}),
                    );
                  }
                  unawaited(
                    _appState.resumeService.save(progress).then((_) {
                      if (mounted) unawaited(_appState.refreshLocalState());
                    }),
                  );
                },
                onClose: _closePlayer,
              ),
        ),
      ],
    );
  }

  Widget _buildTvLayout(void Function(PlayerArgs) openPlayer) {
    return MediaQuery.removePadding(
      // Strip all system safe-area insets for the TV layout. On tvOS, the
      // system reports status-bar / overscan padding that would otherwise make
      // Scaffold AppBars taller and push body content down unnecessarily.
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 240 || constraints.maxHeight < 120) {
            return Scaffold(
              body: FocusScope(
                node: _contentFocusNode,
                child: _ContentNavigator(
                  navigatorKey: _navigatorKey,
                  currentIndex: _currentIndex,
                  appState: _appState,
                  onConnected: () => _navigateTo(0),
                  onOpenPlayer: openPlayer,
                  playbackOrchestratorBuilder:
                      widget.playbackOrchestratorBuilder,
                  playerRouteBuilder: widget.playerRouteBuilder,
                ),
              ),
            );
          }

          return Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 64),
                    child: DpadRegion(
                      memoryKey: 'content',
                      horizontalEdge: DpadEdgeBehavior.stop,
                      onEdge: (direction) {
                        if (direction == TraversalDirection.left) {
                          _activateSidebar();
                        }
                      },
                      child: FocusScope(
                        node: _contentFocusNode,
                        child: _ContentNavigator(
                          navigatorKey: _navigatorKey,
                          currentIndex: _currentIndex,
                          appState: _appState,
                          onSidebarActivate: _activateSidebar,
                          onConnected: () => _navigateTo(0),
                          onOpenPlayer: openPlayer,
                          playbackOrchestratorBuilder:
                              widget.playbackOrchestratorBuilder,
                          playerRouteBuilder: widget.playerRouteBuilder,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  child: NavigationSidebar(
                    currentIndex: _currentIndex,
                    sidebarActive: _sidebarActive,
                    focusNodes: _sidebarFocusNodes,
                    scopeNode: _sidebarScopeNode,
                    onNavigate: _navigateTo,
                    onActivateSidebar: _activateSidebar,
                    onDeactivateSidebar: _deactivateSidebar,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout(void Function(PlayerArgs) openPlayer) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _ContentNavigator(
          navigatorKey: _navigatorKey,
          currentIndex: _currentIndex,
          appState: _appState,
          onConnected: () => _navigateTo(0),
          onOpenPlayer: openPlayer,
          playbackOrchestratorBuilder: widget.playbackOrchestratorBuilder,
          playerRouteBuilder: widget.playerRouteBuilder,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _navigateTo,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        items: _mainRoutes.map((route) {
          final label = RouteNames.routeLabels[route] ?? route;
          return BottomNavigationBarItem(
            icon: Icon(_routeIcon(route)),
            label: label,
          );
        }).toList(),
      ),
    );
  }

  IconData _routeIcon(String route) => switch (route) {
    RouteNames.home => Icons.home,
    RouteNames.search => Icons.search,
    RouteNames.liveTv => Icons.live_tv,
    RouteNames.vod => Icons.movie,
    RouteNames.series => Icons.tv,
    RouteNames.settings => Icons.settings,
    _ => Icons.circle,
  };
}

/// Sidebar navigation for TV/desktop. Shows a vertical list of destinations
/// with focus support and D-pad traversal.
class NavigationSidebar extends StatelessWidget {
  const NavigationSidebar({
    super.key,
    required this.currentIndex,
    required this.sidebarActive,
    required this.focusNodes,
    required this.scopeNode,
    required this.onNavigate,
    required this.onActivateSidebar,
    required this.onDeactivateSidebar,
  });

  final int currentIndex;
  final bool sidebarActive;
  final List<FocusNode> focusNodes;
  final FocusScopeNode scopeNode;
  final ValueChanged<int> onNavigate;
  final VoidCallback onActivateSidebar;
  final VoidCallback onDeactivateSidebar;

  @override
  Widget build(BuildContext context) {
    const routes = RouteNames.mainRoutes;
    final theme = Theme.of(context);
    final expanded = sidebarActive;
    final width = expanded ? 200.0 : 64.0;

    return MouseRegion(
      onEnter: (_) => onActivateSidebar(),
      onExit: (_) => onDeactivateSidebar(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: width,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(2, 0),
            ),
          ],
        ),
        child: FocusScope(
          node: scopeNode,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              onDeactivateSidebar();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo header
              SizedBox(
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
                  child: OverflowBox(
                    maxWidth: 200,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/icons/logo.svg',
                          width: 36,
                          height: 36,
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
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 8),
              // Nav items
              ...List.generate(routes.length, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: SidebarDestinationItem(
                    label:
                        RouteNames.routeLabels[routes[index]] ?? routes[index],
                    icon: _routeIcon(routes[index]),
                    selected: index == currentIndex,
                    expanded: expanded,
                    focusNode: focusNodes[index],
                    onTap: () => onNavigate(index),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  IconData _routeIcon(String route) => switch (route) {
    RouteNames.home => Icons.home,
    RouteNames.search => Icons.search,
    RouteNames.liveTv => Icons.live_tv,
    RouteNames.vod => Icons.movie,
    RouteNames.series => Icons.tv,
    RouteNames.settings => Icons.settings,
    _ => Icons.circle,
  };
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
  });

  final String label;
  final IconData icon;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final bool expanded;

  @override
  State<SidebarDestinationItem> createState() => _SidebarDestinationItemState();
}

class _SidebarDestinationItemState extends State<SidebarDestinationItem> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? backgroundColor;
    Color? foregroundColor;
    if (widget.selected) {
      backgroundColor = colorScheme.primaryContainer;
      foregroundColor = colorScheme.onPrimaryContainer;
    } else if (_focused) {
      backgroundColor = colorScheme.surfaceContainerHigh;
      foregroundColor = colorScheme.onSurface;
    }

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.select ||
            event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: InkWell(
        onTap: widget.onTap,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            border: _focused && !widget.selected
                ? Border.all(color: colorScheme.primary, width: 2)
                : null,
          ),
          child: OverflowBox(
            maxWidth: 200,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, color: foregroundColor, size: 24),
                if (widget.expanded) ...[
                  const SizedBox(width: 12),
                  Text(
                    widget.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foregroundColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Content area navigator that shows the current main route.
class _ContentNavigator extends StatelessWidget {
  const _ContentNavigator({
    required this.navigatorKey,
    required this.currentIndex,
    required this.appState,
    this.onSidebarActivate,
    this.onConnected,
    this.onOpenPlayer,
    this.playbackOrchestratorBuilder,
    this.playerRouteBuilder,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final int currentIndex;
  final AppStateController appState;
  final VoidCallback? onSidebarActivate;
  final VoidCallback? onConnected;
  final void Function(PlayerArgs args)? onOpenPlayer;
  final PlaybackOrchestrator Function()? playbackOrchestratorBuilder;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;

  @override
  Widget build(BuildContext context) {
    const routes = RouteNames.mainRoutes;
    final currentRoute = routes[currentIndex];
    final router = buildAppRouter(
      mainRouteBuilder: _buildMainRoute,
      xtreamService: appState.xtreamService,
      epgService: appState.epgService,
      playbackOrchestratorBuilder: playbackOrchestratorBuilder,
      playerRouteBuilder: playerRouteBuilder,
      onOpenPlayer: onOpenPlayer,
      progressList: appState.progressList,
    );

    return Navigator(
      key: navigatorKey,
      onGenerateRoute: router,
      initialRoute: currentRoute,
    );
  }

  void _openChannel(Channel channel) {
    onOpenPlayer?.call(
      PlayerArgs(
        streamUrl: channel.streamUrl,
        title: channel.name,
        type: 'live',
        streamId: channel.id,
        epgChannelId: channel.epgChannelId ?? channel.tvgName ?? channel.name,
        headers: channel.headers,
      ),
    );
  }

  void _openVod(VodItem item, {double? startPosition}) {
    if (startPosition == null) {
      unawaited(
        navigatorKey.currentState?.pushNamed(
          RouteNames.details,
          arguments: DetailsArgs(
            vodId: item.id,
            vodName: item.name,
            item: item,
          ),
        ),
      );
      return;
    }

    _playVod(item, startPosition: startPosition);
  }

  void _playVod(VodItem item, {double? startPosition}) {
    onOpenPlayer?.call(
      PlayerArgs(
        streamUrl: item.streamUrl,
        title: item.name,
        type: 'vod',
        streamId: item.id,
        startPosition: startPosition,
        metadata: <String, Object?>{
          'container_extension': item.containerExtension,
        },
      ),
    );
  }

  void _openProgress(Progress progress) {
    if (progress.contentType == ContentType.vod) {
      final item = appState.vodItems.firstWhereOrNull(
        (item) => item.id == progress.streamId,
      );
      if (item != null) {
        // Pass no startPosition — the pre-player resume modal will handle it.
        _playVod(item);
      }
      return;
    }

    if (progress.contentType == ContentType.episode &&
        progress.seriesId != null) {
      final series = appState.seriesList.firstWhereOrNull(
        (s) => s.id == progress.seriesId,
      );
      if (series != null) {
        final streamUrl = appState.xtreamService.getSeriesStreamUrl(
          progress.streamId.toString(),
        );
        onOpenPlayer?.call(
          PlayerArgs(
            streamUrl: streamUrl,
            title: series.name,
            type: 'series',
            streamId: progress.streamId,
            seriesId: progress.seriesId,
            seasonNumber: progress.seasonNumber,
          ),
        );
      }
    }
  }

  void _openSeries(Series series) {
    unawaited(
      navigatorKey.currentState?.pushNamed(
        RouteNames.seriesDetails,
        arguments: SeriesDetailsArgs(
          seriesId: series.id,
          seriesName: series.name,
        ),
      ),
    );
  }

  Widget _buildMainRoute(String routeName) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.isBootstrapping) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return switch (routeName) {
          RouteNames.home => _HomeScreen(
            appState: appState,
            onChannelSelect: _openChannel,
            onVodSelect: _openVod,
            onSeriesSelect: _openSeries,
            onProgressSelect: _openProgress,
            onSidebarActivate: onSidebarActivate,
          ),
          RouteNames.search => SearchScreen(
            channels: appState.channels,
            vodItems: appState.vodItems,
            seriesList: appState.seriesList,
            isConfigured: appState.isConfigured,
            onChannelSelect: _openChannel,
            onVodSelect: _openVod,
            onSeriesSelect: _openSeries,
            onSidebarActivate: onSidebarActivate,
          ),
          RouteNames.liveTv => LiveTvScreen(
            channels: appState.channels,
            categories: appState.liveCategories,
            isLoading: appState.isLoadingContent,
            isConfigured: appState.isConfigured,
            favoritesService: appState.favoritesService,
            epgService: appState.epgService,
            onChannelSelect: _openChannel,
            onSidebarActivate: onSidebarActivate,
          ),
          RouteNames.vod => VodScreen(
            vodItems: appState.vodItems,
            categories: appState.vodCategories,
            isLoading: appState.isLoadingContent,
            isConfigured: appState.isConfigured,
            onVodSelect: _openVod,
            onSidebarActivate: onSidebarActivate,
          ),
          RouteNames.series => SeriesScreen(
            seriesList: appState.seriesList,
            categories: appState.seriesCategories,
            isLoading: appState.isLoadingContent,
            isConfigured: appState.isConfigured,
            onSeriesSelect: _openSeries,
            onSidebarActivate: onSidebarActivate,
          ),
          RouteNames.settings => SettingsScreen(
            authNotifier: appState.authNotifier,
            activeViewer: appState.activeViewer,
            viewers: appState.viewers,
            sourceLabel: appState.sourceLabel,
            sourceError: appState.error,
            isConfiguredOverride: appState.isConfigured,
            epgRefreshInterval: appState.epgRefreshInterval,
            epgRefreshOptions: AppStateController.epgRefreshOptions,
            onConnect: appState.connectXtream,
            onDisconnect: () => unawaited(appState.disconnect()),
            onSwitchViewer: (viewer) =>
                unawaited(appState.switchViewer(viewer)),
            onCreateViewer: appState.createViewer,
            onClearCache: () => unawaited(appState.clearAndRefresh()),
            onEpgIntervalChanged: (d) =>
                unawaited(appState.setEpgRefreshInterval(d)),
            onConnected: onConnected,
          ),
          _ => const PlaceholderScreen(title: 'Home'),
        };
      },
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.appState,
    required this.onChannelSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    this.onSidebarActivate,
  });

  final AppStateController appState;
  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    if (!appState.isConfigured) {
      return const Scaffold(
        body: Center(child: Text('Please connect to your service in Settings')),
      );
    }

    final continueWatchingItems = appState.progressList
        .where(_isResumeEligible)
        .map(_resumePreviewItem)
        .whereType<MediaPreviewItem>()
        .toList(growable: false);
    final continueWatchingSection = MediaPreviewSection(
      title: 'Continue Watching',
      emptyLabel: 'No Continue Watching available',
      items: continueWatchingItems,
      onSidebarActivate: onSidebarActivate,
    );
    final liveSection = MediaPreviewSection(
      title: 'Live TV',
      emptyLabel: 'No Live TV available',
      items: appState.channels
          .map(
            (channel) => MediaPreviewItem(
              title: channel.name,
              imageUrl: channel.logoUrl,
              subtitle:
                  appState.epgService
                      .lookupForChannel(channel)
                      ?.current
                      .title ??
                  channel.groupTitle ??
                  'Live channel',
              fallbackIcon: Icons.live_tv,
              imageFit: BoxFit.contain,
              imagePadding: const EdgeInsets.all(10),
              imageBackgroundColor: Colors.transparent,
              onTap: () => onChannelSelect(channel),
            ),
          )
          .toList(growable: false),
      onSidebarActivate: onSidebarActivate,
    );
    final moviesSection = MediaPreviewSection(
      title: 'Movies',
      emptyLabel: 'No Movies available',
      posterStyle: true,
      items: appState.vodItems
          .map(
            (item) => MediaPreviewItem(
              title: item.name,
              imageUrl: item.logoUrl,
              subtitle: item.rating == null ? 'Movie' : '★ ${item.rating}',
              fallbackIcon: Icons.movie,
              fallbackTitle: item.name,
              onTap: () => onVodSelect(item),
            ),
          )
          .toList(growable: false),
      onSidebarActivate: onSidebarActivate,
    );
    final seriesSection = MediaPreviewSection(
      title: 'Series',
      emptyLabel: 'No Series available',
      posterStyle: true,
      items: appState.seriesList
          .map(
            (series) => MediaPreviewItem(
              title: series.name,
              imageUrl: series.coverUrl,
              subtitle: series.rating == null ? 'Series' : '★ ${series.rating}',
              fallbackIcon: Icons.tv,
              fallbackTitle: series.name,
              onTap: () => onSeriesSelect(series),
            ),
          )
          .toList(growable: false),
      onSidebarActivate: onSidebarActivate,
    );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        children: [
          Text('Home', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          Text('Connected source: ${appState.sourceLabel}'),
          const SizedBox(height: MediaBrowsingMetrics.pagePadding),
          if (continueWatchingItems.isNotEmpty) continueWatchingSection,
          liveSection,
          moviesSection,
          seriesSection,
        ],
      ),
    );
  }

  bool _isResumeEligible(Progress progress) {
    return progress.contentType != ContentType.live &&
        progress.positionSeconds >= 30 &&
        !progress.completed;
  }

  MediaPreviewItem? _resumePreviewItem(Progress progress) {
    if (progress.contentType == ContentType.vod) {
      final item = appState.vodItems.firstWhereOrNull(
        (item) => item.id == progress.streamId,
      );
      if (item == null) return null;
      return MediaPreviewItem(
        title: 'Resume ${item.name}',
        imageUrl: item.logoUrl,
        subtitle: 'Stream ${progress.streamId}',
        fallbackIcon: Icons.play_circle_outline,
        imageFit: BoxFit.contain,
        imageAspectRatio: 2 / 3,
        fallbackTitle: item.name,
        onTap: () => onProgressSelect(progress),
      );
    }

    if (progress.contentType == ContentType.episode &&
        progress.seriesId != null) {
      final series = appState.seriesList.firstWhereOrNull(
        (series) => series.id == progress.seriesId,
      );
      if (series == null) return null;
      return MediaPreviewItem(
        title: 'Resume ${series.name}',
        imageUrl: series.coverUrl,
        subtitle: 'Episode ${progress.streamId}',
        fallbackIcon: Icons.play_circle_outline,
        imageFit: BoxFit.contain,
        imageAspectRatio: 2 / 3,
        fallbackTitle: series.name,
        onTap: () => onProgressSelect(progress),
      );
    }

    return null;
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

// --- Intent and Action classes for keyboard shortcuts ---

class _BackIntent extends Intent {
  const _BackIntent();
}

class _MenuIntent extends Intent {
  const _MenuIntent();
}

class _BackAction extends Action<_BackIntent> {
  _BackAction(this.onBack);

  final bool Function() onBack;

  @override
  Object? invoke(_BackIntent intent) {
    onBack();
    return null;
  }
}

class _MenuAction extends Action<_MenuIntent> {
  _MenuAction(this.onMenu);

  final VoidCallback onMenu;

  @override
  Object? invoke(_MenuIntent intent) {
    onMenu();
    return null;
  }
}
