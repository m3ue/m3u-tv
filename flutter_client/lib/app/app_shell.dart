import 'dart:async';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
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
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_progress_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Device type enum matching the RN useDeviceType hook.
enum DeviceType { tv, desktop, tablet, phone }

/// Whether a device type should use sidebar navigation.
bool shouldUseSidebar(DeviceType deviceType) =>
    deviceType == DeviceType.tv || deviceType == DeviceType.desktop;

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
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.deviceType,
    this.appState,
    this.playbackOrchestratorBuilder,
    this.playerRouteBuilder,
  });

  final StatefulNavigationShell navigationShell;
  final DeviceType deviceType;
  final AppStateController? appState;
  final PlaybackOrchestrator Function()? playbackOrchestratorBuilder;
  final Widget Function(PlayerArgs args)? playerRouteBuilder;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> with WidgetsBindingObserver {
  bool _sidebarActive = false;
  late final AppStateController _appState;
  late final bool _ownsAppState;

  DateTime? _lastBackPress;
  int _lastNavMs = 0;
  int _lastNavIndex = -1;
  StreamSubscription<TvNotificationItem>? _tvNotificationSub;

  PlayerArgs? _playerArgs;
  PlaybackOrchestrator? _playerOrchestrator;
  FocusNode? _focusBeforePlayer;

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
    _appState.addListener(_onAppStateChanged);
    _tvNotificationSub = _appState.tvNotifications.listen(_onTvNotification);
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
      return false;
    }
    _lastBackPress = now;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).appBackToExit),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    return true;
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _syncSidebarFocusNodes();
    final route = RouteNames.mainRoutes[widget.navigationShell.currentIndex];
    if (!_mainRoutes.contains(route)) {
      widget.navigationShell.goBranch(0, initialLocation: true);
    }
    setState(() {});
  }

  void _initSidebarFocusNodes() {
    _syncSidebarFocusNodes();
  }

  void _syncSidebarFocusNodes() {
    while (_sidebarFocusNodes.length < _mainRoutes.length) {
      _sidebarFocusNodes.add(FocusNode());
    }
    while (_sidebarFocusNodes.length > _mainRoutes.length) {
      _sidebarFocusNodes.removeLast().dispose();
    }
  }

  void _onTvNotification(TvNotificationItem item) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.body != null && item.body!.isNotEmpty
              ? '${item.title}: ${item.body}'
              : item.title,
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  void dispose() {
    _tvNotificationSub?.cancel().ignore();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // immersiveSticky is reset by the OS on background/foreground transitions;
    // re-apply it each time the app resumes to keep the layout full-screen.
    if (state == AppLifecycleState.resumed && !kIsWeb && Platform.isAndroid) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
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

  // Stable method tearoff passed to ContentActions.onOpenPlayer.
  // Must NOT be a local closure in build() — closures are always new instances,
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

    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return true;
    }

    if (shouldUseSidebar(widget.deviceType) && !_sidebarActive) {
      _activateSidebar();
      return true;
    }

    return false;
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
          title: '${channel.name} - ${program.title}',
          type: 'catchup',
          streamId: channel.id,
          startPosition: 0,
          epgChannelId: channel.epgChannelId ?? channel.tvgName ?? channel.name,
          headers: channel.headers,
          metadata: <String, Object?>{
            'catchup': true,
            'program_title': program.title,
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
  ) async {
    try {
      await _appState.scheduleDvr(channel, program);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).appRecordingScheduled(program.title),
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).appRecordingFailed(error.toString()),
          ),
        ),
      );
    }
  }

  Future<void> _pushDetail(String path, {Object? extra}) async {
    await Future<void>.microtask(() {});
    final savedFocus = FocusManager.instance.primaryFocus;
    // ignore: use_build_context_synchronously
    await context.push(path, extra: extra);
    if (mounted) {
      if (savedFocus != null && savedFocus.canRequestFocus) {
        savedFocus.requestFocus();
      } else {
        _contentFocusNode.requestFocus();
      }
    }
  }

  void _openVod(VodItem item) {
    unawaited(_pushDetail(RouteNames.vodDetailsFor(item.id), extra: item));
  }

  void _openSeries(Series series) {
    unawaited(
      _pushDetail(RouteNames.seriesDetailsFor(series.id), extra: series),
    );
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
    return ListenableBuilder(
      listenable: _appState,
      builder: (context, _) {
        if (_appState.isBootstrapping) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return switch (routeName) {
          RouteNames.home => _HomeScreen(
            appState: _appState,
            onChannelSelect: _openChannel,
            onVodSelect: _openVod,
            onSeriesSelect: _openSeries,
            onProgressSelect: _openProgress,
            onRecordingsSelect: () => _navigateToRoute(RouteNames.dvr),
            onAioStreamsItemSelect: (item, integrationId) => unawaited(
              _pushDetail(
                RouteNames.aiostreamsDetailsFor(
                  integrationId,
                  item.type,
                  item.id,
                ),
                extra: item,
              ),
            ),
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.search => SearchScreen(
            channels: _appState.channels,
            vodItems: _appState.vodItems,
            seriesList: _appState.seriesList,
            isConfigured: _appState.isConfigured,
            onChannelSelect: _openChannel,
            onVodSelect: _openVod,
            onSeriesSelect: _openSeries,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.liveTv => LiveTvScreen(
            channels: _appState.channels,
            categories: _appState.liveCategories,
            isLoading: _appState.isLoadingContent,
            isConfigured: _appState.isConfigured,
            favoritesService: _appState.favoritesService,
            epgService: _appState.epgService,
            onChannelSelect: _openChannel,
            onCatchupProgramSelect: _openCatchupProgram,
            onSidebarActivate: _activateSidebar,
            onScheduleProgram: (channel, program) =>
                unawaited(_scheduleDvr(context, channel, program)),
          ),
          RouteNames.vod => VodScreen(
            vodItems: _appState.vodItems,
            categories: _appState.vodCategories,
            isLoading: _appState.isLoadingContent,
            isConfigured: _appState.isConfigured,
            onVodSelect: _openVod,
            favoritesService: _appState.vodFavoritesService,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.series => SeriesScreen(
            seriesList: _appState.seriesList,
            categories: _appState.seriesCategories,
            isLoading: _appState.isLoadingContent,
            isConfigured: _appState.isConfigured,
            onSeriesSelect: _openSeries,
            favoritesService: _appState.seriesFavoritesService,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.aiostreams => AIOStreamsHomeScreen(
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
              ),
            ),
            favoritesService: _appState.aioFavoritesService,
            progressService: _appState.aioProgressService,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.dvr => DvrRecordingsScreen(
            recordings: _appState.dvrRecordings,
            isLoading: _appState.isLoadingContent,
            isConfigured: _appState.isConfigured,
            onPlay: _openPlayerDirect,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.requests => RequestScreen(
            isConfigured: _appState.isConfigured,
            onSidebarActivate: _activateSidebar,
          ),
          RouteNames.notifications => NotificationsScreen(appState: _appState),
          RouteNames.settings => SettingsScreen(
            authNotifier: _appState.authNotifier,
            activeViewer: _appState.activeViewer,
            viewers: _appState.viewers,
            sourceLabel: _appState.sourceLabel,
            sourceError: _appState.error,
            isConfiguredOverride: _appState.isConfigured,
            epgRefreshInterval: _appState.epgRefreshInterval,
            epgRefreshOptions: AppStateController.epgRefreshOptions,
            traktService: _appState.traktService,
            onConnect: _appState.connectXtream,
            onDisconnect: () => unawaited(_appState.disconnect()),
            onSwitchViewer: (viewer) =>
                unawaited(_appState.switchViewer(viewer)),
            onCreateViewer: _appState.createViewer,
            onClearCache: () => unawaited(_appState.clearAndRefresh()),
            onEpgIntervalChanged: (d) =>
                unawaited(_appState.setEpgRefreshInterval(d)),
            onConnected: () => _navigateTo(0),
            locale: _appState.locale,
            onLocaleChanged: (locale) => unawaited(_appState.setLocale(locale)),
          ),
          _ => const PlaceholderScreen(title: 'Home'),
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
          _BackIntent: _BackAction(_handleBackPress),
          _MenuIntent: _MenuAction(_activateSidebar),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
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
              ? _buildTvLayout(contentShell)
              : _buildMobileLayout(contentShell),
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
                  final existing = _appState.progressList.firstWhereOrNull(
                    (p) =>
                        p.contentType == progress.contentType &&
                        p.streamId == progress.streamId,
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
                        progress.seasonNumber ?? existing?.seasonNumber,
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
                    plot: progress.plot ?? existing?.plot,
                    genre: progress.genre ?? existing?.genre,
                    year: progress.year ?? existing?.year,
                  );
                  final aioItemId = args.metadata['aio_item_id'] as String?;
                  if (aioItemId != null) {
                    final aioItem = AIOStreamsProgressItem(
                      itemId: aioItemId,
                      type: args.type,
                      name: toSave.title ?? args.title,
                      integrationId:
                          (args.metadata['aio_integration_id'] as int?) ?? 0,
                      positionSeconds: toSave.positionSeconds,
                      durationSeconds: toSave.durationSeconds,
                      poster: toSave.thumbnailUrl,
                      lastWatched: DateTime.now(),
                    );
                    _appState.aioProgressService.updateEntry(aioItem);
                    unawaited(
                      _appState.aiostreamsApiService
                          .saveProgress(
                            integrationId: aioItem.integrationId,
                            itemId: aioItem.itemId,
                            itemType: aioItem.type,
                            name: aioItem.name,
                            positionSeconds: aioItem.positionSeconds,
                            durationSeconds: aioItem.durationSeconds,
                            posterUrl: aioItem.poster,
                          )
                          .catchError((_) => null),
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
                onClose: _closePlayer,
              ),
        ),
      ],
    );
  }

  Widget _buildTvLayout(Widget contentShell) {
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

          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
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
                      child: contentShell,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  bottom: 0,
                  child: NavigationSidebar(
                    currentIndex: _currentIndex,
                    routes: _mainRoutes,
                    sidebarActive: _sidebarActive,
                    focusNodes: _sidebarFocusNodes,
                    scopeNode: _sidebarScopeNode,
                    unreadNotificationCount: _appState.unreadNotificationCount,
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

  Widget _buildMobileLayout(Widget contentShell) {
    final primaryCount = RouteNames.mobilePrimaryCount.clamp(
      0,
      _mainRoutes.length,
    );
    final overflowRoutes = _mainRoutes.skip(primaryCount).toList();
    final overflowUnread = overflowRoutes.contains(RouteNames.notifications)
        ? _appState.unreadNotificationCount
        : 0;
    final moreTabIndex = primaryCount;
    final displayedIndex = _currentIndex < primaryCount
        ? _currentIndex
        : moreTabIndex;

    return Scaffold(
      body: SafeArea(bottom: false, child: contentShell),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: displayedIndex,
        onTap: (index) => index == moreTabIndex
            ? _showMoreSheet(overflowRoutes, primaryCount)
            : _navigateTo(index),
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
        items: [
          ..._mainRoutes.take(primaryCount).map((route) {
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
                      _appState.unreadNotificationCount > 0,
                  label: Text('${_appState.unreadNotificationCount}'),
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
          color: theme.colorScheme.surfaceContainerHigh,
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
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.cloud_off, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen({
    required this.appState,
    required this.onChannelSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    required this.onRecordingsSelect,
    required this.onAioStreamsItemSelect,
    this.onSidebarActivate,
  });

  final AppStateController appState;
  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;
  final VoidCallback onRecordingsSelect;
  final void Function(AIOStreamsItem, int integrationId) onAioStreamsItemSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  Set<int> _favoriteChannelIds = {};
  Set<int> _favoriteVodIds = {};
  Set<int> _favoriteSeriesIds = {};

  @override
  void initState() {
    super.initState();
    widget.appState.favoritesService.addListener(_onChannelFavoritesChanged);
    unawaited(_loadFavorites());
  }

  @override
  void dispose() {
    widget.appState.favoritesService.removeListener(_onChannelFavoritesChanged);
    super.dispose();
  }

  void _onChannelFavoritesChanged() {
    unawaited(_loadChannelFavorites());
  }

  Future<void> _loadChannelFavorites() async {
    final ids = await widget.appState.favoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = ids);
  }

  Future<void> _loadFavorites() async {
    final appState = widget.appState;
    final channels = await appState.favoritesService.all();
    if (mounted) setState(() => _favoriteChannelIds = channels);
    final vod = await appState.vodFavoritesService.all();
    if (mounted) setState(() => _favoriteVodIds = vod);
    final series = await appState.seriesFavoritesService.all();
    if (mounted) setState(() => _favoriteSeriesIds = series);
  }

  @override
  Widget build(BuildContext context) {
    final appState = widget.appState;
    if (!appState.isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(AppLocalizations.of(context).appNotConfigured),
        ),
      );
    }

    final l = AppLocalizations.of(context);
    final continueWatchingItems = appState.progressList
        .where(_isResumeEligible)
        .map(_resumePreviewItem)
        .whereType<MediaPreviewItem>()
        .toList(growable: false);
    final continueWatchingSection = MediaPreviewSection(
      title: l.homeContinueWatching,
      emptyLabel: l.homeNoContinueWatching,
      items: continueWatchingItems,
      landscapeStyle: true,
      onSidebarActivate: widget.onSidebarActivate,
    );
    MediaPreviewItem liveChannelItem(Channel channel) => MediaPreviewItem(
      title: channel.name,
      imageUrl: channel.logoUrl,
      subtitle:
          appState.epgService.lookupForChannel(channel)?.current.title ??
          channel.groupTitle ??
          l.homeLiveChannel,
      fallbackIcon: Icons.live_tv,
      imageFit: BoxFit.contain,
      imagePadding: const EdgeInsets.all(10),
      imageBackgroundColor: Colors.transparent,
      isFavorite: _favoriteChannelIds.contains(channel.id),
      onTap: () => widget.onChannelSelect(channel),
      onLongTap: () async {
        await appState.favoritesService.toggle(channel.id);
        await _loadFavorites();
      },
    );

    final favoriteChannels = appState.channels
        .where((channel) => _favoriteChannelIds.contains(channel.id))
        .toList(growable: false);
    final liveSection = MediaPreviewSection(
      title: favoriteChannels.isEmpty ? l.navLiveTv : l.homeFavoriteChannels,
      emptyLabel: l.homeNoLiveTv,
      items: (favoriteChannels.isEmpty ? appState.channels : favoriteChannels)
          .map(liveChannelItem)
          .toList(growable: false),
      onSidebarActivate: widget.onSidebarActivate,
    );
    final moviesSection = MediaPreviewSection(
      title: l.navVod,
      emptyLabel: l.homeNoMovies,
      posterStyle: true,
      items: appState.vodItems
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
                await appState.vodFavoritesService.toggle(item.id);
                await _loadFavorites();
              },
            ),
          )
          .toList(growable: false),
      onSidebarActivate: widget.onSidebarActivate,
    );
    final seriesSection = MediaPreviewSection(
      title: l.navSeries,
      emptyLabel: l.homeNoSeries,
      posterStyle: true,
      items: appState.seriesList
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
                await appState.seriesFavoritesService.toggle(series.id);
                await _loadFavorites();
              },
            ),
          )
          .toList(growable: false),
      onSidebarActivate: widget.onSidebarActivate,
    );
    final recordingsSection = MediaPreviewSection(
      title: 'DVR',
      emptyLabel: 'No DVR recordings available',
      items: [
        MediaPreviewItem(
          title: 'DVR Recordings',
          subtitle: appState.dvrRecordings.isEmpty
              ? 'Browse completed and in-progress recordings'
              : '${appState.dvrRecordings.length} recordings',
          fallbackIcon: Icons.video_library,
          onTap: () => widget.onRecordingsSelect(),
        ),
      ],
      onSidebarActivate: widget.onSidebarActivate,
    );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        children: [
          Text(
            AppLocalizations.of(context).navHome,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          Text(l.homeConnectedSource(appState.sourceLabel)),
          if (appState.error != null && appState.error!.isNotEmpty) ...[
            const SizedBox(height: MediaBrowsingMetrics.chipGap),
            _OfflineBanner(message: appState.error!),
          ],
          const SizedBox(height: MediaBrowsingMetrics.pagePadding),
          if (continueWatchingItems.isNotEmpty) continueWatchingSection,
          liveSection,
          moviesSection,
          seriesSection,
          if (appState.hasAioStreams)
            for (final integration in appState.aiostreamsIntegrations)
              for (final catalog in integration.catalogs)
                AIOStreamsCatalogRow(
                  catalog: catalog,
                  integrationId: integration.id,
                  apiService: appState.aiostreamsApiService,
                  onItemSelect: (item) =>
                      widget.onAioStreamsItemSelect(item, integration.id),
                  onSidebarActivate: widget.onSidebarActivate,
                ),
          if (appState.hasDvrFeature) recordingsSection,
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
      if (progress.title != null) {
        final hasBackdrop = progress.backdropUrl != null;
        final fraction =
            (progress.durationSeconds != null && progress.durationSeconds! > 0)
            ? (progress.positionSeconds / progress.durationSeconds!).clamp(
                0.0,
                1.0,
              )
            : null;
        final plot = progress.plot;
        final subtitle = plot != null
            ? (plot.length > 120 ? '${plot.substring(0, 117)}…' : plot)
            : null;
        final vodFallbackLogo = (!hasBackdrop && progress.thumbnailUrl == null)
            ? widget.appState.vodItems
                  .firstWhereOrNull((v) => v.id == progress.streamId)
                  ?.logoUrl
            : null;
        return MediaPreviewItem(
          title: progress.title!,
          subtitle: subtitle,
          imageUrl:
              progress.backdropUrl ?? progress.thumbnailUrl ?? vodFallbackLogo,
          fallbackIcon: Icons.movie,
          imageFit: hasBackdrop ? BoxFit.cover : BoxFit.contain,
          imageBackgroundColor: hasBackdrop ? null : Colors.black,
          fallbackTitle: progress.title,
          progressFraction: fraction,
          overlayLabel: progress.year,
          overlayBadges: <String>[
            if (progress.rating != null) '★ ${progress.rating}',
            if (progress.runtime != null) progress.runtime!,
          ],
          onTap: () => widget.onProgressSelect(progress),
        );
      }
      final item = widget.appState.vodItems.firstWhereOrNull(
        (item) => item.id == progress.streamId,
      );
      if (item == null) return null;
      final fraction =
          (progress.durationSeconds != null && progress.durationSeconds! > 0)
          ? (progress.positionSeconds / progress.durationSeconds!).clamp(
              0.0,
              1.0,
            )
          : null;
      return MediaPreviewItem(
        title: item.name,
        imageUrl: item.logoUrl,
        fallbackIcon: Icons.movie,
        imageFit: BoxFit.contain,
        imageBackgroundColor: Colors.black,
        fallbackTitle: item.name,
        progressFraction: fraction,
        overlayBadges: <String>[
          if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
        ],
        onTap: () => widget.onProgressSelect(progress),
      );
    }

    if (progress.contentType == ContentType.episode) {
      if (progress.seriesId != null &&
          (progress.seriesName != null || progress.title != null)) {
        final displayTitle = progress.seriesName ?? progress.title!;
        final fraction =
            (progress.durationSeconds != null && progress.durationSeconds! > 0)
            ? (progress.positionSeconds / progress.durationSeconds!).clamp(
                0.0,
                1.0,
              )
            : null;
        final episodeSubtitle =
            progress.episodeTitle ??
            (progress.seasonNumber != null
                ? 'Season ${progress.seasonNumber}'
                : null);
        final seriesFallback = widget.appState.seriesList.firstWhereOrNull(
          (s) => s.id == progress.seriesId,
        );
        return MediaPreviewItem(
          title: displayTitle,
          subtitle: episodeSubtitle,
          imageUrl:
              progress.thumbnailUrl ??
              progress.backdropUrl ??
              seriesFallback?.backdropUrl ??
              seriesFallback?.coverUrl,
          fallbackIcon: Icons.tv,
          fallbackTitle: displayTitle,
          progressFraction: fraction,
          overlayLabel: progress.seasonNumber != null
              ? 'S${progress.seasonNumber}${progress.episodeNumber != null ? ' E${progress.episodeNumber}' : ''}'
              : null,
          overlayBadges: <String>[
            if (progress.rating != null) '★ ${progress.rating}',
            if (progress.runtime != null) progress.runtime!,
          ],
          onTap: () => widget.onProgressSelect(progress),
        );
      }
      if (progress.seriesId != null) {
        final series = widget.appState.seriesList.firstWhereOrNull(
          (series) => series.id == progress.seriesId,
        );
        if (series == null) return null;
        return MediaPreviewItem(
          title: series.name,
          imageUrl: series.backdropUrl ?? series.coverUrl,
          subtitle: progress.seasonNumber != null
              ? AppLocalizations.of(context).homeSeason(progress.seasonNumber!)
              : AppLocalizations.of(context).navSeries,
          fallbackIcon: Icons.tv,
          fallbackTitle: series.name,
          onTap: () => widget.onProgressSelect(progress),
        );
      }
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
