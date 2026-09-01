import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:clock/clock.dart';
import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_catalog_screen.dart';
import 'package:m3u_tv/features/dvr/dvr_recordings_screen.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/features/notifications/notifications_screen.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/player/resume_modal.dart';
import 'package:m3u_tv/features/requests/request_screen.dart';
import 'package:m3u_tv/features/search/search_screen.dart';
import 'package:m3u_tv/features/series/series_screen.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/content_actions.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/desktop_notification_presenter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_background.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/continue_watching_items.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
import 'package:m3u_tv/shared/dvr_schedule_feedback.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/notification_toast.dart';
import 'package:window_manager/window_manager.dart';

/// Height of the hidden-titlebar drag strip on macOS desktop - keeps the
/// window draggable and clears the floating traffic-light buttons, which
/// content would otherwise render underneath (see main.dart's
/// TitleBarStyle.hidden setup). Painted solid with the app's background
/// color rather than transparent.
const double _kMacTitlebarInset = 28;

/// Duration for the sidebar-hide/content-expand transition when a
/// full-screen detail route (VOD/series/AIOStreams item) pushes or pops —
/// matched to _slidePage's default CustomTransitionPage duration in
/// go_router_config.dart so both animations read as one motion.
const Duration _kFullScreenDetailTransition = Duration(milliseconds: 300);

bool get _isMacDesktopWindow => Platform.isMacOS;

/// Device type enum matching the RN useDeviceType hook.
enum DeviceType { tv, desktop, tablet, phone }

/// Whether a device type should use sidebar navigation.
bool shouldUseSidebar(DeviceType deviceType) =>
    deviceType == DeviceType.tv || deviceType == DeviceType.desktop;

String notificationRouteFor(
  TvNotificationDestination destination, {
  bool hasDvrFeature = false,
  bool hasRequestsFeature = false,
}) => switch (destination) {
  TvNotificationDestination.dvr when hasDvrFeature => RouteNames.dvr,
  TvNotificationDestination.requests when hasRequestsFeature =>
    RouteNames.requests,
  _ => RouteNames.notifications,
};

String _routeLabel(BuildContext context, String route) {
  final l = AppLocalizations.of(context);
  return switch (route) {
    RouteNames.home => l.navHome,
    RouteNames.search => l.navSearch,
    RouteNames.liveTv => l.navLiveTv,
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

/// Root shell with adaptive scaffold: sidebar for TV/desktop, bottom nav for
/// phone/tablet. Includes TV focus traversal, D-pad/keyboard shortcuts, back
/// handling, and focus restoration.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.deviceType,
    this.appState,
    this.playbackOrchestratorBuilder,
    this.playerRouteBuilder,
    this.systemUiPolicy,
    this.desktopNotificationPresenter,
  });

  final StatefulNavigationShell navigationShell;
  final DeviceType deviceType;
  final AppStateController? appState;
  final PlaybackOrchestrator Function()? playbackOrchestratorBuilder;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;
  final SystemUiPolicy? systemUiPolicy;
  final DesktopNotificationPresenter? desktopNotificationPresenter;

  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

class AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  bool _sidebarActive = false;

  // Counter rather than a bool: nested detail scaffolds (e.g. a Requests
  // detail pushed from within a modal flow) can overlap briefly during a
  // route transition, so "active" is any depth > 0 rather than the last
  // writer winning.
  int _fullScreenDetailDepth = 0;
  bool get _fullScreenDetailActive => _fullScreenDetailDepth > 0;
  late final AppStateController _appState;
  late final bool _ownsAppState;
  late final SystemUiPolicy _systemUiPolicy;
  int _unreadCount = 0;

  DateTime? _lastBackPress;
  Timer? _backExitTimer;

  // TV-only: when the app returns to the foreground after having been
  // backgrounded for at least this long, navigate back to the user's
  // configured start page instead of resuming wherever they left off. On the
  // couch, reopening the app is expected to land on your "home base"; on
  // desktop/mobile users task-switch constantly and expect their place kept,
  // so this is gated to DeviceType.tv. The grace period keeps brief
  // interruptions (voice assistant overlay, a permission dialog) from
  // resetting the user.
  static const Duration _tvForegroundResetGrace = Duration(seconds: 5);
  DateTime? _backgroundedAt;
  int _lastNavMs = 0;
  int _lastNavIndex = -1;
  StreamSubscription<TvNotificationItem>? _tvNotificationSub;
  StreamSubscription<TvNotificationDestination>? _notificationActivationSub;
  final _toastKey = GlobalKey<NotificationToastOverlayState>();
  late final DesktopNotificationDispatcher _desktopNotificationDispatcher;

  PlayerArgs? _playerArgs;
  PlaybackOrchestrator? _playerOrchestrator;
  StreamSubscription<bool>? _playerNativePlaneSub;
  bool _playerNativePlaneActive = false;
  bool _playerHasFailed = false;
  // True while any root-navigator modal dialog opened from within the
  // player is on screen (track selector, stop/delete-recording confirm),
  // so back handling dismisses the dialog instead of closing the player.
  bool _playerModalDialogVisible = false;
  FocusNode? _focusBeforePlayer;

  // Bumped only when a brand-new player session starts (not on in-session
  // source switches, e.g. skip-previous/skip-next), so PlayerScreen's key
  // stays stable across a channel switch and its State survives via
  // didUpdateWidget instead of being torn down and rebuilt. This matters
  // because the Android Media3 and Apple AVKit native plugins each hold a
  // single global player behind their MethodChannel - remounting PlayerScreen
  // per channel would dispose the *previous* orchestrator after the *new*
  // one has already started loading, and that deferred dispose tears down
  // whatever the native side currently has loaded (the new channel).
  int _playerSessionId = 0;

  // Channels the user was browsing when the live player opened (filtered
  // category/favorites/search list), so skip-previous/skip-next in
  // PlaybackControls stays within that view instead of always cycling the
  // full unfiltered live channel list. Set by feature screens right before
  // they invoke onChannelSelect.
  List<Channel> _playerChannelContext = const <Channel>[];

  final List<FocusNode> _sidebarFocusNodes = [];
  final FocusScopeNode _contentFocusNode = FocusScopeNode();
  final FocusScopeNode _sidebarScopeNode = FocusScopeNode();

  List<String> get _mainRoutes => RouteNames.mainRoutes
      .where(
        (route) => route != RouteNames.aiostreams || _appState.hasAioStreams,
      )
      .where((route) => route != RouteNames.dvr || _appState.hasDvrFeature)
      .where(
        (route) => route != RouteNames.requests || _appState.hasRequestsFeature,
      )
      .toList(growable: false);

  int get _currentIndex {
    final route = RouteNames.mainRoutes[widget.navigationShell.currentIndex];
    final visibleIndex = _mainRoutes.indexOf(route);
    return visibleIndex < 0 ? 0 : visibleIndex;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appState = widget.appState ?? AppStateController();
    _ownsAppState = widget.appState == null;
    _systemUiPolicy = widget.systemUiPolicy ?? SystemUiPolicy();
    _desktopNotificationDispatcher = DesktopNotificationDispatcher(
      presenter:
          widget.desktopNotificationPresenter ??
          NativeDesktopNotificationPresenter(),
      onFallback: _enqueueNotificationToast,
    );
    _unreadCount = _appState.unreadNotificationCount;
    _appState.addListener(_onAppStateChanged);
    _tvNotificationSub = _appState.tvNotifications.listen(_onTvNotification);
    _notificationActivationSub = _appState.notificationActivations.listen(
      _onNotificationActivation,
    );
    if (!_appState.isConfigured) {
      unawaited(_appState.boot());
    }
    _initSidebarFocusNodes();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(
      _desktopNotificationDispatcher.initialize(
        defaultActionName: AppLocalizations.of(
          context,
        ).notificationsDesktopOpen,
        onActivation: _appState.handleNotificationActivation,
      ),
    );
  }

  Future<bool> _handleSystemBack() async {
    if (_playerModalDialogVisible) {
      final popped = await Navigator.of(
        context,
        rootNavigator: true,
      ).maybePop();
      if (popped) return true;
    }
    if (_handleBackPress()) return true;

    // Double-back to exit: require two back presses within 2 seconds.
    final now = DateTime.now();
    final last = _lastBackPress;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return false;
    }
    _backExitTimer?.cancel();
    _backExitTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _lastBackPress = null);
    });
    if (mounted) {
      setState(() => _lastBackPress = now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).appBackToExit),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  bool get _canSystemExit => _playerArgs == null && _lastBackPress != null;

  bool _handleNavigationNotification(NavigationNotification notification) {
    if (_canSystemExit || notification.canHandlePop) return false;
    const NavigationNotification(canHandlePop: true).dispatch(context);
    return true;
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _syncSidebarFocusNodes();
    final route = RouteNames.mainRoutes[widget.navigationShell.currentIndex];
    if (!_mainRoutes.contains(route)) {
      widget.navigationShell.goBranch(0, initialLocation: true);
    }
    final newCount = _appState.unreadNotificationCount;
    if (_unreadCount != newCount) {
      setState(() => _unreadCount = newCount);
    }
  }

  void _initSidebarFocusNodes() {
    _syncSidebarFocusNodes();
  }

  void _syncSidebarFocusNodes([List<String>? routes]) {
    final r = routes ?? _mainRoutes;
    if (_sidebarFocusNodes.length == r.length) return;
    while (_sidebarFocusNodes.length < r.length) {
      _sidebarFocusNodes.add(FocusNode());
    }
    while (_sidebarFocusNodes.length > r.length) {
      _sidebarFocusNodes.removeLast().dispose();
    }
  }

  void _onTvNotification(TvNotificationItem item) {
    unawaited(_desktopNotificationDispatcher.dispatch(item));
  }

  void _enqueueNotificationToast(TvNotificationItem item) {
    if (!mounted) return;
    _toastKey.currentState?.enqueue(item);
  }

  void _onToastTap(TvNotificationItem item) {
    _navigateToRoute(RouteNames.notifications);
  }

  void _onNotificationActivation(TvNotificationDestination destination) {
    _navigateToRoute(
      notificationRouteFor(
        destination,
        hasDvrFeature: _appState.hasDvrFeature,
        hasRequestsFeature: _appState.hasRequestsFeature,
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_systemUiPolicy.applyBrowsing());
    _backExitTimer?.cancel();
    _tvNotificationSub?.cancel().ignore();
    _notificationActivationSub?.cancel().ignore();
    _desktopNotificationDispatcher.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _playerOrchestrator?.dispose().ignore();
    _playerNativePlaneSub?.cancel().ignore();
    for (final node in _sidebarFocusNodes) {
      node.dispose();
    }
    _contentFocusNode.dispose();
    _sidebarScopeNode.dispose();
    _appState.removeListener(_onAppStateChanged);
    if (_ownsAppState) _appState.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = clock.now();
      unawaited(_appState.suspendNotifications());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    unawaited(_appState.resumeNotifications());
    unawaited(
      _playerArgs == null || _playerHasFailed
          ? _systemUiPolicy.applyBrowsing()
          : _systemUiPolicy.applyPlayer(),
    );
    // After the system-UI call above: when this resets to the start page it
    // may close an open player, and _closePlayer restores the browsing
    // system UI itself.
    _maybeResetToStartPageAfterBackground();
  }

  /// TV-only: on returning from a real background (longer than
  /// [_tvForegroundResetGrace]), close any open player and switch to the
  /// user's configured start page so reopening the app lands on their
  /// preferred landing screen rather than wherever they left off. No-op on
  /// desktop/mobile, where keeping the user's place is the expected behavior.
  void _maybeResetToStartPageAfterBackground() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (widget.deviceType != DeviceType.tv) return;
    if (backgroundedAt == null) return;
    if (clock.now().difference(backgroundedAt) < _tvForegroundResetGrace) {
      return;
    }

    final startRoute = _appState.viewSettingsService.defaultStartPageSync.route;
    final branchIndex = RouteNames.mainRoutes.indexOf(startRoute);
    if (branchIndex < 0) return;

    if (_playerArgs != null) unawaited(_closePlayer());

    // Defer the navigation out of the lifecycle callback: goBranch drives a
    // router rebuild, which is not safe to trigger synchronously from
    // didChangeAppLifecycleState. initialLocation:true resets the target
    // branch to its root screen, dropping any nested detail route the user
    // had open on it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.navigationShell.goBranch(branchIndex, initialLocation: true);
      if (_sidebarActive) setState(() => _sidebarActive = false);
      _contentFocusNode.requestFocus();
    });
  }

  void _navigateTo(int index) {
    final routes = _mainRoutes;
    if (index < 0 || index >= routes.length || index == _currentIndex) return;
    final branchIndex = RouteNames.mainRoutes.indexOf(routes[index]);
    if (branchIndex < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (index == _lastNavIndex && now - _lastNavMs < 350) return;
    _lastNavMs = now;
    _lastNavIndex = index;
    widget.navigationShell.goBranch(
      branchIndex,
      initialLocation: branchIndex == widget.navigationShell.currentIndex,
    );
    if (shouldUseSidebar(widget.deviceType)) {
      setState(() => _sidebarActive = false);
      unawaited(
        Future.microtask(() {
          if (mounted) _contentFocusNode.requestFocus();
        }),
      );
    }
  }

  void _navigateToRoute(String routeName) {
    final index = _mainRoutes.indexOf(routeName);
    if (index >= 0) _navigateTo(index);
  }

  void _activateSidebar() {
    if (_fullScreenDetailActive) return;
    setState(() {
      _sidebarActive = true;
    });
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

  // Screens that render a MediaCategoryNav strip (VOD/Series/Live TV/
  // Requests) register their strip's own FocusScopeNode here, keyed by
  // route, so _deactivateSidebar can always land there first instead of
  // wherever focus happened to be before the sidebar was activated. Flutter's
  // native FocusScopeNode restoration (`_contentFocusNode.requestFocus()`
  // below) always drills down to whichever of a screen's sibling scopes
  // (strip vs. grid) last held actual focus - which, once a screen has both,
  // means it would silently skip the strip and land straight back in the
  // grid whenever the grid was the last thing focused. Keying by route
  // (rather than tracking "the last registered node") avoids clobbering the
  // active tab's registration: go_router's StatefulNavigationShell keeps
  // every visited branch mounted, so a screen registers exactly once, the
  // first time its tab is built, and that registration is never disposed
  // just because another tab becomes active.
  final Map<String, FocusScopeNode> _contentEntryFocusByRoute = {};

  void _registerContentEntryFocus(String routeName, FocusScopeNode node) {
    _contentEntryFocusByRoute[routeName] = node;
  }

  // Lets a screen intercept the Back key itself before AppShell's default
  // handling (sidebar activation) runs - currently only Live TV, to move
  // focus to the EPG's Channels column instead. Same route-keyed,
  // register-once pattern as _contentEntryFocusByRoute above, for the same
  // StatefulNavigationShell branch-retention reason.
  final Map<String, bool Function()> _contentBackHandlerByRoute = {};

  void _registerContentBackHandler(String routeName, bool Function() handler) {
    _contentBackHandlerByRoute[routeName] = handler;
  }

  void _deactivateSidebar() {
    setState(() {
      _sidebarActive = false;
    });
    unawaited(
      Future.microtask(() {
        if (!mounted) return;
        final route =
            RouteNames.mainRoutes[widget.navigationShell.currentIndex];
        final entry = _contentEntryFocusByRoute[route];
        if (entry != null) {
          entry.requestFocus();
        } else {
          _contentFocusNode.requestFocus();
        }
      }),
    );
  }

  // Stable method tearoff passed to ContentActions.onOpenPlayer.
  // Must NOT be a local closure in build() - closures are always new instances,
  // which makes ContentActions.updateShouldNotify return true on every rebuild
  // and cascade unnecessary rebuilds to all feature screens.
  void _openPlayerFromActions(PlayerArgs args) =>
      unawaited(_openPlayer(context, args));

  Future<void> _openPlayer(BuildContext context, PlayerArgs args) async {
    var resolvedArgs = args;
    if ((resolvedArgs.type == 'vod' || resolvedArgs.type == 'series') &&
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

  /// Applies the per-device proxy playback preferences (enable proxy +
  /// live/VOD transcoding profile) to backend stream URLs. External URLs
  /// (e.g. AIOStreams sources) pass through unchanged.
  PlayerArgs _applyProxyPlayback(PlayerArgs args) {
    final proxy = _appState.authNotifier.authResponse?.proxy;
    final server = _appState.xtreamService.credentials?.server;
    if (proxy == null || server == null) return args;

    final updated = _appState.proxyPlaybackSettings.apply(
      args.streamUrl,
      type: args.type,
      forced: proxy.forced,
      serverBase: server,
    );
    return updated == args.streamUrl ? args : args.copyWith(streamUrl: updated);
  }

  void _openPlayerDirect(PlayerArgs rawArgs) {
    ref.read(playerOverlayActiveProvider.notifier).state = true;
    final args = _applyProxyPlayback(rawArgs);
    unawaited(_systemUiPolicy.applyPlayer());

    if (_playerOrchestrator != null) {
      // A player is already open (skip-previous/skip-next, or the up-next
      // overlay swapping episodes) - reuse its orchestrator/session rather
      // than building a new one. PlayerScreen's key is unchanged, so the
      // framework updates the existing State via didUpdateWidget instead of
      // disposing it, keeping exactly one native player instance alive for
      // the whole session. Deliberately do NOT re-capture _focusBeforePlayer
      // here: primary focus is inside the player now, so it'd null out the
      // real pre-player node (the originating card) and lose the restore
      // target for when the session finally closes.
      setState(() {
        _playerArgs = args;
        _playerHasFailed = false;
        _playerNativePlaneActive = _playerOrchestrator!.isNativePlaneActive;
      });
      return;
    }

    // Save the focused node so we can restore it precisely after the player
    // closes. _contentFocusNode.requestFocus() alone is unreliable: when
    // PlayerScreen disposes _screenFocusNode, Flutter's _willDisposeFocusNode
    // calls requestFocusWithin() on the root scope, which finds the FIRST
    // focusable in the tree (often the initial route, not the current one)
    // and corrupts _contentFocusNode._focusedChild before our postFrameCallback
    // gets a chance to run.
    final focus = FocusManager.instance.primaryFocus;
    _focusBeforePlayer = _isInContentScope(focus) ? focus : null;

    _playerSessionId += 1;
    final newOrch =
        widget.playbackOrchestratorBuilder?.call() ??
        buildPlaybackOrchestrator();
    setState(() {
      _playerArgs = args;
      _playerOrchestrator = newOrch;
      _playerNativePlaneActive = newOrch.isNativePlaneActive;
      _playerHasFailed = false;
    });
    _playerNativePlaneSub = newOrch.onNativePlaneCompositionChanged.listen((
      active,
    ) {
      if (!mounted || !identical(_playerOrchestrator, newOrch)) return;
      if (_playerNativePlaneActive == active) return;
      setState(() => _playerNativePlaneActive = active);
    });
  }

  bool _isInContentScope(FocusNode? node) {
    var current = node;
    while (current != null) {
      if (current == _contentFocusNode) return true;
      current = current.parent;
    }
    return false;
  }

  Future<void> _closePlayer() async {
    ref.read(playerOverlayActiveProvider.notifier).state = false;
    final orch = _playerOrchestrator;
    final nativePlaneSub = _playerNativePlaneSub;
    final savedFocus = _focusBeforePlayer;
    _focusBeforePlayer = null;
    unawaited(_systemUiPolicy.applyBrowsing());
    // Stop (and fully dispose) the active adapter BEFORE removing
    // PlayerScreen's native view (Texture/PlatformView) from the widget
    // tree, not after. This used to run in a postFrameCallback scheduled
    // *after* the tree-removing setState below, which raced against
    // Flutter tearing down the native platform view -- tvOS's mpv backend
    // hands mpv an unretained pointer to its video layer via `wid`, so a
    // platform view torn down before mpv had actually stopped touching it
    // was a use-after-free that crashed reliably on stop. Bounded with a
    // timeout: a hung backend dispose() must not leave the whole app stuck
    // unable to close the player.
    try {
      await orch?.dispose().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Fall through and close anyway -- better to leak a not-fully-disposed
      // adapter than leave the user stuck on a dead player screen.
    }
    nativePlaneSub?.cancel().ignore();
    if (!mounted) return;
    setState(() {
      _playerArgs = null;
      _playerOrchestrator = null;
      _playerNativePlaneSub = null;
      _playerNativePlaneActive = false;
      _playerHasFailed = false;
      _playerModalDialogVisible = false;
    });
    _playerChannelContext = const <Channel>[];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (savedFocus != null && savedFocus.canRequestFocus) {
        savedFocus.requestFocus();
      } else {
        _contentFocusNode.requestFocus();
      }
    });
  }

  bool _handleBackPress() {
    if (_playerArgs != null) {
      unawaited(_closePlayer());
      return true;
    }

    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return true;
    }

    final route = RouteNames.mainRoutes[widget.navigationShell.currentIndex];
    final screenBackHandler = _contentBackHandlerByRoute[route];
    if (screenBackHandler != null && screenBackHandler()) {
      return true;
    }

    if (shouldUseSidebar(widget.deviceType) && !_sidebarActive) {
      _activateSidebar();
      return true;
    }

    return false;
  }

  void _setPlayerModalDialogVisible(bool visible) {
    if (!mounted || _playerModalDialogVisible == visible) return;
    setState(() => _playerModalDialogVisible = visible);
  }

  bool _handleShortcutBack() {
    if (_playerModalDialogVisible) {
      unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      return true;
    }
    return _handleBackPress();
  }

  void _openChannel(Channel channel) {
    unawaited(
      _openPlayer(
        context,
        PlayerArgs(
          streamUrl: channel.streamUrl,
          title: channel.name,
          type: 'live',
          streamId: channel.id,
          epgChannelId: channel.epgChannelId ?? channel.tvgName ?? channel.name,
          headers: channel.headers,
        ),
      ),
    );
  }

  // Stable tearoffs passed to PlayerScreen so PlaybackControls can offer
  // channel-up/channel-down without PlayerScreen needing to know about
  // liveChannelsProvider itself.
  void _openNextChannel() => _switchChannel(1);
  void _openPreviousChannel() => _switchChannel(-1);

  // Set by feature screens right before they call onChannelSelect, so
  // skip-previous/skip-next in the player can stay within the filtered view
  // (category, favorites, search) the user was browsing.
  void _setChannelContext(List<Channel> channels) {
    _playerChannelContext = channels;
  }

  void _switchChannel(int direction) {
    final args = _playerArgs;
    if (args == null || args.type != 'live') return;
    // A context of exactly one channel (e.g. the On Now rail's set of
    // channels airing the searched show) can't skip anywhere - fall back to
    // the full channel list rather than silently no-op on `% 1 == 0`.
    final channels = _playerChannelContext.length > 1
        ? _playerChannelContext
        : ref.read(liveChannelsProvider);
    if (channels.isEmpty) return;
    final currentIndex = channels.indexWhere((c) => c.id == args.streamId);
    if (currentIndex == -1) return;
    final nextIndex =
        (currentIndex + direction + channels.length) % channels.length;
    _openChannel(channels[nextIndex]);
  }

  void _handleRecordButtonTap(EpgProgram program) {
    final args = _playerArgs;
    if (args == null || args.type != 'live') return;
    final channels = _playerChannelContext.isNotEmpty
        ? _playerChannelContext
        : ref.read(liveChannelsProvider);
    final channel = channels.firstWhereOrNull((c) => c.id == args.streamId);
    if (channel == null) return;

    final activeRecording = _appState.dvrRecordings.firstWhereOrNull(
      (r) => r.channelId == channel.id && r.isInProgress,
    );
    if (activeRecording != null) {
      unawaited(_confirmStopRecording(context, activeRecording));
      return;
    }
    unawaited(_scheduleDvr(context, channel, program));
  }

  /// Same choice offered on the Recordings screen for an in-progress
  /// recording (see DvrRecordingsScreen._confirmCancel): keep the footage
  /// captured so far, or cancel and delete it outright.
  Future<void> _confirmStopRecording(
    BuildContext context,
    DvrRecording recording,
  ) async {
    _setPlayerModalDialogVisible(true);
    try {
      await confirmStopOrDeleteRecording(
        context,
        recording: recording,
        onCancel: _appState.cancelDvrRecording,
        onCancelAndDelete: _cancelAndDeleteRecording,
      );
    } finally {
      _setPlayerModalDialogVisible(false);
    }
  }

  void _openCatchupProgram(Channel channel, EpgProgram program) {
    if (_appState.sourceType != AppSourceType.xtream) {
      _openChannel(channel);
      return;
    }
    final duration = program.end.difference(program.start);
    final streamUrl = _appState.xtreamService.getCatchupStreamUrl(
      channel.id,
      program.start,
      duration,
    );
    unawaited(
      _openPlayer(
        context,
        PlayerArgs(
          streamUrl: streamUrl,
          title: '${channel.name} - ${program.displayTitle}',
          type: 'catchup',
          streamId: channel.id,
          startPosition: 0,
          epgChannelId: channel.epgChannelId ?? channel.tvgName ?? channel.name,
          headers: channel.headers,
          metadata: <String, Object?>{
            'catchup': true,
            'program_title': program.displayTitle,
            'program_start': program.start.toIso8601String(),
            'program_end': program.end.toIso8601String(),
          },
        ),
      ),
    );
  }

  Future<void> _scheduleDvr(
    BuildContext context,
    Channel channel,
    EpgProgram program,
  ) {
    return scheduleDvrWithFeedback(
      context,
      schedule: () => _appState.scheduleDvrAiring(
        channelId: channel.id,
        title: program.displayTitle,
        startTime: program.start,
        endTime: program.end,
      ),
      title: program.displayTitle,
    );
  }

  /// Schedules a single DVR airing for one Shows-search episode. No
  /// SnackBar here: the screen owns success/failure feedback (mirroring
  /// how the live-tv `_scheduleDvr` keeps it out of the scheduling call).
  Future<DvrRecording?> _scheduleDvrAiring(EpgShowEpisode episode) {
    return _appState.scheduleDvrAiring(
      channelId: episode.channelId,
      title: episode.displayTitle,
      startTime: episode.startTime,
      endTime: episode.endTime,
    );
  }

  /// Schedules a batch of DVR airings for one Shows-search selection.
  /// Per-item failures land inside the returned list (the screen turns that
  /// into a single summary SnackBar), no per-item SnackBars here, mirroring
  /// the single-item `_scheduleDvrAiring`'s "screen owns feedback" rule.
  Future<List<DvrAiringScheduleResult>> _scheduleDvrAirings(
    List<EpgShowEpisode> episodes,
  ) {
    return _appState.scheduleDvrAirings(episodes);
  }

  /// Calls the foundation-agent-owned `XtreamService.createDvrSeriesRule`
  /// and refreshes the cached series rules list so the DVR screen's new
  /// "Series Rules" section reflects the addition immediately.
  ///
  /// Returns a [CreateDvrSeriesRuleOutcome] so the UI can tell
  /// "rule created" / "duplicate of existing rule" / "failed" apart and
  /// show the right SnackBar without losing the A3-409 distinction that
  /// `XtreamService.createDvrSeriesRule` throws as
  /// `DvrSeriesRuleExistsException`. The `on Object { return false; }`
  /// blanket from earlier releases would have collapsed the duplicate case
  /// into a generic failure - B2 surfaces it instead.
  Future<CreateDvrSeriesRuleOutcome> _createDvrSeriesRule({
    int? channelId,
    required String title,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  }) async {
    try {
      final id = await _appState.xtreamService.createDvrSeriesRule(
        channelId: channelId,
        title: title,
        matchMode: matchMode,
        seriesMode: seriesMode,
        keepLast: keepLast,
        priority: priority,
        startEarlySeconds: startEarlySeconds,
        endLateSeconds: endLateSeconds,
      );
      await _appState.refreshDvrSeriesRules();
      // The rule's `created` hook may have already matched and scheduled a
      // recording server-side (see AppStateController.refreshDvrRecordings
      // doc comment) - refresh so it shows up in the Recordings tab without
      // waiting for the next full app reload.
      unawaited(_appState.refreshDvrRecordings());
      return id == 0
          ? CreateDvrSeriesRuleOutcome.failed
          : CreateDvrSeriesRuleOutcome.created;
    } on DvrSeriesRuleExistsException {
      try {
        await _appState.refreshDvrSeriesRules();
      } on Object catch (error, stackTrace) {
        debugPrint('DVR: refresh after duplicate create failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return CreateDvrSeriesRuleOutcome.duplicate;
    } on Object catch (error, stackTrace) {
      debugPrint('DVR: create series rule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return CreateDvrSeriesRuleOutcome.failed;
    }
  }

  /// Deletes a DVR series rule and refreshes the cached list.
  Future<void> _deleteDvrSeriesRule(DvrSeriesRule rule) async {
    await _appState.xtreamService.deleteDvrSeriesRule(rule.id);
    await _appState.refreshDvrSeriesRules();
  }

  /// Updates an existing DVR series rule in place (never delete-and-recreate —
  /// deleting cascades to the rule's recordings and would destroy history) and
  /// refreshes the cached list. `updateDvrSeriesRule` applies only the fields
  /// the sheet returned; absent fields keep their current server values.
  Future<void> _updateDvrSeriesRule(
    DvrSeriesRule rule,
    DvrSeriesRuleOptions options,
  ) async {
    await _appState.xtreamService.updateDvrSeriesRule(
      ruleId: rule.id,
      channelId: options.channelId,
      matchMode: options.matchMode,
      seriesMode: options.seriesMode,
      keepLast: options.keepLast,
      priority: options.priority,
      startEarlySeconds: options.startEarlySeconds,
      endLateSeconds: options.endLateSeconds,
    );
    await _appState.refreshDvrSeriesRules();
    unawaited(_appState.refreshDvrRecordings());
  }

  /// Proxies the Shows screen's search through the foundation-agent-owned
  /// `XtreamService.searchEpgShows`.
  Future<List<EpgShow>> _searchEpgShows(String query) {
    return _appState.xtreamService.searchEpgShows(query);
  }

  /// Stops a scheduled or in-progress recording and deletes the row from the
  /// editor - the "Delete recording" choice on the Recordings screen's stop
  /// dialog (see DvrRecordingsScreen._confirmCancel). m3u-editor's
  /// `cancel_dvr_recording` only marks the recording `cancelled` (a stop +
  /// history-keep operation), so this chains a follow-up `delete_dvr_recording`
  /// once the row is in a deletable state. The "Keep recording" choice instead
  /// calls `AppStateController.cancelDvrRecording` directly and stops here.
  ///
  /// If the cancel succeeds but the delete fails (e.g. transient server
  /// hiccup), the recording is still stopped and stays in the local list with
  /// its Cancelled status - the user can retry Delete from there. The delete
  /// failure is rethrown (not swallowed) so DvrRecordingsScreen's
  /// _runWithFeedback shows the "could not delete" SnackBar instead of a
  /// false "deleted" success message for a recording that's still there.
  Future<void> _cancelAndDeleteRecording(String uuid) async {
    await _appState.cancelDvrRecording(uuid);
    try {
      await _appState.deleteDvrRecording(uuid);
    } on Object catch (error) {
      debugPrint('DVR: post-cancel delete failed: $error');
      rethrow;
    }
  }

  /// Pushes a detail route. When [fullScreen] is true, the sidebar-hide
  /// transition is tied directly to this call's own push/pop - flipped
  /// synchronously right before `context.push` and unwound in `finally`
  /// once that same push's route is gone - rather than to the pushed
  /// widget's own init/dispose lifecycle. A widget can only announce itself
  /// after it already exists, which is inherently a frame (or more) behind
  /// the moment navigation was requested; doing it here instead means the
  /// AppShell layout animation and the route's own transition start on the
  /// same frame in both directions, which is what makes it read as one
  /// smooth motion instead of a layout snap partway through the slide.
  Future<void> _pushDetail(
    String path, {
    Object? extra,
    bool fullScreen = false,
  }) async {
    await Future<void>.microtask(() {});
    final savedFocus = FocusManager.instance.primaryFocus;
    if (fullScreen) {
      setState(() => _fullScreenDetailDepth++);
    }
    try {
      // ignore: use_build_context_synchronously
      await context.push(path, extra: extra);
    } finally {
      if (fullScreen && mounted) {
        setState(() => _fullScreenDetailDepth--);
      }
    }
    if (mounted) {
      if (savedFocus != null && savedFocus.canRequestFocus) {
        savedFocus.requestFocus();
      } else {
        _contentFocusNode.requestFocus();
      }
    }
  }

  void _openVod(VodItem item) {
    unawaited(
      _pushDetail(
        RouteNames.vodDetailsFor(item.id),
        extra: item,
        fullScreen: true,
      ),
    );
  }

  void _openRequestResult(ContentRequestSearchResult result) {
    unawaited(
      _pushDetail(
        RouteNames.requestsDetailsFor(
          result.integrationId,
          result.type,
          result.externalId,
        ),
        extra: result,
      ),
    );
  }

  void _openSeries(Series series) {
    unawaited(
      _pushDetail(
        RouteNames.seriesDetailsFor(series.id),
        extra: series,
        fullScreen: true,
      ),
    );
  }

  /// Marks a single series episode watched / unwatched for the active viewer.
  /// "Unwatched" zeroes the progress row (position 0, not completed) rather
  /// than deleting it - the Xtream API has no delete verb, and a zeroed row
  /// reads as unwatched everywhere (Continue Watching filters it out, the
  /// series detail no longer counts it as finished).
  /// Returns true when the change was fully persisted. The local resume store
  /// and in-memory list are always updated (offline-friendly); the boolean
  /// only reflects whether the server write also landed, so a "mark season"
  /// caller can tell the user if some episodes did not sync.
  Future<bool> _markEpisodeWatched({
    required int streamId,
    required int seriesId,
    required int seasonNumber,
    required int episodeNumber,
    int? durationSeconds,
    String? seriesName,
    String? episodeTitle,
    required bool watched,
  }) async {
    final viewer = _appState.activeViewer;
    if (viewer == null) return false;
    final progress = Progress(
      viewerId: viewer.ulid,
      contentType: ContentType.episode,
      streamId: streamId,
      positionSeconds: watched ? (durationSeconds ?? 0) : 0,
      durationSeconds: durationSeconds,
      completed: watched,
      seriesId: seriesId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      seriesName: seriesName,
      episodeTitle: episodeTitle,
    );
    var serverOk = true;
    if (_appState.sourceType == AppSourceType.xtream) {
      try {
        await _appState.xtreamService.updateProgress(progress);
      } on Object {
        serverOk = false;
      }
    }
    await _appState.resumeService.save(progress);
    if (mounted) _appState.updateProgressEntry(progress);
    return serverOk;
  }

  void _openAioSearch() {
    unawaited(
      _pushDetail(RouteNames.aiostreamsSearchPath, fullScreen: true),
    );
  }

  void _openShow(EpgShow show) {
    unawaited(
      _pushDetail(
        RouteNames.showDetailsFor(show.normalizedTitle),
        extra: show,
        fullScreen: true,
      ),
    );
  }

  /// Lets a descendant enter/exit the same immersive full-screen state as
  /// `_pushDetail(fullScreen: true)` - sidebar hidden, bottom nav hidden —
  /// without going through a go_router push itself. Needed for screens
  /// like the DVR series-rule Options page, which is opened via a plain
  /// `Navigator.push` (not a route) from a tab that isn't already
  /// immersive (the Series Rules tab, unlike Show Detail).
  void _enterFullScreenDetail() => setState(() => _fullScreenDetailDepth++);

  void _exitFullScreenDetail() {
    if (mounted) setState(() => _fullScreenDetailDepth--);
  }

  void _openProgress(Progress progress) {
    if (progress.contentType == ContentType.vod) {
      final item = _appState.vodItems.firstWhereOrNull(
        (item) => item.id == progress.streamId,
      );
      if (item != null) {
        unawaited(
          _openPlayer(
            context,
            PlayerArgs(
              streamUrl: item.streamUrl,
              title: progress.title ?? item.name,
              type: 'vod',
              streamId: item.id,
              metadata: <String, Object?>{
                'container_extension': item.containerExtension,
                if (progress.backdropUrl != null)
                  'backdrop_url': progress.backdropUrl,
                if (progress.thumbnailUrl != null)
                  'thumbnail_url': progress.thumbnailUrl,
                if (progress.rating != null) 'rating': progress.rating,
                if (progress.runtime != null) 'duration': progress.runtime,
              },
            ),
          ),
        );
      }
      return;
    }

    if (progress.contentType == ContentType.episode &&
        progress.seriesId != null) {
      final series = _appState.seriesList.firstWhereOrNull(
        (s) => s.id == progress.seriesId,
      );
      if (series != null) {
        final streamUrl = _appState.xtreamService.getSeriesStreamUrl(
          progress.streamId.toString(),
        );
        unawaited(
          _openPlayer(
            context,
            PlayerArgs(
              streamUrl: streamUrl,
              title: progress.episodeTitle ?? series.name,
              type: 'series',
              streamId: progress.streamId,
              seriesId: progress.seriesId,
              seasonNumber: progress.seasonNumber,
              metadata: <String, Object?>{
                if (series.tmdbId != null) 'tmdb_id': series.tmdbId,
                'series_name': progress.seriesName ?? series.name,
                if (progress.episodeNumber != null)
                  'episode_number': progress.episodeNumber,
                if (progress.seasonNumber != null)
                  'season_number': progress.seasonNumber,
                if (progress.episodeTitle != null)
                  'episode_title': progress.episodeTitle,
              },
            ),
          ),
        );
      }
    }
  }

  Widget _buildTabScreen(String routeName) {
    return switch (routeName) {
      RouteNames.home => _HomeScreen(
        onChannelSelect: _openChannel,
        onChannelContextChanged: _setChannelContext,
        onVodSelect: _openVod,
        onSeriesSelect: _openSeries,
        onProgressSelect: _openProgress,
        onContinueWatchingMore: () => unawaited(
          _pushDetail(RouteNames.continueWatchingPath, fullScreen: true),
        ),
        onRecordingsSelect: () => _navigateToRoute(RouteNames.dvr),
        onAioStreamsItemSelect: (item, integrationId) => unawaited(
          _pushDetail(
            RouteNames.aiostreamsDetailsFor(
              integrationId,
              item.type,
              item.id,
            ),
            extra: item,
            fullScreen: true,
          ),
        ),
        useSidebarLayout: shouldUseSidebar(widget.deviceType),
        onSidebarActivate: _activateSidebar,
      ),
      RouteNames.search => SearchScreen(
        onChannelSelect: _openChannel,
        onChannelContextChanged: _setChannelContext,
        onVodSelect: _openVod,
        onSeriesSelect: _openSeries,
        onSidebarActivate: _activateSidebar,
        onSearchShows: _searchEpgShows,
        onShowSelect: _openShow,
      ),
      RouteNames.liveTv => LiveTvScreen(
        favoritesService: _appState.favoritesService,
        viewSettingsService: _appState.viewSettingsService,
        useSidebarLayout: shouldUseSidebar(widget.deviceType),
        onChannelSelect: _openChannel,
        onChannelContextChanged: _setChannelContext,
        onCatchupProgramSelect: _openCatchupProgram,
        onSidebarActivate: _activateSidebar,
        onScheduleProgram: (channel, program) =>
            unawaited(_scheduleDvr(context, channel, program)),
        onEnsureEpg: _appState.ensureEpgForChannels,
        onCatchupEpgRequested: _appState.ensureCatchupEpgForChannel,
        onCancelRecording: (uuid) => _appState.cancelDvrRecording(uuid),
        onCancelAndDeleteRecording: _cancelAndDeleteRecording,
        onRecordSeries: (channel, program) => _createDvrSeriesRule(
          channelId: channel.id,
          title: program.title,
        ),
        onEnterFullScreenDetail: _enterFullScreenDetail,
        onExitFullScreenDetail: _exitFullScreenDetail,
        onEntryFocusScopeReady: (node) =>
            _registerContentEntryFocus(RouteNames.liveTv, node),
        onBackHandlerReady: (handler) =>
            _registerContentBackHandler(RouteNames.liveTv, handler),
        onSearchShows: _searchEpgShows,
        onShowSelect: _openShow,
      ),
      RouteNames.vod => VodScreen(
        onVodSelect: _openVod,
        favoritesService: _appState.vodFavoritesService,
        onSidebarActivate: _activateSidebar,
        useSidebarLayout: shouldUseSidebar(widget.deviceType),
        onEntryFocusScopeReady: (node) =>
            _registerContentEntryFocus(RouteNames.vod, node),
      ),
      RouteNames.series => SeriesScreen(
        onSeriesSelect: _openSeries,
        favoritesService: _appState.seriesFavoritesService,
        onSidebarActivate: _activateSidebar,
        useSidebarLayout: shouldUseSidebar(widget.deviceType),
        onEntryFocusScopeReady: (node) =>
            _registerContentEntryFocus(RouteNames.series, node),
      ),
      RouteNames.aiostreams => ListenableBuilder(
        listenable: _appState,
        builder: (_, _) => AIOStreamsHomeScreen(
          integrations: _appState.aiostreamsIntegrations,
          apiService: _appState.aiostreamsApiService,
          onItemSelect: (item, integrationId) => unawaited(
            _pushDetail(
              RouteNames.aiostreamsDetailsFor(
                integrationId,
                item.type,
                item.id,
              ),
              extra: item,
              fullScreen: true,
            ),
          ),
          onPlay: _openPlayerFromActions,
          onSearchSelect: _openAioSearch,
          favoritesService: _appState.aioFavoritesService,
          progressList: _appState.progressList,
          onSidebarActivate: _activateSidebar,
        ),
      ),
      RouteNames.dvr => ListenableBuilder(
        listenable: _appState,
        builder: (_, _) {
          if (_appState.isBootstrapping) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return DvrRecordingsScreen(
            recordings: _appState.dvrRecordings,
            isLoading: _appState.isLoadingContent,
            isConfigured: _appState.isConfigured,
            useInlineRowActions: shouldUseSidebar(widget.deviceType),
            storageInfo: ref.watch(dvrStorageInfoProvider),
            onPlay: _openPlayerDirect,
            onCancelRecording: (uuid) => _appState.cancelDvrRecording(uuid),
            onCancelAndDeleteRecording: _cancelAndDeleteRecording,
            onDeleteRecording: (uuid) => _appState.deleteDvrRecording(uuid),
            seriesRules: ref.watch(dvrSeriesRulesProvider),
            onDeleteSeriesRule: _deleteDvrSeriesRule,
            onUpdateSeriesRule: _updateDvrSeriesRule,
            onSearchShows: _searchEpgShows,
            onOpenShowDetail: _openShow,
            onEnterFullScreenDetail: _enterFullScreenDetail,
            onExitFullScreenDetail: _exitFullScreenDetail,
            onSidebarActivate: _activateSidebar,
          );
        },
      ),
      RouteNames.requests => ListenableBuilder(
        listenable: _appState,
        builder: (_, _) {
          if (_appState.isBootstrapping) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return RequestScreen(
            key: ValueKey(_appState.mediaRequestOwner),
            isConfigured: _appState.isConfigured,
            onSearch: _appState.searchContentRequests,
            onResultSelect: _openRequestResult,
            onDismiss: _appState.dismissMediaRequest,
            onRefreshRequests: _appState.refreshMediaRequests,
            onSidebarActivate: _activateSidebar,
            useSidebarLayout: shouldUseSidebar(widget.deviceType),
            onEntryFocusScopeReady: (node) =>
                _registerContentEntryFocus(RouteNames.requests, node),
          );
        },
      ),
      RouteNames.notifications => NotificationsScreen(
        onMarkRead: _appState.markNotificationRead,
        onMarkAllRead: _appState.markAllNotificationsRead,
        onSetChannels: _appState.setNotificationChannels,
      ),
      RouteNames.settings => ListenableBuilder(
        listenable: _appState,
        builder: (_, _) => SettingsScreen(
          authNotifier: _appState.authNotifier,
          deviceType: widget.deviceType,
          activeViewer: _appState.activeViewer,
          viewers: _appState.viewers,
          sourceLabel: _appState.sourceLabel,
          serverTimezone: _appState.serverTimezone,
          sourceError: _appState.error,
          isConfiguredOverride: _appState.isConfigured,
          epgRefreshInterval: _appState.epgRefreshInterval,
          epgRefreshOptions: AppStateController.epgRefreshOptions,
          traktService: _appState.traktService,
          devicePairingService: _appState.devicePairingService,
          onConnect: _appState.connectXtream,
          onDisconnect: () => unawaited(_appState.disconnect()),
          onSwitchViewer: (viewer) => unawaited(_appState.switchViewer(viewer)),
          onCreateViewer: _appState.createViewer,
          onClearCache: () => unawaited(_appState.clearAndRefresh()),
          onEpgIntervalChanged: (d) =>
              unawaited(_appState.setEpgRefreshInterval(d)),
          onConnected: () => _navigateTo(0),
          locale: _appState.locale,
          onLocaleChanged: (locale) => unawaited(_appState.setLocale(locale)),
          viewSettingsService: _appState.viewSettingsService,
          proxyPlaybackSettings: _appState.proxyPlaybackSettings,
          comskipSettings: _appState.comskipSettings,
        ),
      ),
      _ => const PlaceholderScreen(title: 'Home'),
    };
  }

  @override
  Widget build(BuildContext context) {
    // isConfigured triggers route recalculation on connect/disconnect.
    ref.watch(isConfiguredProvider);

    final routes = _mainRoutes;
    _syncSidebarFocusNodes(routes);
    final useSidebar = shouldUseSidebar(widget.deviceType);

    final contentShell = ContentActions(
      appState: _appState,
      onOpenPlayer: _openPlayerFromActions,
      onChannelSelect: _openChannel,
      onCatchupSelect: _openCatchupProgram,
      onVodSelect: _openVod,
      onSeriesSelect: _openSeries,
      onProgressSelect: _openProgress,
      onSidebarActivate: _activateSidebar,
      onRecordSeries: _createDvrSeriesRule,
      onDeleteSeriesRule: _deleteDvrSeriesRule,
      onScheduleEpisode: _scheduleDvrAiring,
      onScheduleEpisodes: _scheduleDvrAirings,
      onMarkEpisodeWatched: _markEpisodeWatched,
      buildTabScreen: _buildTabScreen,
      child: FocusScope(
        node: _contentFocusNode,
        child: widget.navigationShell,
      ),
    );

    final shell = Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.goBack): const _BackIntent(),
        LogicalKeySet(LogicalKeyboardKey.contextMenu): const _MenuIntent(),
        LogicalKeySet(LogicalKeyboardKey.f1): const _MenuIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _BackIntent: _BackAction(_handleShortcutBack),
          _MenuIntent: _MenuAction(_activateSidebar),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                useSidebar &&
                !_fullScreenDetailActive &&
                !_contentFocusNode.hasFocus) {
              _activateSidebar();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: useSidebar
              ? _buildTvLayout(contentShell, routes, _unreadCount)
              : _buildMobileLayout(contentShell, routes, _unreadCount),
        ),
      ),
    );
    final backAwareShell = NotificationListener<NavigationNotification>(
      onNotification: _handleNavigationNotification,
      child: PopScope<Object?>(
        canPop: _canSystemExit,
        child: BackButtonListener(
          onBackButtonPressed: _handleSystemBack,
          child: shell,
        ),
      ),
    );

    final args = _playerArgs;
    final orch = _playerOrchestrator;
    if (args == null || orch == null) {
      return NotificationToastOverlay(
        key: _toastKey,
        onNotificationTap: _onToastTap,
        child: backAwareShell,
      );
    }

    final viewerId = _appState.activeViewer?.ulid ?? '';
    final recordingChannelIds = ref.watch(recordingChannelIdsProvider);
    final suppressBrowsingComposition =
        _playerNativePlaneActive && !_playerHasFailed;

    return NotificationToastOverlay(
      key: _toastKey,
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: suppressBrowsingComposition,
            child: ExcludeSemantics(
              excluding: suppressBrowsingComposition,
              child: Opacity(
                opacity: suppressBrowsingComposition ? 0 : 1,
                child: backAwareShell,
              ),
            ),
          ),
          Positioned.fill(
            child:
                widget.playerRouteBuilder?.call(args) ??
                PlayerScreen(
                  key: ValueKey(_playerSessionId),
                  args: args,
                  orchestrator: orch,
                  isHandheld:
                      widget.deviceType == DeviceType.phone ||
                      widget.deviceType == DeviceType.tablet,
                  epgService: _appState.epgService,
                  xtreamService: _appState.xtreamService,
                  comskipSettings: _appState.comskipSettings,
                  hasDvrFeature: _appState.hasDvrFeature,
                  viewerId: viewerId,
                  viewSettingsService: _appState.viewSettingsService,
                  onNextChannel: args.type == 'live' ? _openNextChannel : null,
                  onPreviousChannel: args.type == 'live'
                      ? _openPreviousChannel
                      : null,
                  onReplaceItem: args.type == 'series'
                      ? _openPlayerDirect
                      : null,
                  onRecordProgram:
                      args.type == 'live' && _appState.hasDvrFeature
                      ? _handleRecordButtonTap
                      : null,
                  onTrackDialogVisibilityChanged: _setPlayerModalDialogVisible,
                  isRecordingCurrentChannel:
                      args.type == 'live' &&
                      recordingChannelIds.contains(args.streamId),
                  progressReporter: (progress) {
                    final aioLookupId = args.metadata['aio_item_id'] as String?;
                    final existing = _appState.progressList.firstWhereOrNull(
                      (p) =>
                          p.contentType == progress.contentType &&
                          (p.contentType == ContentType.aiostreams
                              ? p.aioItemId == aioLookupId
                              : p.streamId == progress.streamId),
                    );
                    final toSave = Progress(
                      viewerId: progress.viewerId,
                      contentType: progress.contentType,
                      streamId: progress.streamId,
                      positionSeconds: progress.positionSeconds,
                      durationSeconds:
                          progress.durationSeconds ?? existing?.durationSeconds,
                      completed: progress.completed,
                      seriesId: progress.seriesId ?? existing?.seriesId,
                      seasonNumber:
                          progress.seasonNumber ??
                          (args.metadata['season_number'] as int?) ??
                          existing?.seasonNumber,
                      episodeNumber:
                          progress.episodeNumber ??
                          (args.metadata['episode_number'] as int?) ??
                          existing?.episodeNumber,
                      title:
                          progress.title ??
                          args.metadata['title'] as String? ??
                          args.title,
                      episodeTitle:
                          progress.episodeTitle ??
                          args.metadata['episode_title'] as String? ??
                          existing?.episodeTitle,
                      seriesName:
                          progress.seriesName ??
                          args.metadata['series_name'] as String? ??
                          existing?.seriesName,
                      thumbnailUrl:
                          progress.thumbnailUrl ??
                          args.metadata['thumbnail_url'] as String? ??
                          existing?.thumbnailUrl,
                      backdropUrl:
                          progress.backdropUrl ??
                          args.metadata['backdrop_url'] as String? ??
                          existing?.backdropUrl,
                      rating:
                          progress.rating ??
                          args.metadata['rating'] as String? ??
                          existing?.rating,
                      runtime:
                          progress.runtime ??
                          args.metadata['duration'] as String? ??
                          existing?.runtime,
                      plot:
                          progress.plot ??
                          args.metadata['plot'] as String? ??
                          existing?.plot,
                      genre: progress.genre ?? existing?.genre,
                      year:
                          progress.year ??
                          args.metadata['year'] as String? ??
                          existing?.year,
                    );
                    final aioItemId = args.metadata['aio_item_id'] as String?;
                    final aioIntegrationId =
                        args.metadata['aio_integration_id'] as int?;
                    final aioToSave = aioItemId != null
                        ? Progress(
                            viewerId: toSave.viewerId,
                            contentType: ContentType.aiostreams,
                            streamId: 0,
                            positionSeconds: toSave.positionSeconds,
                            durationSeconds: toSave.durationSeconds,
                            completed: toSave.completed,
                            seasonNumber: toSave.seasonNumber,
                            episodeNumber: toSave.episodeNumber,
                            title: toSave.title,
                            episodeTitle: toSave.episodeTitle,
                            thumbnailUrl: toSave.thumbnailUrl,
                            backdropUrl: toSave.backdropUrl,
                            rating: toSave.rating,
                            runtime: toSave.runtime,
                            plot: toSave.plot,
                            genre: toSave.genre,
                            year: toSave.year,
                            aioItemId: aioItemId,
                            aioIntegrationId: aioIntegrationId,
                          )
                        : null;
                    if (aioToSave != null) {
                      if (_appState.sourceType == AppSourceType.xtream) {
                        unawaited(
                          _appState.xtreamService
                              .updateProgress(aioToSave)
                              .catchError((_) {}),
                        );
                      }
                      unawaited(
                        _appState.resumeService.save(aioToSave).then((_) {
                          if (mounted) {
                            _appState.updateProgressEntry(aioToSave);
                          }
                        }),
                      );
                    } else {
                      if (_appState.sourceType == AppSourceType.xtream) {
                        unawaited(
                          _appState.xtreamService
                              .updateProgress(toSave)
                              .catchError((_) {}),
                        );
                      }
                      unawaited(
                        _appState.resumeService.save(toSave).then((_) {
                          if (mounted) _appState.updateProgressEntry(toSave);
                        }),
                      );
                    }
                  },
                  traktService: _appState.traktService,
                  onPlaybackFailure: () {
                    if (!mounted) return;
                    setState(() => _playerHasFailed = true);
                    unawaited(_systemUiPolicy.applyBrowsing());
                  },
                  onClose: _closePlayer,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTvLayout(
    Widget contentShell,
    List<String> routes,
    int unreadCount,
  ) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 240 || constraints.maxHeight < 120) {
            return Scaffold(body: contentShell);
          }

          final macTitlebarInset = _isMacDesktopWindow
              ? _kMacTitlebarInset
              : 0.0;
          final fullScreenDetail = _fullScreenDetailActive;

          // The sidebar physically slides off-screen to the left and the
          // content pane's left edge animates out to meet it, both on the
          // same AnimatedPositioned duration/curve - timed to start the
          // instant `_pushDetail(..., fullScreen: true)` flips this state
          // (before the route push/pop even begins), so this motion and the
          // detail route's own slide transition (_slidePage in
          // go_router_config.dart) run concurrently as one movement instead
          // of a hard layout snap competing with an already-running page
          // transition.
          final sidebar = AnimatedPositioned(
            duration: _kFullScreenDetailTransition,
            curve: Curves.easeInOut,
            top: macTitlebarInset,
            // Clears the sidebar's widest (expanded, 200px) state regardless
            // of whether it was expanded or collapsed when hidden.
            left: fullScreenDetail ? -220 : 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: fullScreenDetail,
              child: NavigationSidebar(
                currentIndex: _currentIndex,
                routes: routes,
                sidebarActive: _sidebarActive,
                focusNodes: _sidebarFocusNodes,
                scopeNode: _sidebarScopeNode,
                unreadNotificationCount: unreadCount,
                onNavigate: _navigateTo,
                onActivateSidebar: _activateSidebar,
                onDeactivateSidebar: _deactivateSidebar,
              ),
            ),
          );

          final content = AnimatedPositioned(
            duration: _kFullScreenDetailTransition,
            curve: Curves.easeInOut,
            top: macTitlebarInset,
            left: fullScreenDetail ? 0 : 64,
            right: 0,
            bottom: 0,
            child: DpadRegion(
              memoryKey: 'content',
              horizontalEdge: DpadEdgeBehavior.stop,
              onEdge: (direction) {
                if (!fullScreenDetail && direction == TraversalDirection.left) {
                  _activateSidebar();
                }
              },
              child: contentShell,
            ),
          );

          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: DecoratedBox(decoration: kAppGradientBg),
                ),
                content,
                sidebar,
                if (_isMacDesktopWindow)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _kMacTitlebarInset,
                    child: DragToMoveArea(
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: const ColoredBox(
                            color: Color(0x8009090b),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileLayout(
    Widget contentShell,
    List<String> routes,
    int unreadCount,
  ) {
    final primaryCount = RouteNames.mobilePrimaryCount.clamp(
      0,
      routes.length,
    );
    final overflowRoutes = routes.skip(primaryCount).toList();
    final overflowUnread = overflowRoutes.contains(RouteNames.notifications)
        ? unreadCount
        : 0;
    final moreTabIndex = primaryCount;
    final displayedIndex = _currentIndex < primaryCount
        ? _currentIndex
        : moreTabIndex;

    return Scaffold(
      body: contentShell,
      bottomNavigationBar: _fullScreenDetailActive
          ? null
          : BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: displayedIndex,
              onTap: (index) => index == moreTabIndex
                  ? _showMoreSheet(overflowRoutes, primaryCount, unreadCount)
                  : _navigateTo(index),
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant,
              items: [
                ...routes.take(primaryCount).map((route) {
                  return BottomNavigationBarItem(
                    icon: Icon(_routeIcon(route)),
                    label: _routeLabel(context, route),
                  );
                }),
                if (overflowRoutes.isNotEmpty)
                  BottomNavigationBarItem(
                    icon: Badge(
                      isLabelVisible: overflowUnread > 0,
                      label: Text('$overflowUnread'),
                      child: const Icon(Icons.more_vert),
                    ),
                    label: AppLocalizations.of(context).navMore,
                  ),
              ],
            ),
    );
  }

  Future<void> _showMoreSheet(
    List<String> overflowRoutes,
    int primaryCount,
    int unreadCount,
  ) async {
    // Return the chosen index and navigate after the sheet is fully dismissed.
    // Calling _navigateTo synchronously inside ListTile.onTap while the sheet
    // is still in the overlay can cause a double interaction event on some
    // platforms (goBranch fires a route change mid-pop animation).
    final index = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < overflowRoutes.length; i++)
              ListTile(
                leading: Badge(
                  isLabelVisible:
                      overflowRoutes[i] == RouteNames.notifications &&
                      unreadCount > 0,
                  label: Text('$unreadCount'),
                  child: Icon(_routeIcon(overflowRoutes[i])),
                ),
                title: Text(_routeLabel(sheetContext, overflowRoutes[i])),
                selected: _currentIndex == primaryCount + i,
                onTap: () => Navigator.of(sheetContext).pop(primaryCount + i),
              ),
          ],
        ),
      ),
    );
    if (index != null && mounted) _navigateTo(index);
  }

  IconData _routeIcon(String route) => switch (route) {
    RouteNames.home => Icons.home,
    RouteNames.search => Icons.search,
    RouteNames.liveTv => Icons.live_tv,
    RouteNames.vod => Icons.movie,
    RouteNames.series => Icons.tv,
    RouteNames.aiostreams => Icons.subscriptions,
    RouteNames.dvr => Icons.video_library,
    RouteNames.requests => Icons.playlist_add,
    RouteNames.notifications => Icons.notifications,
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
          color: expanded ? theme.colorScheme.surface : Colors.transparent,
          boxShadow: expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(2, 0),
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
            return KeyEventResult.ignored;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 12),
              ...List.generate(routes.length, (index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: SidebarDestinationItem(
                    label: _routeLabel(context, routes[index]),
                    icon: _routeIcon(routes[index]),
                    selected: index == currentIndex,
                    expanded: expanded,
                    focusNode: focusNodes[index],
                    badgeCount: routes[index] == RouteNames.notifications
                        ? unreadNotificationCount
                        : 0,
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
    RouteNames.aiostreams => Icons.subscriptions,
    RouteNames.dvr => Icons.video_library,
    RouteNames.requests => Icons.playlist_add,
    RouteNames.notifications => Icons.notifications,
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

  void _setHovered(bool v) {
    if (_hovered == v) return;
    setState(() => _hovered = v);
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
    } else if (_focused || _hovered) {
      backgroundColor = colorScheme.surfaceContainerHigh;
      foregroundColor = colorScheme.onSurface;
    }

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
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: OverflowBox(
                  maxWidth: 200,
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
                          size: 24,
                        ),
                      ),
                      if (widget.expanded) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            widget.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: foregroundColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: (_focused || _hovered) && !widget.selected
                        ? 1.0
                        : 0.0,
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

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCallout(message: message, variant: AppCalloutVariant.error);
  }
}

class _HomeScreen extends ConsumerStatefulWidget {
  const _HomeScreen({
    required this.onChannelSelect,
    this.onChannelContextChanged,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    required this.onContinueWatchingMore,
    required this.onRecordingsSelect,
    required this.onAioStreamsItemSelect,
    this.useSidebarLayout = false,
    this.onSidebarActivate,
  });

  final void Function(Channel) onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;
  final VoidCallback onContinueWatchingMore;
  final VoidCallback onRecordingsSelect;
  final void Function(AIOStreamsItem, int integrationId) onAioStreamsItemSelect;
  final bool useSidebarLayout;
  final VoidCallback? onSidebarActivate;

  @override
  ConsumerState<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<_HomeScreen> {
  Set<int> _favoriteChannelIds = {};
  Set<int> _favoriteVodIds = {};
  Set<int> _favoriteSeriesIds = {};

  late final FavoritesService _liveFavoritesService;
  late final FavoritesService _vodFavoritesService;
  late final FavoritesService _seriesFavoritesService;

  @override
  void initState() {
    super.initState();
    _liveFavoritesService = ref.read(liveFavoritesServiceProvider);
    _vodFavoritesService = ref.read(vodFavoritesServiceProvider);
    _seriesFavoritesService = ref.read(seriesFavoritesServiceProvider);
    _liveFavoritesService.addListener(_onChannelFavoritesChanged);
    unawaited(_loadFavorites());
  }

  @override
  void dispose() {
    _liveFavoritesService.removeListener(_onChannelFavoritesChanged);
    super.dispose();
  }

  void _onChannelFavoritesChanged() {
    unawaited(_loadChannelFavorites());
  }

  Future<void> _loadChannelFavorites() async {
    final ids = await _liveFavoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = ids);
  }

  Future<void> _loadFavorites() async {
    final live = await _liveFavoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = live);
    final vod = await _vodFavoritesService.all();
    if (mounted) setState(() => _favoriteVodIds = vod);
    final series = await _seriesFavoritesService.all();
    if (mounted) setState(() => _favoriteSeriesIds = series);
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final progressList = ref.watch(progressListProvider);
    final channels = ref.watch(liveChannelsProvider);
    final vodItems = ref.watch(vodItemsProvider);
    final seriesList = ref.watch(seriesListProvider);
    final epgService = ref.watch(epgServiceProvider);
    final dvrRecordings = ref.watch(dvrRecordingsProvider);
    final sourceError = ref.watch(sourceErrorProvider);
    final hasDvrFeature = ref.watch(hasDvrFeatureProvider);

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            AppLocalizations.of(context).appNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final l = AppLocalizations.of(context);
    final continueWatchingItems = continueWatchingPreviewItems(
      context,
      progressList: progressList,
      vodItems: vodItems,
      seriesList: seriesList,
      onProgressSelect: widget.onProgressSelect,
    );
    const continueWatchingRowLimit = 4;
    final continueWatchingOverflow =
        continueWatchingItems.length - continueWatchingRowLimit;
    final continueWatchingRowItems = [
      ...continueWatchingItems.take(continueWatchingRowLimit),
      if (continueWatchingOverflow > 0)
        MediaPreviewItem(
          title: l.homeContinueWatchingSeeAll,
          subtitle: l.homeContinueWatchingMoreCount(continueWatchingOverflow),
          fallbackIcon: Icons.history,
          onTap: widget.onContinueWatchingMore,
        ),
    ];
    final continueWatchingSection = MediaPreviewSection(
      title: l.homeContinueWatching,
      titleIcon: Icons.history,
      emptyLabel: l.homeNoContinueWatching,
      items: continueWatchingRowItems,
      landscapeStyle: true,
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
    final favoriteChannels = channels
        .where((channel) => _favoriteChannelIds.contains(channel.id))
        .toList(growable: false);
    final liveSectionChannels = favoriteChannels.isEmpty
        ? channels
        : favoriteChannels;
    MediaPreviewItem liveChannelItem(Channel channel) => MediaPreviewItem(
      title: channel.name,
      imageUrl: channel.logoUrl,
      subtitle:
          epgService.lookupForChannel(channel)?.current.displayTitle ??
          channel.groupTitle ??
          l.homeLiveChannel,
      fallbackIcon: Icons.live_tv,
      imageFit: BoxFit.contain,
      imagePadding: const EdgeInsets.all(10),
      imageBackgroundColor: Colors.transparent,
      isFavorite: _favoriteChannelIds.contains(channel.id),
      onTap: () {
        widget.onChannelContextChanged?.call(liveSectionChannels);
        widget.onChannelSelect(channel);
      },
      onLongTap: () async {
        await _liveFavoritesService.toggle(channel.id);
        await _loadFavorites();
      },
    );

    final liveSection = MediaPreviewSection(
      title: favoriteChannels.isEmpty ? l.navLiveTv : l.homeFavoriteChannels,
      titleIcon: favoriteChannels.isEmpty ? Icons.live_tv : Icons.star,
      emptyLabel: l.homeNoLiveTv,
      items: liveSectionChannels.map(liveChannelItem).toList(growable: false),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
    final moviesSection = MediaPreviewSection(
      title: l.navVod,
      titleIcon: Icons.movie,
      emptyLabel: l.homeNoMovies,
      posterStyle: true,
      items: vodItems
          .map(
            (item) => MediaPreviewItem(
              title: item.name,
              imageUrl: item.logoUrl,
              subtitle: item.rating == null ? l.homeMovie : '★ ${item.rating}',
              fallbackIcon: Icons.movie,
              fallbackTitle: item.name,
              isFavorite: _favoriteVodIds.contains(item.id),
              onTap: () => widget.onVodSelect(item),
              onLongTap: () async {
                await _vodFavoritesService.toggle(item.id);
                await _loadFavorites();
              },
            ),
          )
          .toList(growable: false),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
    final seriesSection = MediaPreviewSection(
      title: l.navSeries,
      titleIcon: Icons.tv,
      emptyLabel: l.homeNoSeries,
      posterStyle: true,
      items: seriesList
          .map(
            (series) => MediaPreviewItem(
              title: series.name,
              imageUrl: series.coverUrl,
              subtitle: series.rating == null
                  ? l.navSeries
                  : '★ ${series.rating}',
              fallbackIcon: Icons.tv,
              fallbackTitle: series.name,
              isFavorite: _favoriteSeriesIds.contains(series.id),
              onTap: () => widget.onSeriesSelect(series),
              onLongTap: () async {
                await _seriesFavoritesService.toggle(series.id);
                await _loadFavorites();
              },
            ),
          )
          .toList(growable: false),
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
    final recordingsSection = MediaPreviewSection(
      title: 'DVR',
      titleIcon: Icons.video_library,
      emptyLabel: 'No DVR recordings available',
      items: [
        MediaPreviewItem(
          title: 'DVR Recordings',
          subtitle: dvrRecordings.isEmpty
              ? 'Browse completed and in-progress recordings'
              : '${dvrRecordings.length} recordings',
          fallbackIcon: Icons.video_library,
          onTap: () => widget.onRecordingsSelect(),
        ),
      ],
      useSidebarLayout: widget.useSidebarLayout,
      onSidebarActivate: widget.onSidebarActivate,
    );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        children: [
          if (sourceError != null && sourceError.isNotEmpty) ...[
            _OfflineBanner(message: sourceError),
            const SizedBox(height: MediaBrowsingMetrics.pagePadding),
          ],
          if (continueWatchingItems.isNotEmpty) continueWatchingSection,
          liveSection,
          moviesSection,
          seriesSection,
          if (hasDvrFeature) recordingsSection,
        ],
      ),
    );
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
