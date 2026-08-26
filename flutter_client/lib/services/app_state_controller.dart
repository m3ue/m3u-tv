import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart' show Locale;

import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';

enum AppSourceType { none, xtream }

/// Which content lists need to be re-fetched after a DVR recording finishes
/// post-processing so its upserted VOD/episode surfaces in the UI. Private
/// to this file — only the debounce/coalesce machinery in [AppStateController]
/// reasons about it.
enum _DvrContentRefreshTarget { vod, series }

typedef MediaRequestOwner = ({
  int sourceGeneration,
  int notificationGeneration,
  AppSourceType sourceType,
  UserCredentials? credentials,
});

/// Per-episode outcome from [AppStateController.scheduleDvrAirings]. One
/// entry per input episode, in input order. Per-item failures (e.g.
/// `XtreamDvrScheduleException` for the 422 concurrent recording limit case)
/// land here instead of aborting the rest of the batch.
class DvrAiringScheduleResult {
  const DvrAiringScheduleResult({
    required this.episode,
    required this.success,
    this.errorMessage,
  });

  final EpgShowEpisode episode;
  final bool success;

  /// Server-side error message when [success] is false. Null on success.
  final String? errorMessage;
}

class AppStateController extends ChangeNotifier {
  factory AppStateController({
    AuthNotifier? authNotifier,
    XtreamService? xtreamService,
    SecureStorage? secureStorage,
    CacheService? cacheService,
    FavoritesService? favoritesService,
    FavoritesService? vodFavoritesService,
    FavoritesService? seriesFavoritesService,
    ResumeService? resumeService,
    ViewerService? viewerService,
    EpgService? epgService,
    PersistentJsonStore? persistentStore,
    PersistentJsonStore? cacheStore,
    TvNotificationService? tvNotificationService,
    TvNotificationStore? tvNotificationStore,
    ReverbService? reverbService,
    AIOStreamsFavoritesService? aioFavoritesService,
    ProxyPlaybackSettings? proxyPlaybackSettings,
    ComskipSettings? comskipSettings,
    PushNotificationService? pushNotificationService,
    DevicePairingService? devicePairingService,
    ViewSettingsService? viewSettingsService,
  }) {
    final store = persistentStore ?? PersistentJsonStore();
    final resolvedSecureStorage =
        secureStorage ?? FileSecureStorage(store: store);
    // The content cache (whole channel/VOD/series catalog) lives in its own
    // file on the production path so a small single-key write elsewhere -
    // e.g. the resume tracker every ~10s during playback - never has to
    // re-serialize it. When a caller supplies its own store or cacheService
    // (tests), keep everything in the one file so their assertions hold.
    final resolvedCacheStore =
        cacheStore ??
        (persistentStore == null && cacheService == null
            ? PersistentJsonStore(fileName: 'cache.json')
            : store);
    final resolvedCacheService =
        cacheService ?? CacheService(store: resolvedCacheStore);
    final resolvedXtreamService =
        xtreamService ??
        authNotifier?.xtreamService ??
        XtreamService(cache: resolvedCacheService);
    return AppStateController._(
      authNotifier:
          authNotifier ??
          AuthNotifier(
            xtreamService: resolvedXtreamService,
            secureStorage: resolvedSecureStorage,
          ),
      xtreamService: resolvedXtreamService,
      secureStorage: resolvedSecureStorage,
      cacheService: resolvedCacheService,
      appStateStore: store,
      cacheStore: resolvedCacheStore,
      favoritesService: favoritesService ?? FavoritesService(store: store),
      vodFavoritesService:
          vodFavoritesService ??
          FavoritesService(store: store, namespace: 'vod'),
      seriesFavoritesService:
          seriesFavoritesService ??
          FavoritesService(store: store, namespace: 'series'),
      resumeService: resumeService ?? ResumeService(store: store),
      viewerService: viewerService ?? ViewerService(store: store),
      epgService: epgService ?? EpgService(),
      traktService: TraktService(storage: resolvedSecureStorage),
      devicePairingService: devicePairingService ?? DevicePairingService(),
      tvNotificationService: tvNotificationService ?? TvNotificationService(),
      notificationStore:
          tvNotificationStore ?? TvNotificationStore(store: store),
      reverbService: reverbService ?? ReverbService(),
      aioFavoritesService:
          aioFavoritesService ?? AIOStreamsFavoritesService(store: store),
      proxyPlaybackSettings:
          proxyPlaybackSettings ?? ProxyPlaybackSettings(store: store),
      comskipSettings: comskipSettings ?? ComskipSettings(store: store),
      pushNotificationService:
          pushNotificationService ?? PushNotificationService(),
      viewSettingsService:
          viewSettingsService ?? ViewSettingsService(store: store),
    );
  }

  AppStateController._({
    required this.authNotifier,
    required this.xtreamService,
    required this.secureStorage,
    required this.cacheService,
    required this._appStateStore,
    required this._cacheStore,
    required this.favoritesService,
    required this.vodFavoritesService,
    required this.seriesFavoritesService,
    required this.resumeService,
    required this.viewerService,
    required this.epgService,
    required this.traktService,
    required this.devicePairingService,
    required this._tvNotificationService,
    required this.notificationStore,
    required this._reverbService,
    required this.aioFavoritesService,
    required this.proxyPlaybackSettings,
    required this.comskipSettings,
    required this._pushNotificationService,
    required this.viewSettingsService,
  }) {
    epgService.cacheTtl = cacheService.refreshInterval;
    favoritesService.onChanged = (streamId, {required favorited}) =>
        _pushFavoriteChange('live', streamId, favorited: favorited);
    vodFavoritesService.onChanged = (streamId, {required favorited}) =>
        _pushFavoriteChange('vod', streamId, favorited: favorited);
    seriesFavoritesService.onChanged = (streamId, {required favorited}) =>
        _pushFavoriteChange('series', streamId, favorited: favorited);
    favoritesService.captureMutationOwnership =
        _captureFavoriteMutationOwnership;
    vodFavoritesService.captureMutationOwnership =
        _captureFavoriteMutationOwnership;
    seriesFavoritesService.captureMutationOwnership =
        _captureFavoriteMutationOwnership;
    aioFavoritesService.captureMutationOwnership =
        _captureAioFavoriteMutationOwnership;
    aioFavoritesService.onAdded = _pushAioFavoriteAdded;
    aioFavoritesService.onRemoved = _pushAioFavoriteRemoved;
  }

  static const _sourceKey = 'm3ue_tv_source';
  static const _epgIntervalKey = 'm3ue_tv_epg_interval_minutes';
  static const _localeKey = 'm3ue_tv_locale';
  static const _favoritesMigratedKey = 'm3ue_tv_favorites_migrated_viewers';

  static const List<Duration> epgRefreshOptions = <Duration>[
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 6),
  ];

  final AuthNotifier authNotifier;
  final XtreamService xtreamService;

  /// The app-state file (credentials, settings, favorites, resume progress)
  /// and the content-cache file. Equal when a test forces a single store; a
  /// one-time key migration between them runs in [boot].
  final PersistentJsonStore _appStateStore;
  final PersistentJsonStore _cacheStore;
  final SecureStorage secureStorage;
  final CacheService cacheService;
  final FavoritesService favoritesService;
  final FavoritesService vodFavoritesService;
  final FavoritesService seriesFavoritesService;
  final ResumeService resumeService;
  final AIOStreamsFavoritesService aioFavoritesService;
  final ProxyPlaybackSettings proxyPlaybackSettings;
  final ComskipSettings comskipSettings;
  final ViewSettingsService viewSettingsService;
  final TvNotificationService _tvNotificationService;
  final TvNotificationStore notificationStore;
  final ReverbService _reverbService;
  final PushNotificationService _pushNotificationService;
  String? _pushToken;
  bool _pushRegistrationSuspended = false;
  UserCredentials? _registeredPushCredentials;
  String? _registeredPushToken;
  final SerialQueue _pushLifecycleQueue = SerialQueue();
  final Generation _pushLifecycleGeneration = Generation();
  Future<void>? _pushInitialization;
  StreamSubscription<String>? _pushTokenSubscription;
  final Set<String> _pendingNotificationActivations = <String>{};
  final StreamController<TvNotificationItem> _tvNotificationController =
      StreamController<TvNotificationItem>.broadcast();
  final StreamController<TvNotificationDestination>
  _notificationActivationController =
      StreamController<TvNotificationDestination>.broadcast();
  static const _maxActivatedNotificationIds = 100;
  final Set<String> _activatedNotificationIds = <String>{};
  final Generation _notificationSessionGeneration = Generation();
  final Generation _sourceOperationGeneration = Generation();
  final Generation _sourceRollbackGeneration = Generation();
  final Generation _viewerOperationGeneration = Generation();
  final SerialQueue _sourceReplacementQueue = SerialQueue();
  final Set<Future<void>> _backgroundPersistence = <Future<void>>{};
  int _sourceReplacementOwners = 0;
  int _unreadNotificationCount = 0;

  /// Stream of incoming TV push notifications (from Reverb WebSocket or
  /// unread notifications fetched on boot). Listen to this in the UI to
  /// show snackbars or banners.
  Stream<TvNotificationItem> get tvNotifications =>
      _tvNotificationController.stream;

  Stream<TvNotificationDestination> get notificationActivations =>
      _notificationActivationController.stream;

  int get unreadNotificationCount => _unreadNotificationCount;

  void _runBackgroundPersistence(Future<Object?> operation) {
    late final Future<void> tracked;
    tracked = operation
        .then<void>((_) {})
        .whenComplete(
          () => _backgroundPersistence.remove(tracked),
        );
    _backgroundPersistence.add(tracked);
    unawaited(tracked);
  }

  Future<void> drainBackgroundPersistence() async {
    while (_backgroundPersistence.isNotEmpty) {
      await Future.wait(_backgroundPersistence.toList(growable: false));
    }
  }

  Future<bool> _refreshUnreadNotificationCount({
    bool Function()? shouldCommit,
  }) async {
    if (shouldCommit != null && !shouldCommit()) return false;
    final subscribed = await notificationStore.subscribedChannels();
    if (shouldCommit != null && !shouldCommit()) return false;
    final unreadCount = await notificationStore.unreadCount(
      channelFilter: subscribed.isEmpty ? null : subscribed,
    );
    if (shouldCommit != null && !shouldCommit()) return false;
    _unreadNotificationCount = unreadCount;
    notifyListeners();
    return true;
  }

  Future<void> markNotificationRead(String id) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsNotification = _captureNotificationOwnership(
      credentials: credentials,
      notificationGeneration: _notificationSessionGeneration.current,
    );
    if (!ownsNotification()) return;
    await notificationStore.markReadIf(id, ownsNotification);
    if (!ownsNotification()) return;
    if (!await _refreshUnreadNotificationCount(
      shouldCommit: ownsNotification,
    )) {
      return;
    }
    if (!ownsNotification()) return;
    unawaited(
      _tvNotificationService.markRead(credentials, id).catchError((_) {}),
    );
  }

  Future<void> markAllNotificationsRead() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsNotification = _captureNotificationOwnership(
      credentials: credentials,
      notificationGeneration: _notificationSessionGeneration.current,
    );
    if (!ownsNotification()) return;
    final unread = (await notificationStore.all()).where((n) => !n.isRead);
    if (!ownsNotification()) return;
    final ids = unread.map((n) => n.item.id).toList(growable: false);
    await notificationStore.markAllReadIf(ownsNotification);
    if (!ownsNotification()) return;
    if (!await _refreshUnreadNotificationCount(
      shouldCommit: ownsNotification,
    )) {
      return;
    }
    for (final id in ids) {
      if (!ownsNotification()) return;
      unawaited(
        _tvNotificationService.markRead(credentials, id).catchError((_) {}),
      );
    }
  }

  Future<void> setNotificationChannels(Set<String> channels) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsNotification = _captureNotificationOwnership(
      credentials: credentials,
      notificationGeneration: _notificationSessionGeneration.current,
    );
    if (!ownsNotification()) return;
    await notificationStore.setSubscribedChannels(channels);
    if (!ownsNotification()) return;
    await _refreshUnreadNotificationCount(shouldCommit: ownsNotification);
  }

  final ViewerService viewerService;
  final EpgService epgService;
  final TraktService traktService;
  final DevicePairingService devicePairingService;

  AppSourceType _sourceType = AppSourceType.none;
  bool _isBootstrapping = false;
  bool _isLoadingContent = false;
  String? _error;
  Locale? _locale;
  Viewer? _activeViewer;
  List<Viewer> _viewers = const <Viewer>[];
  List<Category> _liveCategories = const <Category>[];
  List<Category> _vodCategories = const <Category>[];
  List<Category> _seriesCategories = const <Category>[];
  List<Channel> _channels = const <Channel>[];
  List<VodItem> _vodItems = const <VodItem>[];
  List<Series> _seriesList = const <Series>[];
  List<DvrRecording> _dvrRecordings = const <DvrRecording>[];
  DvrStorageInfo? _dvrStorageInfo;
  Set<int> _recordingChannelIds = const <int>{};
  List<DvrSeriesRule> _dvrSeriesRules = const <DvrSeriesRule>[];
  List<MediaRequestSummary> _mediaRequests = const <MediaRequestSummary>[];
  List<Progress> _progressList = const <Progress>[];
  Future<List<Progress>>? _recentlyWatchedRefresh;
  String? _recentlyWatchedRefreshViewerId;
  int? _recentlyWatchedRefreshSourceGeneration;
  int? _recentlyWatchedRefreshViewerGeneration;
  final Set<int> _pendingEpgChannelIds = <int>{};
  final Set<int> _pendingForcedEpgChannelIds = <int>{};
  final Map<String, DateTime> _fetchedEpgRanges = <String, DateTime>{};
  Timer? _epgFetchDebounce;
  DateTime? _pendingEpgStartDate;
  DateTime? _pendingEpgEndDate;
  String _activeEpgRangeKey = '';
  // Deliberately separate from epgService's own source-generation counter:
  // this one invalidates in-flight per-range/channel-batch fetches (bumped
  // on every guide range navigation, not just a full source reset), while
  // epgService's tracks whether the entire EPG source has been swapped.
  // The two must both advance together in _resetEpgSession — a reset path
  // that bumps only one would let a stale fetch write into the new source.
  int _epgRequestGeneration = 0;
  static const _epgPrimeCount = 60;
  static const _epgFetchDebounceDelay = Duration(milliseconds: 250);
  // Coalesce multiple DVR post-processing pushes that land in quick
  // succession (e.g. several recordings finishing back-to-back) into a
  // single re-fetch of VOD/Series. Mirrors the [_epgFetchDebounce] pattern.
  Timer? _dvrContentRefreshDebounce;
  Set<_DvrContentRefreshTarget> _dvrContentRefreshPending =
      const <_DvrContentRefreshTarget>{};
  // Guards against a second flush starting while one is already awaiting its
  // fetches. Without it, a push landing mid-flush (its debounce timer already
  // cleared by the in-flight run) would start an independent flush and
  // duplicate the network call instead of being coalesced into it — see the
  // while-loop in [_flushDvrContentRefresh].
  bool _dvrContentRefreshFlushing = false;
  static const _dvrContentRefreshDebounceDelay = Duration(milliseconds: 1500);
  // Cancelling the debounce timer in [dispose] only helps if it hasn't fired
  // yet. Once [_flushDvrContentRefresh] is in flight its awaits can outlive
  // us, and it runs from a fire-and-forget Timer callback, so a
  // notifyListeners() on a disposed notifier would surface as an unhandled
  // async error rather than being caught anywhere.
  bool _disposed = false;

  AppSourceType get sourceType => _sourceType;
  bool get isBootstrapping => _isBootstrapping;
  bool get isLoadingContent => _isLoadingContent;
  Locale? get locale => _locale;
  bool get isConfigured => _sourceType != AppSourceType.none;
  String? get error => _error ?? authNotifier.error;
  Viewer? get activeViewer => _activeViewer;
  List<Viewer> get viewers => _viewers;
  List<Category> get liveCategories => _liveCategories;
  List<Category> get vodCategories => _vodCategories;
  List<Category> get seriesCategories => _seriesCategories;
  List<Channel> get channels => _channels;
  List<VodItem> get vodItems => _vodItems;
  List<Series> get seriesList => _seriesList;
  List<DvrRecording> get dvrRecordings => _dvrRecordings;
  DvrStorageInfo? get dvrStorageInfo => _dvrStorageInfo;
  Set<int> get recordingChannelIds => _recordingChannelIds;
  List<DvrSeriesRule> get dvrSeriesRules => _dvrSeriesRules;
  List<Progress> get progressList => _progressList;
  List<MediaRequestSummary> get mediaRequests => _mediaRequests;
  bool get hasDvrFeature =>
      authNotifier.authResponse?.hasFeature('dvr') ?? false;
  bool get hasRequestsFeature =>
      authNotifier.authResponse?.hasFeature('requests') ?? false;
  RequestsCapability? get requestsCapability =>
      authNotifier.authResponse?.requests;
  MediaRequestOwner get mediaRequestOwner => (
    sourceGeneration: _sourceOperationGeneration.current,
    notificationGeneration: _notificationSessionGeneration.current,
    sourceType: _sourceType,
    credentials: authNotifier.credentials,
  );
  bool get hasAioStreams => authNotifier.authResponse?.hasAioStreams ?? false;
  List<AIOStreamsIntegration> get aiostreamsIntegrations =>
      authNotifier.authResponse?.aiostreamsIntegrations ?? const [];
  late final AIOStreamsApiService aiostreamsApiService = AIOStreamsApiService(
    xtreamService: xtreamService,
  );
  String get sourceLabel => switch (_sourceType) {
    AppSourceType.xtream => 'Xtream',
    AppSourceType.none => 'Not connected',
  };

  String? get serverTimezone =>
      _sourceType == AppSourceType.xtream ? xtreamService.serverTimezone : null;

  Future<void> boot() async {
    final sourceGeneration = _sourceOperationGeneration.advance();
    _isBootstrapping = true;
    _error = null;
    notifyListeners();
    unawaited(traktService.init());
    unawaited(proxyPlaybackSettings.load());
    unawaited(comskipSettings.load());

    // One-time move of the content cache into its own file for installs that
    // predate the split. No-op once done, or when a single store is in use.
    // Best-effort: an IO failure here just defers the split to a later boot,
    // it must not block startup.
    if (!identical(_cacheStore, _appStateStore)) {
      try {
        await _cacheStore.adoptKeysFrom(
          _appStateStore,
          (key) => key.startsWith('m3ue_cache_'),
        );
      } on Object catch (error) {
        debugPrint('Content cache migration deferred: $error');
      }
    }

    final savedLocale = await secureStorage.read(_localeKey);
    if (savedLocale != null) _locale = Locale(savedLocale);

    final savedIntervalRaw = await secureStorage.read(_epgIntervalKey);
    if (savedIntervalRaw != null) {
      final minutes = int.tryParse(savedIntervalRaw);
      if (minutes != null && minutes > 0) {
        final interval = Duration(minutes: minutes);
        cacheService.refreshInterval = interval;
        epgService.cacheTtl = interval;
      }
    }

    final savedSource = await _readSavedSourceType();
    // Read saved credentials off disk without a network handshake so cached
    // content can be painted before the live credential check completes.
    final credentials = await authNotifier.loadSavedCredentialsOffline();
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;

    if (credentials != null) {
      _resetEpgSession();
      final notificationGeneration = _notificationSessionGeneration.advance();
      final hydrated = await _hydrateCachedXtreamContent(
        sourceGeneration: sourceGeneration,
      );
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return;

      if (hydrated) {
        // Paint the cached grids now; validate the credentials and refresh
        // from the server in the background.
        _isBootstrapping = false;
        notifyListeners();
        _runBackgroundPersistence(
          _validateCredentialsAndRefresh(
            credentials,
            sourceGeneration: sourceGeneration,
            notificationGeneration: notificationGeneration,
          ),
        );
        return;
      }

      // Nothing cached to paint - block on the handshake and first load.
      final connected = await authNotifier.connect(
        credentials,
        isCurrent: () => !_sourceOperationGeneration.isStale(sourceGeneration),
      );
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
      if (connected) {
        final loaded = await _replaceWithXtreamContent(
          clearCache: false,
          sourceGeneration: sourceGeneration,
        );
        if (loaded) {
          _pushRegistrationSuspended = false;
          _runBackgroundPersistence(
            _connectTvNotifications(credentials, notificationGeneration),
          );
          unawaited(_registerPushToken(credentials));
        }
      } else if (savedSource == AppSourceType.xtream &&
          authNotifier.error != null) {
        _sourceType = AppSourceType.xtream;
        _error = authNotifier.error;
      }
    }

    _isBootstrapping = false;
    notifyListeners();
  }

  /// Runs the live credential handshake after cached content has already been
  /// painted by [boot]. On success it refreshes every list from the server
  /// and wires up notifications/push. On failure it leaves the stale cached
  /// content in place and surfaces the error as a banner rather than tearing
  /// the grids down - a transient network drop should not blank a working
  /// screen on a TV.
  Future<void> _validateCredentialsAndRefresh(
    UserCredentials credentials, {
    required int sourceGeneration,
    required int notificationGeneration,
  }) async {
    final connected = await authNotifier.connect(
      credentials,
      isCurrent: () => !_sourceOperationGeneration.isStale(sourceGeneration),
    );
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    if (!connected) {
      _error = authNotifier.error;
      notifyListeners();
      return;
    }

    final activeViewer = _activeViewer;
    final viewerGeneration = _viewerOperationGeneration.current;
    if (activeViewer != null) {
      _runBackgroundPersistence(
        _syncFavoritesForActiveViewer(
          activeViewer,
          sourceGeneration: sourceGeneration,
          viewerGeneration: viewerGeneration,
        ),
      );
      _runBackgroundPersistence(
        _refreshRecentlyWatchedForActiveViewer(
          activeViewer,
          sourceGeneration: sourceGeneration,
          viewerGeneration: viewerGeneration,
        ),
      );
    }
    _runBackgroundPersistence(
      _replaceWithXtreamContent(
        clearCache: false,
        sourceGeneration: sourceGeneration,
      ),
    );
    _pushRegistrationSuspended = false;
    _runBackgroundPersistence(
      _connectTvNotifications(credentials, notificationGeneration),
    );
    unawaited(_registerPushToken(credentials));
  }

  Future<bool> connectXtream(UserCredentials credentials) {
    final sourceGeneration = _sourceOperationGeneration.advance();
    final rollbackGeneration = _sourceRollbackGeneration.current;
    if (_sourceReplacementOwners == 0) {
      return _connectXtream(
        credentials,
        sourceGeneration,
        rollbackGeneration: rollbackGeneration,
        ownsQueue: false,
      );
    }
    return _sourceReplacementQueue.run(() async {
      _sourceReplacementOwners += 1;
      try {
        return await _connectXtream(
          credentials,
          sourceGeneration,
          rollbackGeneration: rollbackGeneration,
          ownsQueue: true,
        );
      } finally {
        _sourceReplacementOwners -= 1;
      }
    });
  }

  Future<bool> _connectXtream(
    UserCredentials credentials,
    int sourceGeneration, {
    required int rollbackGeneration,
    required bool ownsQueue,
  }) async {
    final notificationGeneration = _notificationSessionGeneration.advance();
    _isLoadingContent = true;
    _error = null;
    notifyListeners();

    final previousCredentials = authNotifier.credentials;
    final previousAuthSession = authNotifier.snapshotSession();
    final previousCache = await cacheService.snapshot();
    final previousSource = await secureStorage.read(_sourceKey);
    final replacingNotificationSession =
        previousCredentials != null &&
        !_sameCredentials(previousCredentials, credentials);
    var restoredPreviousSource = false;
    Future<void> restorePreviousSource({required bool allowStaleSource}) async {
      if (_sourceRollbackGeneration.isStale(rollbackGeneration)) {
        if (_sourceType == AppSourceType.none) {
          await _bestEffort(cacheService.clear);
        }
        return;
      }
      if (restoredPreviousSource) return;
      restoredPreviousSource = true;
      await _bestEffort(() async {
        if (_sourceRollbackGeneration.isStale(rollbackGeneration)) return;
        await authNotifier.restoreSession(previousAuthSession);
      });
      await _bestEffort(() async {
        if (_sourceRollbackGeneration.isStale(rollbackGeneration)) return;
        await cacheService.restore(previousCache);
      });
      await _bestEffort(() async {
        if (_sourceRollbackGeneration.isStale(rollbackGeneration)) return;
        await _restoreSource(previousSource);
      });
      if (replacingNotificationSession) {
        await _bestEffort(
          () async {
            if (_sourceRollbackGeneration.isStale(rollbackGeneration)) return;
            await _restoreNotificationSession(
              previousCredentials,
              sourceGeneration: sourceGeneration,
              notificationGeneration: notificationGeneration,
              allowStaleSource: allowStaleSource,
            );
          },
        );
      }
    }

    if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
    if (replacingNotificationSession) {
      _clearNotificationOwner();
      _pushRegistrationSuspended = true;
      _pushLifecycleGeneration.advance();
      await _reverbService.disconnect();
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
      await _unregisterPushToken();
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
    }

    final connected = await authNotifier.connect(
      credentials,
      isCurrent: () => !_sourceOperationGeneration.isStale(sourceGeneration),
      persistCredentials: false,
      publishSession: false,
    );
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
    if (!connected) {
      if (replacingNotificationSession) {
        await _restoreNotificationSession(
          previousCredentials,
          sourceGeneration: sourceGeneration,
          notificationGeneration: notificationGeneration,
        );
      }
      _isLoadingContent = false;
      _error = _redact(
        authNotifier.error ?? 'Authentication failed',
        credentials,
      );
      notifyListeners();
      return false;
    }
    // Credentials are authenticated as of here, so the transition this flag
    // was guarding is over — clear it even if content fails to load below,
    // otherwise a load failure leaves push registration stuck suspended
    // until some future connect attempt happens to fully succeed.
    _pushRegistrationSuspended = false;

    final loaded = await _replaceWithXtreamContent(
      clearCache: true,
      sourceGeneration: sourceGeneration,
      invalidateEpgFreshness:
          _sourceType != AppSourceType.xtream ||
          !_sameCredentials(previousCredentials, credentials),
      persistSession: authNotifier.persistSession,
      ownsSourceReplacementQueue: ownsQueue,
      rollbackSource: () => restorePreviousSource(allowStaleSource: true),
    );
    final isCurrent = !_sourceOperationGeneration.isStale(sourceGeneration);
    if (!loaded && isCurrent) {
      await restorePreviousSource(allowStaleSource: false);
    } else {
      if (loaded && isCurrent) authNotifier.publishSession();
    }
    if (isCurrent) {
      _isLoadingContent = false;
      notifyListeners();
    }
    if (loaded && isCurrent) {
      _runBackgroundPersistence(
        _connectTvNotifications(credentials, notificationGeneration),
      );
      await _registerPushToken(credentials);
    }
    return loaded && isCurrent;
  }

  Future<void> _restoreSource(String? source) async {
    if (source == null) {
      await secureStorage.delete(_sourceKey);
    } else {
      await secureStorage.write(_sourceKey, source);
    }
  }

  Future<void> _bestEffort(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object catch (_) {}
  }

  Future<void> _restoreNotificationSession(
    UserCredentials credentials, {
    required int sourceGeneration,
    required int notificationGeneration,
    bool allowStaleSource = false,
  }) async {
    if (!allowStaleSource &&
        _sourceOperationGeneration.isStale(sourceGeneration)) {
      return;
    }
    _pushRegistrationSuspended = false;
    await _connectTvNotifications(credentials, notificationGeneration);
    if ((!allowStaleSource &&
            _sourceOperationGeneration.isStale(sourceGeneration)) ||
        _notificationSessionGeneration.isStale(notificationGeneration)) {
      return;
    }
    await _registerPushToken(credentials);
  }

  Future<void> _connectTvNotifications(
    UserCredentials credentials,
    int notificationGeneration,
  ) async {
    try {
      final session = await _reconcileUnreadNotifications(
        credentials,
        present: _pendingNotificationActivations.isEmpty,
        notificationGeneration: notificationGeneration,
      );
      if (_notificationSessionGeneration.isStale(notificationGeneration)) {
        return;
      }
      await _drainPendingPushActivations();
      if (_notificationSessionGeneration.isStale(notificationGeneration) ||
          !_sameCredentials(authNotifier.credentials, credentials)) {
        return;
      }
      // Older server versions don't return Reverb config — skip WebSocket setup
      // rather than hammering a connection that can never succeed.
      if (session == null) return;
      final ownsDvr = _captureDvrOwnership(
        credentials,
        notificationGeneration: notificationGeneration,
      );
      final ownsRequests = _captureMediaRequestOwnership(
        credentials,
        notificationGeneration: notificationGeneration,
      );
      await _reverbService.connect(
        session: session,
        credentials: credentials,
        onNotification: _onPushNotification,
        onDvrStatus: (recording) =>
            _onDvrStatusPush(recording, credentials, ownsDvr),
        onRequestStatus: (request) =>
            _onRequestStatusPush(request, ownsRequests),
        onFavoriteToggled: _onFavoriteTogglePush,
        // Reconciles any status pushes missed while disconnected (app
        // suspended, network drop) — cheap, status-filtered fetch, not a poll.
        onConnected: () => unawaited(
          _refreshActiveDvrRecordings(credentials, ownsDvr),
        ),
      );
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
  }

  /// Fetches the server's authoritative unread list, syncs it into the local
  /// store (surfacing genuinely new items as toasts), and returns the
  /// playlist session — or `null` if the server has no Reverb config to
  /// connect a WebSocket to.
  Future<TvPlaylistSession?> _reconcileUnreadNotifications(
    UserCredentials credentials, {
    String? presentOnlyId,
    bool present = true,
    int? notificationGeneration,
  }) async {
    final accountPrincipal = credentials.username;
    final ownsNotification = _captureNotificationOwnership(
      credentials: credentials,
      notificationGeneration: notificationGeneration,
    );
    if (!ownsNotification()) return null;
    final (session, unread) = await _tvNotificationService.fetchUnread(
      credentials,
    );
    if (!ownsNotification()) return null;
    if (!notificationStore.selectOwner(
      server: credentials.server,
      accountPrincipal: accountPrincipal,
      session: session,
    )) {
      _clearNotificationOwner();
      return null;
    }
    if (session.availableChannels.isNotEmpty) {
      await notificationStore.setServerChannels(
        session.availableChannels,
        shouldCommit: ownsNotification,
      );
      if (!ownsNotification()) return null;
    }
    // Sync local store with the server's authoritative unread list: stale
    // local unreads are marked read, new server items are added. Only
    // genuinely new items (not seen before) are surfaced as toasts — this
    // should not replay banners for notifications the user already received.
    final authorizedUnread = session.isAdmin
        ? unread
        : unread.where((item) => !item.adminOnly).toList(growable: false);
    final newItems = await notificationStore.syncUnreadWithServer(
      authorizedUnread,
      shouldCommit: ownsNotification,
    );
    if (!ownsNotification()) return null;
    if (!await _refreshUnreadNotificationCount(
      shouldCommit: ownsNotification,
    )) {
      return null;
    }
    if (present) {
      final subscribed = await notificationStore.subscribedChannels();
      if (!ownsNotification()) return null;
      for (final item in newItems) {
        if ((presentOnlyId == null || item.id == presentOnlyId) &&
            (subscribed.isEmpty || subscribed.contains(item.channel)) &&
            ownsNotification()) {
          _tvNotificationController.add(item);
        }
      }
    }
    if (!ownsNotification()) return null;
    if (session.channelName.isEmpty || session.reverb.appKey.isEmpty) {
      return null;
    }
    return session;
  }

  Future<void> reconcileNotifications() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    await _reconcileUnreadNotifications(credentials);
  }

  /// Suspends the TV notification WebSocket while the app is backgrounded.
  /// Call [resumeNotifications] when the app returns to the foreground.
  Future<void> suspendNotifications() => _reverbService.pause();

  /// Reconnects the TV notification WebSocket after the app returns to the
  /// foreground, and reconciles any notifications (e.g. a push received
  /// while backgrounded) the server delivered while the socket was down.
  /// No-op if there are no stored credentials.
  Future<void> resumeNotifications() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final notificationGeneration = _notificationSessionGeneration.current;
    try {
      await _reconcileUnreadNotifications(
        credentials,
        present: _pendingNotificationActivations.isEmpty,
        notificationGeneration: notificationGeneration,
      );
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
    await _drainPendingPushActivations();
    await _reverbService.resume();
  }

  /// Called by `main.dart` once Firebase hands back an FCM registration
  /// token (mobile only — TV builds never call this). Registers immediately
  /// if credentials are already connected; otherwise the token is held and
  /// registered the next time [_connectTvNotifications] runs.
  Future<void> initPushNotifications() =>
      _pushInitialization ??= _initializePushNotifications();

  Future<void> _initializePushNotifications() async {
    final token = await _pushNotificationService.init(
      onForegroundMessage: handleForegroundPush,
      onMessageOpenedApp: handlePushActivation,
    );
    if (token != null) await setPushToken(token);
    _pushTokenSubscription = _pushNotificationService.onTokenRefresh.listen(
      (replacement) => unawaited(setPushToken(replacement)),
    );
  }

  Future<void> setPushToken(String token) {
    final generation = _pushLifecycleGeneration.current;
    final registrationSuspended = _pushRegistrationSuspended;
    return _queuePushLifecycle(() async {
      final alreadyRegistered =
          _pushToken == token && _registeredPushToken == token;
      _pushToken = token;
      if (_pushLifecycleGeneration.isStale(generation) ||
          registrationSuspended ||
          _pushRegistrationSuspended ||
          alreadyRegistered) {
        return;
      }
      await _unregisterPushTokenNow();
      if (_pushLifecycleGeneration.isStale(generation) ||
          _pushRegistrationSuspended) {
        return;
      }
      final credentials = authNotifier.credentials;
      if (credentials != null) {
        await _registerPushTokenNow(credentials, generation);
      }
    });
  }

  Future<void> _queuePushLifecycle(Future<void> Function() operation) =>
      _pushLifecycleQueue.run(operation);

  Future<void> _registerPushToken(UserCredentials credentials) {
    final generation = _pushLifecycleGeneration.current;
    return _queuePushLifecycle(
      () => _registerPushTokenNow(credentials, generation),
    );
  }

  Future<void> _registerPushTokenNow(
    UserCredentials credentials,
    int generation,
  ) async {
    if (_pushLifecycleGeneration.isStale(generation) ||
        _pushRegistrationSuspended) {
      return;
    }
    final token = _pushToken;
    if (token == null) return;
    if (_registeredPushToken == token &&
        _sameCredentials(_registeredPushCredentials, credentials)) {
      return;
    }
    await _unregisterPushTokenNow();
    if (_pushLifecycleGeneration.isStale(generation) ||
        _pushRegistrationSuspended) {
      return;
    }
    try {
      await _pushNotificationService.registerToken(
        credentials,
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      _registeredPushCredentials = credentials;
      _registeredPushToken = token;
    } on Object catch (_) {
      // Push registration is best-effort, same as TV notifications above.
    }
  }

  Future<void> _unregisterPushToken() =>
      _queuePushLifecycle(_unregisterPushTokenNow);

  Future<void> _unregisterPushTokenNow() async {
    final credentials = _registeredPushCredentials;
    final token = _registeredPushToken;
    _registeredPushCredentials = null;
    _registeredPushToken = null;
    if (credentials == null || token == null) return;
    try {
      await _pushNotificationService.unregisterToken(
        credentials,
        token: token,
      );
    } on Object catch (_) {
      // Best-effort cleanup; do not retain a stale local association on failure.
    }
  }

  void _onPushNotification(TvNotificationItem item) {
    final ownsNotification = _captureNotificationOwnership();
    _runBackgroundPersistence(
      receiveTvNotification(item, shouldCommit: ownsNotification),
    );
  }

  bool Function() _captureNotificationOwnership({
    UserCredentials? credentials,
    int? notificationGeneration,
  }) {
    final ownedCredentials = credentials ?? authNotifier.credentials;
    final ownedNotificationGeneration =
        notificationGeneration ?? _notificationSessionGeneration.current;
    final sourceGeneration = _sourceOperationGeneration.current;
    final viewerGeneration = _viewerOperationGeneration.current;
    final sourceType = _sourceType;
    final viewerUlid = _activeViewer?.ulid;
    return () =>
        ownedCredentials != null &&
        !_notificationSessionGeneration.isStale(
          ownedNotificationGeneration,
        ) &&
        !_sourceOperationGeneration.isStale(sourceGeneration) &&
        !_viewerOperationGeneration.isStale(viewerGeneration) &&
        _sameCredentials(authNotifier.credentials, ownedCredentials) &&
        _sourceType == sourceType &&
        _activeViewer?.ulid == viewerUlid;
  }

  bool Function() _captureDvrOwnership(
    UserCredentials credentials, {
    int? notificationGeneration,
  }) {
    final ownedNotificationGeneration =
        notificationGeneration ?? _notificationSessionGeneration.current;
    final sourceGeneration = _sourceOperationGeneration.current;
    final viewerGeneration = _viewerOperationGeneration.current;
    final viewerUlid = _activeViewer?.ulid;
    return () =>
        !_notificationSessionGeneration.isStale(
          ownedNotificationGeneration,
        ) &&
        !_sourceOperationGeneration.isStale(sourceGeneration) &&
        !_viewerOperationGeneration.isStale(viewerGeneration) &&
        _sourceType == AppSourceType.xtream &&
        _sameCredentials(authNotifier.credentials, credentials) &&
        _sameCredentials(xtreamService.credentials, credentials) &&
        _activeViewer?.ulid == viewerUlid;
  }

  bool Function() _captureMediaRequestOwnership(
    UserCredentials credentials, {
    int? notificationGeneration,
    MediaRequestOwner? owner,
  }) {
    final owned =
        owner ??
        (
          sourceGeneration: _sourceOperationGeneration.current,
          notificationGeneration:
              notificationGeneration ?? _notificationSessionGeneration.current,
          sourceType: _sourceType,
          credentials: credentials,
        );
    return () =>
        owned.credentials != null &&
        !_notificationSessionGeneration.isStale(
          owned.notificationGeneration,
        ) &&
        !_sourceOperationGeneration.isStale(owned.sourceGeneration) &&
        owned.sourceType == AppSourceType.xtream &&
        _sourceType == owned.sourceType &&
        _sameCredentials(owned.credentials, credentials) &&
        _sameCredentials(authNotifier.credentials, owned.credentials) &&
        _sameCredentials(xtreamService.credentials, owned.credentials);
  }

  Future<void> handleForegroundPush(PushMessage message) async {
    final id = message.notificationId;
    final credentials = authNotifier.credentials;
    if (id == null || credentials == null) return;
    final notificationGeneration = _notificationSessionGeneration.current;
    try {
      await _reconcileUnreadNotifications(
        credentials,
        presentOnlyId: id,
        notificationGeneration: notificationGeneration,
      );
    } on Object catch (_) {
      // Push reconciliation is best-effort and never trusts payload content.
    }
  }

  Future<void> handlePushActivation(PushMessage message) =>
      handleNotificationActivation(message.notificationId);

  Future<void> handleNotificationActivation(String? notificationId) async {
    final id = canonicalNotificationId(notificationId);
    if (id == null) return;
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      _pendingNotificationActivations.add(id);
      return;
    }
    final accountPrincipal = credentials.username;
    final notificationGeneration = _notificationSessionGeneration.current;
    final ownsNotification = _captureNotificationOwnership(
      credentials: credentials,
      notificationGeneration: notificationGeneration,
    );
    if (!ownsNotification()) return;

    try {
      final (session, unread) = await _tvNotificationService.fetchUnread(
        credentials,
      );
      if (!ownsNotification()) return;
      if (!notificationStore.selectOwner(
        server: credentials.server,
        accountPrincipal: accountPrincipal,
        session: session,
      )) {
        _clearNotificationOwner();
        return;
      }
      if (session.availableChannels.isNotEmpty) {
        await notificationStore.setServerChannels(
          session.availableChannels,
          shouldCommit: ownsNotification,
        );
        if (!ownsNotification()) return;
      }
      final authorizedUnread = session.isAdmin
          ? unread
          : unread.where((item) => !item.adminOnly).toList(growable: false);
      await notificationStore.syncUnreadWithServer(
        authorizedUnread,
        shouldCommit: ownsNotification,
      );
      if (!ownsNotification()) return;
      if (!await _refreshUnreadNotificationCount(
        shouldCommit: ownsNotification,
      )) {
        return;
      }
      final matching = authorizedUnread.where((item) => item.id == id);
      if (matching.isEmpty) return;
      final destination = notificationDestinationFor(matching.first.channel);
      if (!ownsNotification() ||
          destination == null ||
          !_markNotificationActivated(id)) {
        return;
      }
      _notificationActivationController.add(destination);
    } on Object catch (_) {
      // A tap without an authorized REST record is a safe no-op.
    }
  }

  Future<void> _drainPendingPushActivations() async {
    if (authNotifier.credentials == null ||
        _pendingNotificationActivations.isEmpty) {
      return;
    }
    final pending = _pendingNotificationActivations.toList(growable: false);
    _pendingNotificationActivations.clear();
    for (final id in pending) {
      await handleNotificationActivation(id);
    }
  }

  void _onDvrStatusPush(
    DvrRecording recording,
    UserCredentials credentials,
    bool Function() ownsWork,
  ) {
    if (!ownsWork()) return;
    final channelId = recording.channelId;
    if (channelId != null) {
      final updated = Set<int>.of(_recordingChannelIds);
      if (recording.isInProgress) {
        updated.add(channelId);
      } else {
        updated.remove(channelId);
      }
      if (!setEquals(_recordingChannelIds, updated)) {
        if (!ownsWork()) return;
        _recordingChannelIds = updated;
        if (!ownsWork()) return;
        notifyListeners();
      }
    }

    if (recording.status == DvrRecordingStatus.deleted) {
      // The server is the source of truth: a deleted recording has no
      // get_dvr_recording row left to fetch, so drop it locally instead of
      // refreshing its detail.
      final next = _dvrRecordings
          .where((r) => r.uuid != recording.uuid)
          .toList(growable: false);
      if (next.length != _dvrRecordings.length) {
        if (!ownsWork()) return;
        _dvrRecordings = next;
        if (!ownsWork()) return;
        notifyListeners();
      }
      return;
    }

    // The push payload is a lightweight status ping (no stream_url/live_url —
    // those need this viewer's Xtream credentials to build). Fetch the full
    // record so the DVR Recordings screen updates its status label and gets
    // a playable URL as soon as a recording starts, not just on next reload.
    //
    // Toasts for user-facing transitions (started/completed/failed/cancelled)
    // are no longer sent from here — the server dispatches a persisted
    // TvNotification on the 'dvr' channel at those points instead, which
    // arrives through the same _onPushNotification path as every other
    // notification (unread badge, history, subscription filter all for free).
    if (!ownsWork()) return;
    unawaited(
      _refreshDvrRecordingDetail(
        recording.uuid,
        credentials,
        ownsWork,
      ),
    );
  }

  Future<void> _refreshDvrRecordingDetail(
    String uuid,
    UserCredentials credentials,
    bool Function() ownsWork,
  ) async {
    if (!ownsWork()) return;
    try {
      final detail = await xtreamService.getDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
      final next = [..._dvrRecordings];
      final index = next.indexWhere((r) => r.uuid == uuid);
      if (index >= 0) {
        next[index] = detail;
      } else {
        next.insert(0, detail);
      }
      if (!ownsWork()) return;
      _dvrRecordings = next;
      if (!ownsWork()) return;
      notifyListeners();

      // When a recording lands in `completed` or `postProcessing`, the server
      // has just upserted it as a VOD movie or series episode. Re-fetch the
      // affected list(s) so the new item appears in Movies / Series / Home
      // without requiring a full reconnect — fixes #179.
      if (detail.status == DvrRecordingStatus.completed ||
          detail.status == DvrRecordingStatus.postProcessing) {
        _scheduleDvrContentRefresh(_classifyContentTargets(detail), ownsWork);
      }
    } on Object catch (error) {
      debugPrint('DVR: refresh recording detail after push failed: $error');
    }
  }

  /// Decide which content lists to refresh for a finished recording. A
  /// recording with both a season and episode number is unambiguously a
  /// series episode; everything else (movies, one-offs, or server payloads
  /// that omit season/episode metadata) falls back to refreshing both lists
  /// — the issue permits over-refresh, never under-refresh.
  Set<_DvrContentRefreshTarget> _classifyContentTargets(
    DvrRecording recording,
  ) {
    if (recording.seasonNumber != null && recording.episodeNumber != null) {
      return const <_DvrContentRefreshTarget>{_DvrContentRefreshTarget.series};
    }
    return const <_DvrContentRefreshTarget>{
      _DvrContentRefreshTarget.vod,
      _DvrContentRefreshTarget.series,
    };
  }

  void _scheduleDvrContentRefresh(
    Set<_DvrContentRefreshTarget> targets,
    bool Function() ownsWork,
  ) {
    if (targets.isEmpty) return;
    _dvrContentRefreshPending = <_DvrContentRefreshTarget>{
      ..._dvrContentRefreshPending,
      ...targets,
    };
    _dvrContentRefreshDebounce?.cancel();
    _dvrContentRefreshDebounce = Timer(
      _dvrContentRefreshDebounceDelay,
      () => _flushDvrContentRefresh(ownsWork),
    );
  }

  Future<void> _flushDvrContentRefresh(bool Function() ownsWork) async {
    // A flush is already looping (see below) and will pick up whatever this
    // call just merged into `_dvrContentRefreshPending` on its next
    // iteration — starting a second, concurrent flush here would duplicate
    // the network calls the first one is already making.
    if (_dvrContentRefreshFlushing) return;
    _dvrContentRefreshFlushing = true;
    try {
      // Loop rather than flushing once: a push that lands while this flush is
      // awaiting its fetches merges into `_dvrContentRefreshPending` with no
      // timer to pick it up (this flush already consumed and nulled it), so
      // it must be handled before this method returns.
      while (true) {
        if (_disposed || _dvrContentRefreshPending.isEmpty) return;
        if (!ownsWork()) return;
        final targets = _dvrContentRefreshPending;
        _dvrContentRefreshPending = const <_DvrContentRefreshTarget>{};
        _dvrContentRefreshDebounce?.cancel();
        _dvrContentRefreshDebounce = null;

        final results = await Future.wait<bool>(<Future<bool>>[
          if (targets.contains(_DvrContentRefreshTarget.vod))
            _refreshContentAfterDvr<List<VodItem>>(
              fetch: xtreamService.getVodStreams,
              apply: (next) => _vodItems = next,
              ownsWork: ownsWork,
              label: 'VOD',
            ),
          if (targets.contains(_DvrContentRefreshTarget.series))
            _refreshContentAfterDvr<List<Series>>(
              fetch: xtreamService.getSeries,
              apply: (next) => _seriesList = next,
              ownsWork: ownsWork,
              label: 'series',
            ),
        ]);
        if (_disposed || !ownsWork()) return;
        if (results.contains(true)) notifyListeners();
      }
    } finally {
      _dvrContentRefreshFlushing = false;
    }
  }

  Future<bool> _refreshContentAfterDvr<T>({
    required Future<T> Function() fetch,
    required void Function(T next) apply,
    required bool Function() ownsWork,
    required String label,
  }) async {
    try {
      final next = await fetch();
      if (!ownsWork() || _disposed) return false;
      apply(next);
      // No cache write here — dev commits `vodStreams`/`series` only as part
      // of the whole-bundle guarded replace in `_sourceReplacementQueue`. A
      // per-key partial write would risk persisting another account's
      // library if the ownership predicate goes stale mid-fetch.
      return true;
    } on Object catch (error) {
      debugPrint('DVR: refresh $label after post-processing failed: $error');
      return false;
    }
  }

  /// Mirrors [_onDvrStatusPush]: updates the local requests list in place
  /// from the lightweight `request.status` push (approved/rejected/completed
  /// by MediaRequestStatusEvent on the server) instead of re-polling
  /// request_history.
  void _onRequestStatusPush(
    MediaRequestSummary request,
    bool Function() ownsWork,
  ) {
    if (!ownsWork()) return;
    final next = [..._mediaRequests];
    final index = next.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.insert(0, request);
    }
    if (!ownsWork()) return;
    _mediaRequests = next;
    if (!ownsWork()) return;
    notifyListeners();
  }

  /// Pushes a local Live/VOD/Series favorite change to the server. No-op
  /// when not connected (nothing to sync to) — mirrors the same
  /// `sourceType == xtream` gate used for progress pushes in app_shell.dart.
  void _pushFavoriteChange(
    String contentType,
    int streamId, {
    required bool favorited,
  }) {
    if (_sourceType != AppSourceType.xtream) return;
    final viewer = _activeViewer;
    if (viewer == null) return;
    unawaited(
      xtreamService
          .toggleFavorite(
            viewerId: viewer.ulid,
            contentType: contentType,
            streamId: streamId,
            favorited: favorited,
          )
          .catchError((Object error) {
            debugPrint('Favorites: push $contentType/$streamId failed: $error');
          }),
    );
  }

  /// Pushes a local AIOStreams favorite add to the server, carrying its full
  /// metadata — the server has no other way to learn an addon item's
  /// title/poster/type, and other devices need that to render the favorite
  /// without a live re-fetch from the addon.
  void _pushAioFavoriteAdded(AIOStreamsFavoriteItem item) {
    if (_sourceType != AppSourceType.xtream) return;
    final viewer = _activeViewer;
    if (viewer == null) return;
    unawaited(
      xtreamService
          .toggleFavorite(
            viewerId: viewer.ulid,
            contentType: 'aiostreams',
            aioItemId: item.id,
            favorited: true,
            title: item.name,
            thumbnailUrl: item.poster,
            itemType: item.type,
            aioIntegrationId: item.integrationId,
          )
          .catchError((Object error) {
            debugPrint('Favorites: push aiostreams/${item.id} failed: $error');
          }),
    );
  }

  AIOStreamsMutationOwnership _captureAioFavoriteMutationOwnership() {
    final sourceGeneration = _sourceOperationGeneration.current;
    final viewerGeneration = _viewerOperationGeneration.current;
    final sourceType = _sourceType;
    final viewerUlid = _activeViewer?.ulid;
    return () =>
        !_sourceOperationGeneration.isStale(sourceGeneration) &&
        !_viewerOperationGeneration.isStale(viewerGeneration) &&
        _sourceType == sourceType &&
        _activeViewer?.ulid == viewerUlid;
  }

  FavoritesMutationOwnership _captureFavoriteMutationOwnership() {
    final sourceGeneration = _sourceOperationGeneration.current;
    final viewerGeneration = _viewerOperationGeneration.current;
    final sourceType = _sourceType;
    final viewerUlid = _activeViewer?.ulid;
    return () =>
        !_sourceOperationGeneration.isStale(sourceGeneration) &&
        !_viewerOperationGeneration.isStale(viewerGeneration) &&
        _sourceType == sourceType &&
        _activeViewer?.ulid == viewerUlid;
  }

  void _pushAioFavoriteRemoved(String itemId) {
    if (_sourceType != AppSourceType.xtream) return;
    final viewer = _activeViewer;
    if (viewer == null) return;
    unawaited(
      xtreamService
          .toggleFavorite(
            viewerId: viewer.ulid,
            contentType: 'aiostreams',
            aioItemId: itemId,
            favorited: false,
          )
          .catchError((Object error) {
            debugPrint(
              'Favorites: push aiostreams/$itemId removal failed: $error',
            );
          }),
    );
  }

  /// Applies a favorite/unfavorite pushed from another device signed into the
  /// same viewer. Ignores events for a viewer other than the currently
  /// active one.
  void _onFavoriteTogglePush(FavoriteToggleEvent event) {
    final viewer = _activeViewer;
    if (viewer == null || viewer.ulid != event.viewerId) return;
    final ownsMutation = _captureFavoriteMutationOwnership();

    if (event.contentType == 'aiostreams') {
      final aioItemId = event.aioItemId;
      if (aioItemId == null) return;
      unawaited(
        aioFavoritesService.applyRemote(
          aioItemId,
          favorited: event.favorited,
          item: event.favorited ? _aioItemFromEvent(event) : null,
        ),
      );
      return;
    }

    final streamId = event.streamId;
    if (streamId == null) return;
    final service = switch (event.contentType) {
      'live' => favoritesService,
      'vod' => vodFavoritesService,
      'series' => seriesFavoritesService,
      _ => null,
    };
    unawaited(
      service?.applyRemote(
        streamId,
        favorited: event.favorited,
        shouldCommit: ownsMutation,
      ),
    );
  }

  AIOStreamsFavoriteItem? _aioItemFromEvent(FavoriteToggleEvent event) {
    final aioItemId = event.aioItemId;
    if (aioItemId == null) return null;
    return AIOStreamsFavoriteItem(
      id: aioItemId,
      type: event.itemType ?? '',
      name: event.title ?? '',
      integrationId: event.aioIntegrationId ?? 0,
      poster: event.thumbnailUrl,
    );
  }

  /// Reconciles Live/VOD/Series/AIOStreams favorites for the active viewer
  /// with the server. The first time a given viewer is seen, pre-existing
  /// local-only favorites are unioned into the account via `sync_favorites`
  /// (never deletes) rather than overwritten — except for a non-admin (child)
  /// viewer, which never had its own local favorites (there was only ever
  /// one shared local list before server sync existed) and so just pulls.
  /// After that one-time reconciliation, the server is authoritative and
  /// every call here simply replaces the local cache with `get_favorites`.
  Future<bool> _syncFavoritesForActiveViewer(
    Viewer viewer, {
    required int sourceGeneration,
    required int viewerGeneration,
    bool Function()? ownsWork,
  }) async {
    bool isCurrent() =>
        ownsWork?.call() ??
        _ownsXtreamViewer(
          viewer,
          sourceGeneration: sourceGeneration,
          viewerGeneration: viewerGeneration,
        );
    if (!isCurrent()) return false;
    try {
      final migrated = await _readMigratedFavoriteViewers();
      if (!isCurrent()) return false;
      if (!migrated.contains(viewer.ulid)) {
        final synchronized = viewer.isAdmin && migrated.isEmpty
            ? await _pushLocalFavoritesOnce(viewer, isCurrent: isCurrent)
            : await _pullFavorites(viewer, isCurrent: isCurrent);
        if (!synchronized || !isCurrent()) return false;
        await _markFavoritesMigrated(viewer.ulid, isCurrent: isCurrent);
        return isCurrent();
      }
      return _pullFavorites(viewer, isCurrent: isCurrent);
    } on Object catch (error) {
      debugPrint('Favorites: sync failed for viewer ${viewer.ulid}: $error');
      return false;
    }
  }

  Future<bool> _pushLocalFavoritesOnce(
    Viewer viewer, {
    required bool Function() isCurrent,
  }) async {
    final live = await favoritesService.all();
    if (!isCurrent()) return false;
    final vod = await vodFavoritesService.all();
    if (!isCurrent()) return false;
    final series = await seriesFavoritesService.all();
    if (!isCurrent()) return false;
    final aio = await aioFavoritesService.all();
    if (!isCurrent()) return false;
    final payload = <Map<String, Object?>>[
      for (final id in live) {'content_type': 'live', 'stream_id': id},
      for (final id in vod) {'content_type': 'vod', 'stream_id': id},
      for (final id in series) {'content_type': 'series', 'stream_id': id},
      for (final item in aio)
        {
          'content_type': 'aiostreams',
          'aio_item_id': item.id,
          'title': item.name,
          'thumbnail_url': item.poster,
          'item_type': item.type,
          'aio_integration_id': item.integrationId,
        },
    ];
    if (!isCurrent()) return false;
    final merged = await xtreamService.syncFavorites(viewer.ulid, payload);
    if (!isCurrent()) return false;
    return _applyServerFavorites(merged, isCurrent: isCurrent);
  }

  Future<bool> _pullFavorites(
    Viewer viewer, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final favorites = await xtreamService.getFavorites(viewer.ulid);
    if (!isCurrent()) return false;
    return _applyServerFavorites(favorites, isCurrent: isCurrent);
  }

  Future<bool> _applyServerFavorites(
    List<Map<String, Object?>> favorites, {
    required bool Function() isCurrent,
  }) async {
    final live = <int>{};
    final vod = <int>{};
    final series = <int>{};
    final aio = <AIOStreamsFavoriteItem>[];
    for (final item in favorites) {
      final contentType = item['content_type'];
      if (contentType == 'aiostreams') {
        final aioItemId = item['aio_item_id'];
        if (aioItemId is! String || aioItemId.isEmpty) continue;
        aio.add(
          AIOStreamsFavoriteItem(
            id: aioItemId,
            type: '${item['item_type'] ?? ''}',
            name: '${item['title'] ?? ''}',
            integrationId: (item['aio_integration_id'] as num?)?.toInt() ?? 0,
            poster: item['thumbnail_url'] as String?,
          ),
        );
        continue;
      }
      final streamId = item['stream_id'];
      final id = streamId is int ? streamId : int.tryParse('$streamId');
      if (id == null) continue;
      switch (contentType) {
        case 'live':
          live.add(id);
        case 'vod':
          vod.add(id);
        case 'series':
          series.add(id);
      }
    }
    if (!isCurrent()) return false;
    if (!await favoritesService.replaceAll(live, shouldCommit: isCurrent)) {
      return false;
    }
    if (!await vodFavoritesService.replaceAll(vod, shouldCommit: isCurrent)) {
      return false;
    }
    if (!await seriesFavoritesService.replaceAll(
      series,
      shouldCommit: isCurrent,
    )) {
      return false;
    }
    return aioFavoritesService.replaceAll(aio, shouldCommit: isCurrent);
  }

  Future<Set<String>> _readMigratedFavoriteViewers() async {
    final raw = await secureStorage.read(_favoritesMigratedKey);
    if (raw == null) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => '$e').toSet();
    } on Object catch (_) {}
    return <String>{};
  }

  Future<bool> _markFavoritesMigrated(
    String viewerUlid, {
    required bool Function() isCurrent,
  }) async {
    final viewers = await _readMigratedFavoriteViewers()
      ..add(viewerUlid);
    if (!isCurrent()) return false;
    return secureStorage.writeIfCurrent(
      _favoritesMigratedKey,
      jsonEncode(viewers.toList()),
      isCurrent,
    );
  }

  Future<void> receiveTvNotification(
    TvNotificationItem item, {
    bool Function()? shouldCommit,
  }) async {
    if (shouldCommit != null && !shouldCommit()) return;
    final inserted = await notificationStore.add(
      item,
      shouldCommit: shouldCommit,
    );
    if (!inserted || (shouldCommit != null && !shouldCommit())) return;
    if (!await _refreshUnreadNotificationCount(shouldCommit: shouldCommit)) {
      return;
    }
    // Only surface the notification in the stream (banners/toasts) if the
    // channel passes the user's subscription filter.
    final subscribed = await notificationStore.subscribedChannels();
    if (shouldCommit != null && !shouldCommit()) return;
    if (subscribed.isEmpty || subscribed.contains(item.channel)) {
      _tvNotificationController.add(item);
    }
  }

  Future<void> disconnect() async {
    final sourceGeneration = _sourceOperationGeneration.advance();
    _sourceRollbackGeneration.advance();
    _isLoadingContent = false;
    _notificationSessionGeneration.advance();
    _clearNotificationOwner();
    _pushRegistrationSuspended = true;
    _pushLifecycleGeneration.advance();
    await _unregisterPushToken();
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    await _reverbService.disconnect();
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    await authNotifier.disconnect();
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    await cacheService.clear();
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    await _bestEffort(emptyMediaImageCacheIfAvailable);
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    await secureStorage.delete(_sourceKey);
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    _resetEpgSession();
    _sourceType = AppSourceType.none;
    _viewers = const <Viewer>[];
    _viewerOperationGeneration.advance();
    _activeViewer = null;
    _liveCategories = const <Category>[];
    _vodCategories = const <Category>[];
    _seriesCategories = const <Category>[];
    _channels = const <Channel>[];
    _vodItems = const <VodItem>[];
    _seriesList = const <Series>[];
    _dvrRecordings = const <DvrRecording>[];
    _dvrStorageInfo = null;
    _recordingChannelIds = const <int>{};
    _dvrSeriesRules = const <DvrSeriesRule>[];
    _mediaRequests = const <MediaRequestSummary>[];
    _progressList = const <Progress>[];
    _error = null;
    notifyListeners();
  }

  Duration get epgRefreshInterval => epgService.cacheTtl;

  Future<void> setEpgRefreshInterval(Duration interval) async {
    cacheService.refreshInterval = interval;
    epgService.cacheTtl = interval;
    await secureStorage.write(
      _epgIntervalKey,
      '${interval.inMinutes}',
    );
    notifyListeners();
  }

  Future<void> setLocale(Locale? locale) async {
    _locale = locale;
    if (locale == null) {
      await secureStorage.delete(_localeKey);
    } else {
      await secureStorage.write(_localeKey, locale.languageCode);
    }
    notifyListeners();
  }

  Future<void> refreshDvrSeriesRules() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final rules = await xtreamService.listDvrSeriesRulesFor(credentials);
      if (!ownsWork()) return;
      _dvrSeriesRules = rules;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh series rules failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    if (!ownsWork()) return;
    notifyListeners();
  }

  /// Refreshes the cached DVR recordings list from `get_dvr_recordings`.
  ///
  /// Series rules can produce a matching `DvrRecording` synchronously (see
  /// [scheduleDvrAiring]'s doc comment for the same server-side behaviour on
  /// one-shot recordings), so the UI agent should call this after a
  /// successful `createDvrSeriesRule` / `updateDvrSeriesRule` round-trip, not
  /// just after [refreshDvrSeriesRules]. Otherwise, a newly matched recording
  /// will not show up in the Recordings tab until the next full reload.
  Future<void> refreshDvrRecordings() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return;
      final recordingChannelIds = _extractRecordingChannelIds(recordings);
      if (!ownsWork()) return;
      _dvrRecordings = recordings;
      if (!ownsWork()) return;
      _recordingChannelIds = recordingChannelIds;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh recordings failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    if (!ownsWork()) return;
    notifyListeners();
  }

  Future<void> clearAndRefresh() async {
    final sourceGeneration = _sourceOperationGeneration.advance();
    _resetEpgSession(clearGuide: false);
    _isLoadingContent = true;
    _error = null;
    notifyListeners();
    aiostreamsApiService.clearCache();
    unawaited(_bestEffort(emptyMediaImageCacheIfAvailable));
    if (_sourceType == AppSourceType.xtream && !authNotifier.isConfigured) {
      _isLoadingContent = false;
      await boot();
      return;
    }
    await _replaceWithXtreamContent(
      clearCache: true,
      sourceGeneration: sourceGeneration,
    );
    if (_sourceOperationGeneration.isStale(sourceGeneration)) return;
    _isLoadingContent = false;
    notifyListeners();
  }

  Future<void> switchViewer(Viewer viewer) async {
    final sourceGeneration = _sourceOperationGeneration.current;
    final viewerGeneration = _viewerOperationGeneration.advance();
    await viewerService.setActiveViewer(viewer, loginKey: _currentLoginKey());
    if (_sourceOperationGeneration.isStale(sourceGeneration) ||
        _viewerOperationGeneration.isStale(viewerGeneration)) {
      return;
    }
    _activeViewer = viewer;
    bool isCurrent() => _ownsXtreamViewer(
      viewer,
      sourceGeneration: sourceGeneration,
      viewerGeneration: viewerGeneration,
    );
    final progress = await _loadRecentlyWatched(
      viewer.ulid,
      isCurrent: isCurrent,
    );
    if (!isCurrent()) return;
    _progressList = progress;
    notifyListeners();
    _runBackgroundPersistence(
      _syncFavoritesForActiveViewer(
        viewer,
        sourceGeneration: sourceGeneration,
        viewerGeneration: viewerGeneration,
      ),
    );
  }

  Future<Viewer?> createViewer(String name) async {
    try {
      final credentials = authNotifier.credentials;
      if (credentials == null) return null;
      final ownsWork = _captureMediaRequestOwnership(credentials);
      if (!ownsWork()) return null;
      final viewer = await xtreamService.createViewerFor(credentials, name);
      if (!ownsWork()) return null;
      _viewers = [..._viewers, viewer];
      await switchViewer(viewer);
      return viewer;
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> refreshLocalState() async {
    final viewer = _activeViewer;
    if (viewer != null) {
      _progressList = await resumeService.all(viewer.ulid);
    }
    notifyListeners();
  }

  /// Schedules a one-shot DVR recording and refreshes the local list.
  ///
  /// m3u-editor's `schedule_dvr` creates a DVR rule and (when DVR is enabled
  /// for the playlist) returns synchronously after the rule's scheduler has
  /// produced the corresponding `DvrRecording` row. We refresh the local list
  /// from `get_dvr_recordings` so the UI shows the real entry instead of a
  /// phantom row synthesised from a stale client-side response.
  ///
  /// Returns the matching recording if the refresh surfaced one for this
  /// channel + start time; otherwise null (the scheduler tick may not have
  /// produced the row yet on slower servers).
  Future<DvrRecording?> scheduleDvrAiring({
    required int channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return null;
    await xtreamService.scheduleDvrFor(
      credentials,
      channelId: channelId,
      title: title,
      startTime: startTime,
      endTime: endTime,
    );
    if (!ownsWork()) return null;
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return null;
      _dvrRecordings = recordings;
      _recordingChannelIds = _extractRecordingChannelIds(recordings);
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return null;
      debugPrint('DVR: refresh after schedule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!ownsWork()) return null;
    notifyListeners();
    unawaited(refreshDvrStorage());
    for (final recording in _dvrRecordings) {
      if (recording.channelId != channelId) continue;
      final start = recording.scheduledStart;
      if (start == null) continue;
      if (startTime.difference(start).abs() <= const Duration(minutes: 1)) {
        return recording;
      }
    }
    return null;
  }

  /// Schedules a batch of one-shot DVR recordings and refreshes the local
  /// list once, after the whole loop completes. The single-item
  /// [scheduleDvrAiring] does this per call (applying it per item in a
  /// batch would mean N `getDvrRecordingsFor` round-trips, N
  /// `notifyListeners()` rebuilds, and N `refreshDvrStorage()` calls).
  ///
  /// Per-item failures (e.g. `XtreamDvrScheduleException` for the 422
  /// concurrent recording limit case) are captured into each
  /// [DvrAiringScheduleResult] rather than aborting the rest of the batch.
  ///
  /// Throws [StateError] when credentials are not configured (a wholesale
  /// precondition fail, not a per-item failure). Matches [scheduleDvrAiring].
  Future<List<DvrAiringScheduleResult>> scheduleDvrAirings(
    List<EpgShowEpisode> episodes,
  ) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return const <DvrAiringScheduleResult>[];

    final results = <DvrAiringScheduleResult>[];
    for (final episode in episodes) {
      if (!ownsWork()) break;
      try {
        await xtreamService.scheduleDvrFor(
          credentials,
          channelId: episode.channelId,
          title: episode.displayTitle,
          startTime: episode.startTime,
          endTime: episode.endTime,
        );
        results.add(DvrAiringScheduleResult(episode: episode, success: true));
      } on XtreamDvrScheduleException catch (error) {
        results.add(
          DvrAiringScheduleResult(
            episode: episode,
            success: false,
            errorMessage: error.message,
          ),
        );
      } on Object catch (error, stackTrace) {
        debugPrint('DVR: batch schedule item failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        results.add(
          DvrAiringScheduleResult(
            episode: episode,
            success: false,
            errorMessage: error.toString(),
          ),
        );
      }
    }

    // Ownership was lost partway through the loop above: report the
    // untried episodes as failed instead of silently dropping them from
    // the caller's success/failure count.
    for (final episode in episodes.skip(results.length)) {
      results.add(
        DvrAiringScheduleResult(
          episode: episode,
          success: false,
          errorMessage: 'Cancelled: DVR ownership changed mid-batch',
        ),
      );
    }

    if (!ownsWork()) return results;
    try {
      final recordings = await xtreamService.getDvrRecordingsFor(credentials);
      if (!ownsWork()) return results;
      _dvrRecordings = recordings;
      _recordingChannelIds = _extractRecordingChannelIds(recordings);
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return results;
      debugPrint('DVR: refresh after batch schedule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!ownsWork()) return results;
    notifyListeners();
    unawaited(refreshDvrStorage());
    return results;
  }

  static Set<int> _extractRecordingChannelIds(List<DvrRecording> recordings) {
    return recordings
        .where((recording) => recording.isInProgress)
        .map((recording) => recording.channelId)
        .whereType<int>()
        .toSet();
  }

  /// Splices freshly-fetched `active` (status=recording) entries into
  /// `_dvrRecordings` by uuid — inserting one this list doesn't know about
  /// yet, replacing one whose locally-known status disagrees with the
  /// server's. Returns null when every entry already matches, so a caller
  /// that finds nothing new doesn't force a `dvrRecordingsProvider` rebuild.
  ///
  /// This exists because [_onDvrStatusPush] is the only other writer of
  /// `_dvrRecordings`, and it only runs for pushes actually received. A
  /// `Scheduled -> Recording` push missed while disconnected previously left
  /// `_dvrRecordings` stuck on `Scheduled` even after `_recordingChannelIds`
  /// self-healed via this same function — the DVR Recordings screen and EPG
  /// recording badges (#185) are both backed by `_dvrRecordings`, not
  /// `_recordingChannelIds`.
  List<DvrRecording>? _mergeActiveDvrRecordings(List<DvrRecording> active) {
    List<DvrRecording>? next;
    for (final recording in active) {
      final source = next ?? _dvrRecordings;
      final index = source.indexWhere((r) => r.uuid == recording.uuid);
      if (index >= 0) {
        if (source[index].status == recording.status) continue;
        next ??= [..._dvrRecordings];
        next[index] = recording;
      } else {
        next ??= [..._dvrRecordings];
        next.insert(0, recording);
      }
    }
    return next;
  }

  /// Cancels a scheduled or in-progress DVR recording, keeping it in the
  /// local list with its refreshed (Cancelled) status — the server itself
  /// only marks the row cancelled and keeps history; deleting it is a
  /// separate, explicit action (see [deleteDvrRecording]). If the post-cancel
  /// detail fetch 404s (the row is already gone server-side for some other
  /// reason), drops it locally instead of leaving a stale pre-cancel row.
  Future<void> cancelDvrRecording(String uuid) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return;
    try {
      await xtreamService.cancelDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: cancel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    try {
      final detail = await xtreamService.getDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
      final next = [..._dvrRecordings];
      final index = next.indexWhere((recording) => recording.uuid == uuid);
      if (index >= 0) {
        next[index] = detail;
      } else {
        next.insert(0, detail);
      }
      _dvrRecordings = next;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh recording detail after cancel failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      _dvrRecordings = _dvrRecordings
          .where((recording) => recording.uuid != uuid)
          .toList(growable: false);
    }
    if (!ownsWork()) return;
    _recordingChannelIds = _extractRecordingChannelIds(_dvrRecordings);
    if (!ownsWork()) return;
    notifyListeners();
  }

  /// Deletes a completed/failed/cancelled DVR recording and removes it from
  /// the local list. Same fail-safe: 404 still drops the row locally.
  Future<void> deleteDvrRecording(String uuid) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork()) return;
    try {
      await xtreamService.deleteDvrRecordingFor(credentials, uuid);
      if (!ownsWork()) return;
    } on Object catch (error, stackTrace) {
      if (!ownsWork()) return;
      debugPrint('DVR: delete failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
    _dvrRecordings = _dvrRecordings
        .where((recording) => recording.uuid != uuid)
        .toList(growable: false);
    _recordingChannelIds = _extractRecordingChannelIds(_dvrRecordings);
    if (!ownsWork()) return;
    notifyListeners();
    unawaited(refreshDvrStorage());
  }

  /// Lightweight poll for which channels are currently recording, used to
  /// mark Live TV tiles without waiting for a full app refresh. Callers
  /// (e.g. LiveTvScreen) are expected to invoke this on a short timer only
  /// while the screen is visible — `status=recording` keeps the request
  /// small regardless of total recording history.
  Future<void> refreshActiveDvrRecordings() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsWork = _captureDvrOwnership(credentials);
    await _refreshActiveDvrRecordings(credentials, ownsWork);
  }

  Future<void> _refreshActiveDvrRecordings(
    UserCredentials credentials,
    bool Function() ownsWork,
  ) async {
    if (!ownsWork() || !hasDvrFeature) return;
    try {
      final active = await xtreamService.getDvrRecordingsFor(
        credentials,
        status: DvrRecordingStatus.recording,
        limit: 200,
      );
      if (!ownsWork()) return;

      final ids = _extractRecordingChannelIds(active);
      final idsChanged = !setEquals(_recordingChannelIds, ids);
      final merged = _mergeActiveDvrRecordings(active);

      if (!idsChanged && merged == null) return;
      if (!ownsWork()) return;
      if (idsChanged) _recordingChannelIds = ids;
      if (merged != null) _dvrRecordings = merged;
      if (!ownsWork()) return;
      notifyListeners();
    } on Object catch (error) {
      debugPrint('DVR: refresh active recordings failed: $error');
    }
  }

  /// Refreshes DVR storage usage against quota via `get_dvr_storage`.
  /// Older m3u-editor servers without this action fail the request, which
  /// we treat as "unsupported" — the storage display just stays hidden
  /// rather than surfacing an error.
  Future<void> refreshDvrStorage() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    final ownsWork = _captureDvrOwnership(credentials);
    if (!ownsWork() || !hasDvrFeature) return;
    try {
      final storageInfo = await xtreamService.getDvrStorageFor(credentials);
      if (!ownsWork()) return;
      _dvrStorageInfo = storageInfo;
    } on Object catch (error) {
      if (!ownsWork()) return;
      debugPrint('DVR: refresh storage failed: $error');
      if (!ownsWork()) return;
      _dvrStorageInfo = null;
    }
    if (!ownsWork()) return;
    notifyListeners();
  }

  /// Searches guest-enabled Arr integrations via `request_search`. Thin
  /// pass-through — the Requests screen owns its own search-in-flight/error
  /// state since results aren't part of the app's persistent state.
  Future<List<ContentRequestSearchResult>> searchContentRequests(
    String query, {
    String? type,
  }) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return const <ContentRequestSearchResult>[];
    final ownsWork = _captureMediaRequestOwnership(credentials);
    if (!ownsWork()) return const <ContentRequestSearchResult>[];
    final results = await xtreamService.searchContentRequestsFor(
      credentials,
      query,
      type: type,
    );
    if (!ownsWork()) return const <ContentRequestSearchResult>[];
    return results;
  }

  /// Submits a content request and adds it to the local requests list so it
  /// shows up immediately, without waiting for a `request.status` push.
  Future<MediaRequestSummary> submitContentRequest({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
    MediaRequestOwner? requestOwner,
  }) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureMediaRequestOwnership(
      credentials,
      owner: requestOwner,
    );
    if (!ownsWork()) {
      throw StateError('Xtream credentials not configured');
    }
    final request = await xtreamService.submitContentRequestFor(
      credentials,
      type: type,
      integrationId: integrationId,
      externalId: externalId,
      seasons: seasons,
    );
    if (!ownsWork()) return request;
    final next = [request, ..._mediaRequests];
    if (!ownsWork()) return request;
    _mediaRequests = next;
    if (!ownsWork()) return request;
    notifyListeners();
    return request;
  }

  /// Dismisses a completed or rejected request and removes it locally.
  Future<void> dismissMediaRequest(int requestId) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureMediaRequestOwnership(credentials);
    if (!ownsWork()) return;
    await xtreamService.dismissMediaRequest(requestId);
    if (!ownsWork()) return;
    final next = _mediaRequests
        .where((request) => request.id != requestId)
        .toList(growable: false);
    if (!ownsWork()) return;
    _mediaRequests = next;
    if (!ownsWork()) return;
    notifyListeners();
  }

  /// Refreshes the requesting guest's request history from the server. Used
  /// when the Requests screen becomes visible, since a push can be missed
  /// while the app is backgrounded and no other screen holds this list warm.
  Future<void> refreshMediaRequests() async {
    final credentials = authNotifier.credentials;
    if (credentials == null || !hasRequestsFeature) return;
    final ownsWork = _captureMediaRequestOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final requests = await xtreamService.getMediaRequests();
      if (!ownsWork()) return;
      _mediaRequests = requests;
      if (!ownsWork()) return;
      notifyListeners();
    } on Object catch (error) {
      debugPrint('Requests: refresh failed: $error');
    }
  }

  void updateProgressEntry(Progress updated) {
    final idx = _progressList.indexWhere((p) {
      if (p.contentType != updated.contentType) return false;
      if (updated.contentType == ContentType.aiostreams) {
        return p.aioItemId == updated.aioItemId;
      }
      return p.streamId == updated.streamId;
    });
    if (idx >= 0) {
      final next = List<Progress>.of(_progressList);
      next[idx] = updated;
      _progressList = next;
    } else {
      _progressList = [updated, ..._progressList];
    }
    notifyListeners();
  }

  Future<bool> _replaceWithXtreamContent({
    required bool clearCache,
    required int sourceGeneration,
    bool invalidateEpgFreshness = false,
    Future<void> Function()? persistSession,
    bool ownsSourceReplacementQueue = false,
    Future<void> Function()? rollbackSource,
  }) async {
    try {
      final liveCategoriesFuture = xtreamService.getLiveCategoriesUncached();
      final vodCategoriesFuture = xtreamService.getVodCategories();
      final seriesCategoriesFuture = xtreamService.getSeriesCategories();
      final channelsFuture = xtreamService.getLiveStreams();
      final vodItemsFuture = xtreamService.getVodStreams();
      final seriesFuture = xtreamService.getSeries();
      final recordingsFuture = hasDvrFeature
          ? xtreamService.getDvrRecordings().catchError(
              (Object _) => const <DvrRecording>[],
            )
          : Future<List<DvrRecording>>.value(const <DvrRecording>[]);
      final seriesRulesFuture = hasDvrFeature
          ? xtreamService.listDvrSeriesRules().catchError(
              (Object _) => const <DvrSeriesRule>[],
            )
          : Future<List<DvrSeriesRule>>.value(const <DvrSeriesRule>[]);
      final mediaRequestsFuture = hasRequestsFeature
          ? xtreamService.getMediaRequests().catchError(
              (Object _) => const <MediaRequestSummary>[],
            )
          : Future<List<MediaRequestSummary>>.value(
              const <MediaRequestSummary>[],
            );
      final viewersFuture = xtreamService.getViewers();

      // Only the browsing catalog and viewers gate the first paint. DVR
      // recordings/rules and media requests are fired in parallel above but
      // joined off the critical path in [_applyDvrAndRequestExtras] so a cold
      // cache does not make Movies wait on endpoints the grids never render.
      final results = await Future.wait<Object>(<Future<Object>>[
        liveCategoriesFuture,
        vodCategoriesFuture,
        seriesCategoriesFuture,
        channelsFuture,
        vodItemsFuture,
        seriesFuture,
        viewersFuture,
      ]);
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;

      final liveCategories = results[0] as List<Category>;
      final vodCategories = results[1] as List<Category>;
      final seriesCategories = results[2] as List<Category>;
      final channels = results[3] as List<Channel>;
      final vodItems = results[4] as List<VodItem>;
      final seriesList = results[5] as List<Series>;
      final viewers = results[6] as List<Viewer>;

      final activeViewer = await viewerService.resolveActiveViewer(
        viewers,
        loginKey: _currentLoginKey(),
        persist: false,
      );
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
      final fetched = activeViewer == null
          ? const <Progress>[]
          : await _loadRecentlyWatched(
              activeViewer.ulid,
              persist: false,
              isCurrent: () =>
                  !_sourceOperationGeneration.isStale(sourceGeneration),
            );
      if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
      // Keep local progress if the server returned nothing (e.g. sync lag).
      final progress = fetched.isEmpty && _progressList.isNotEmpty
          ? _progressList
          : fetched;

      Future<bool> commit() async {
        if (_sourceOperationGeneration.isStale(sourceGeneration)) return false;
        try {
          await cacheService.replace(<String, Object?>{
            'sourceType': 'xtream',
            'liveCategories': liveCategories,
            'vodCategories': vodCategories,
            'seriesCategories': seriesCategories,
            'liveStreams': channels,
            'vodStreams': vodItems,
            'seriesStreams': seriesList,
            'viewers': viewers,
          });
          if (_sourceOperationGeneration.isStale(sourceGeneration)) {
            await rollbackSource?.call();
            return false;
          }
          await secureStorage.write(
            _sourceKey,
            jsonEncode(<String, Object?>{'type': 'xtream'}),
          );
          if (_sourceOperationGeneration.isStale(sourceGeneration)) {
            await rollbackSource?.call();
            return false;
          }
          await persistSession?.call();
          if (_sourceOperationGeneration.isStale(sourceGeneration)) {
            await rollbackSource?.call();
            return false;
          }
          if (activeViewer != null) {
            await viewerService.setActiveViewer(
              activeViewer,
              loginKey: _currentLoginKey(),
            );
            if (_sourceOperationGeneration.isStale(sourceGeneration)) {
              await rollbackSource?.call();
              return false;
            }
          }

          final viewerGeneration = _viewerOperationGeneration.advance();
          final replacingXtreamSource =
              invalidateEpgFreshness && _sourceType == AppSourceType.xtream;
          if (replacingXtreamSource) {
            bool ownsReplacement() =>
                !_sourceOperationGeneration.isStale(sourceGeneration) &&
                !_viewerOperationGeneration.isStale(viewerGeneration);
            final synchronized =
                activeViewer != null &&
                await _syncFavoritesForActiveViewer(
                  activeViewer,
                  sourceGeneration: sourceGeneration,
                  viewerGeneration: viewerGeneration,
                  ownsWork: ownsReplacement,
                );
            if (!ownsReplacement()) {
              await rollbackSource?.call();
              return false;
            }
            if (!synchronized &&
                !await _applyServerFavorites(
                  const <Map<String, Object?>>[],
                  isCurrent: ownsReplacement,
                )) {
              await rollbackSource?.call();
              return false;
            }
          }

          if (invalidateEpgFreshness) {
            _resetEpgSession(
              clearGuide: _sourceType != AppSourceType.none,
            );
          }
          _sourceType = AppSourceType.xtream;
          _liveCategories = liveCategories;
          _vodCategories = vodCategories;
          _seriesCategories = seriesCategories;
          _channels = channels;
          _vodItems = vodItems;
          _seriesList = seriesList;
          // DVR recordings/rules and media requests land via
          // [_applyDvrAndRequestExtras] after this commit. On a fresh
          // connection drop the previous account's values now; on a
          // same-account refresh keep them until the refetch resolves so the
          // Home/DVR screens do not flicker to empty.
          if (clearCache) {
            _dvrRecordings = const <DvrRecording>[];
            _recordingChannelIds = const <int>{};
            _dvrSeriesRules = const <DvrSeriesRule>[];
            _mediaRequests = const <MediaRequestSummary>[];
          }
          _viewers = viewers;
          _activeViewer = activeViewer;
          _progressList = progress;
          _error = null;
          if (clearCache) aiostreamsApiService.clearCache();
          notifyListeners();
          unawaited(refreshDvrStorage());
          if (activeViewer != null) {
            if (!replacingXtreamSource) {
              _runBackgroundPersistence(
                _syncFavoritesForActiveViewer(
                  activeViewer,
                  sourceGeneration: sourceGeneration,
                  viewerGeneration: viewerGeneration,
                ),
              );
            }
            _runBackgroundPersistence(
              _refreshRecentlyWatchedForActiveViewer(
                activeViewer,
                sourceGeneration: sourceGeneration,
                viewerGeneration: viewerGeneration,
              ),
            );
          }

          // Prime EPG for the first screen's worth of channels only; the rest is
          // fetched lazily as screens request it via [ensureEpgForChannels] (e.g.
          // as the channel list scrolls into view). Fetching all channels' EPG
          // upfront was the main bottleneck on large playlists.
          unawaited(_loadXtreamEpg(channels.take(_epgPrimeCount).toList()));
          return true;
        } on Object {
          await rollbackSource?.call();
          rethrow;
        }
      }

      final bool loaded;
      if (ownsSourceReplacementQueue) {
        loaded = await commit();
      } else {
        _sourceReplacementOwners += 1;
        try {
          loaded = await _sourceReplacementQueue.run(commit);
        } finally {
          _sourceReplacementOwners -= 1;
        }
      }
      if (loaded && !_sourceOperationGeneration.isStale(sourceGeneration)) {
        _runBackgroundPersistence(
          _applyDvrAndRequestExtras(
            recordingsFuture,
            seriesRulesFuture,
            mediaRequestsFuture,
            sourceGeneration: sourceGeneration,
          ),
        );
      }
      return loaded;
    } on Object catch (error) {
      if (!_sourceOperationGeneration.isStale(sourceGeneration)) {
        _error = _redact(
          userFacingXtreamError(error),
          xtreamService.credentials,
        );
      }
      return false;
    }
  }

  /// Joins the DVR recordings/rules and media-request fetches started by
  /// [_replaceWithXtreamContent] after its content commit, so the browsing
  /// grids are never gated on endpoints they do not render. Each future
  /// already resolves to an empty list on failure (catchError at the call
  /// site), so [Future.wait] here never throws.
  Future<void> _applyDvrAndRequestExtras(
    Future<List<DvrRecording>> recordingsFuture,
    Future<List<DvrSeriesRule>> seriesRulesFuture,
    Future<List<MediaRequestSummary>> mediaRequestsFuture, {
    required int sourceGeneration,
  }) async {
    final results = await Future.wait<Object>(<Future<Object>>[
      recordingsFuture,
      seriesRulesFuture,
      mediaRequestsFuture,
    ]);
    if (_disposed || _sourceOperationGeneration.isStale(sourceGeneration)) {
      return;
    }
    final fetchedDvrRecordings = results[0] as List<DvrRecording>;
    final fetchedDvrSeriesRules = results[1] as List<DvrSeriesRule>;
    final mediaRequests = results[2] as List<MediaRequestSummary>;
    // Keep local DVR state if the server returned nothing (sync lag or a
    // transient failure swallowed by the catchError on each future), mirroring
    // the progress-list guard in [_replaceWithXtreamContent].
    final dvrRecordings =
        fetchedDvrRecordings.isEmpty && _dvrRecordings.isNotEmpty
        ? _dvrRecordings
        : fetchedDvrRecordings;
    final dvrSeriesRules =
        fetchedDvrSeriesRules.isEmpty && _dvrSeriesRules.isNotEmpty
        ? _dvrSeriesRules
        : fetchedDvrSeriesRules;
    _dvrRecordings = dvrRecordings;
    _recordingChannelIds = _extractRecordingChannelIds(dvrRecordings);
    _dvrSeriesRules = dvrSeriesRules;
    _mediaRequests = mediaRequests;
    notifyListeners();
  }

  Future<bool> _hydrateCachedXtreamContent({
    required int sourceGeneration,
  }) async {
    final source = await cacheService.get<String>('sourceType');
    if (source?.data != 'xtream') return false;

    final liveCategories =
        (await cacheService.get<List<Category>>('liveCategories'))?.data ??
        const <Category>[];
    final vodCategories =
        (await cacheService.get<List<Category>>('vodCategories'))?.data ??
        const <Category>[];
    final seriesCategories =
        (await cacheService.get<List<Category>>('seriesCategories'))?.data ??
        const <Category>[];
    final channels =
        (await cacheService.get<List<Channel>>('liveStreams'))?.data ??
        const <Channel>[];
    final vodItems =
        (await cacheService.get<List<VodItem>>('vodStreams'))?.data ??
        const <VodItem>[];
    final seriesList =
        (await cacheService.get<List<Series>>('seriesStreams'))?.data ??
        const <Series>[];
    final viewers =
        (await cacheService.get<List<Viewer>>('viewers'))?.data ??
        const <Viewer>[];
    final hasContent =
        liveCategories.isNotEmpty ||
        vodCategories.isNotEmpty ||
        seriesCategories.isNotEmpty ||
        channels.isNotEmpty ||
        vodItems.isNotEmpty ||
        seriesList.isNotEmpty;
    if (!hasContent) return false;

    final viewerGeneration = _viewerOperationGeneration.advance();
    final activeViewer = await viewerService.resolveActiveViewer(
      viewers,
      loginKey: _currentLoginKey(),
    );
    if (_sourceOperationGeneration.isStale(sourceGeneration) ||
        _viewerOperationGeneration.isStale(viewerGeneration)) {
      return false;
    }
    final progress = activeViewer == null
        ? const <Progress>[]
        : await resumeService.all(activeViewer.ulid);
    if (_sourceOperationGeneration.isStale(sourceGeneration) ||
        _viewerOperationGeneration.isStale(viewerGeneration)) {
      return false;
    }
    _sourceType = AppSourceType.xtream;
    _liveCategories = liveCategories;
    _vodCategories = vodCategories;
    _seriesCategories = seriesCategories;
    _channels = channels;
    _vodItems = vodItems;
    _seriesList = seriesList;
    _dvrRecordings = const <DvrRecording>[];
    _dvrStorageInfo = null;
    _recordingChannelIds = const <int>{};
    _dvrSeriesRules = const <DvrSeriesRule>[];
    _mediaRequests = const <MediaRequestSummary>[];
    _viewers = viewers;
    _activeViewer = activeViewer;
    _progressList = progress;
    _error = null;
    final currentViewer = _activeViewer;
    if (currentViewer != null) {
      _runBackgroundPersistence(
        _syncFavoritesForActiveViewer(
          currentViewer,
          sourceGeneration: _sourceOperationGeneration.current,
          viewerGeneration: _viewerOperationGeneration.current,
        ),
      );
    }
    unawaited(refreshDvrStorage());
    return true;
  }

  Future<void> _refreshRecentlyWatchedForActiveViewer(
    Viewer viewer, {
    required int sourceGeneration,
    required int viewerGeneration,
  }) async {
    bool isCurrent() => _ownsXtreamViewer(
      viewer,
      sourceGeneration: sourceGeneration,
      viewerGeneration: viewerGeneration,
    );
    if (!isCurrent()) return;
    try {
      final progress = await _loadRecentlyWatchedDeduped(
        viewer.ulid,
        sourceGeneration: sourceGeneration,
        viewerGeneration: viewerGeneration,
        isCurrent: isCurrent,
      );
      if (!isCurrent()) return;
      if (progress.isEmpty && _progressList.isNotEmpty) return;
      _progressList = progress;
      notifyListeners();
    } on Object catch (_) {}
  }

  Future<List<Progress>> _loadRecentlyWatchedDeduped(
    String viewerId, {
    required int sourceGeneration,
    required int viewerGeneration,
    required bool Function() isCurrent,
  }) {
    final inFlight = _recentlyWatchedRefresh;
    if (inFlight != null &&
        _recentlyWatchedRefreshViewerId == viewerId &&
        _recentlyWatchedRefreshSourceGeneration == sourceGeneration &&
        _recentlyWatchedRefreshViewerGeneration == viewerGeneration) {
      return inFlight;
    }
    late final Future<List<Progress>> future;
    _recentlyWatchedRefreshViewerId = viewerId;
    _recentlyWatchedRefreshSourceGeneration = sourceGeneration;
    _recentlyWatchedRefreshViewerGeneration = viewerGeneration;
    future = _loadRecentlyWatched(viewerId, isCurrent: isCurrent).whenComplete(
      () {
        if (identical(_recentlyWatchedRefresh, future)) {
          _recentlyWatchedRefresh = null;
          _recentlyWatchedRefreshViewerId = null;
          _recentlyWatchedRefreshSourceGeneration = null;
          _recentlyWatchedRefreshViewerGeneration = null;
        }
      },
    );
    _recentlyWatchedRefresh = future;
    return future;
  }

  Future<List<Progress>> _loadRecentlyWatched(
    String viewerId, {
    bool persist = true,
    bool Function()? isCurrent,
  }) async {
    bool ownsWork() => isCurrent?.call() ?? true;
    if (!ownsWork()) return const <Progress>[];
    final remote = await xtreamService.getRecentlyWatched(viewerId);
    if (!ownsWork()) return const <Progress>[];
    final local = await resumeService.all(viewerId);
    if (!ownsWork()) return const <Progress>[];

    // First time this viewer has anything server-side (e.g. a fresh per-auth
    // viewer created after upgrading from before per-auth viewer isolation
    // was enforced, so old progress is sitting under the admin viewer
    // instead): treat the device's local cache as the source of truth and
    // seed the server from it via the existing single-item write path. Safe
    // because it only ever fires while the server has nothing at all for
    // this viewer, and is naturally self-limiting — once seeded, remote is
    // no longer empty, so this never runs again for this viewer.
    if (persist && remote.isEmpty && local.isNotEmpty) {
      for (final p in local) {
        if (!ownsWork()) return const <Progress>[];
        try {
          await xtreamService.updateProgress(p);
          if (!ownsWork()) return const <Progress>[];
        } on Object catch (error) {
          debugPrint('Progress: seed push failed for viewer $viewerId: $error');
        }
        if (!ownsWork()) return const <Progress>[];
      }
      return ownsWork() ? local : const <Progress>[];
    }

    // Regular items: keyed by (contentType, streamId).
    // AIO items: keyed separately by aioItemId — all AIO items share streamId=0
    // so a single map would collapse them.
    final localMap = {
      for (final p in local)
        if (p.contentType != ContentType.aiostreams)
          (p.contentType, p.streamId): p,
    };
    final localAioMap = {
      for (final p in local)
        if (p.contentType == ContentType.aiostreams && p.aioItemId != null)
          p.aioItemId!: p,
    };

    // For each remote entry, prefer the local copy when it has richer metadata
    // (thumbnail, title, etc. captured at playback time). Always adopt the
    // server's position and completion flag as authoritative. For AIO items the
    // server already stores all metadata, so server values win for those fields.
    final result = <Progress>[
      for (final r in remote)
        () {
          final l = r.contentType == ContentType.aiostreams
              ? localAioMap[r.aioItemId]
              : localMap[(r.contentType, r.streamId)];
          if (l != null && l.title != null && l.title!.isNotEmpty) {
            return Progress(
              viewerId: l.viewerId,
              contentType: l.contentType,
              streamId: l.streamId,
              positionSeconds: r.positionSeconds,
              durationSeconds: r.durationSeconds ?? l.durationSeconds,
              completed: r.completed,
              seriesId: l.seriesId ?? r.seriesId,
              seasonNumber: l.seasonNumber ?? r.seasonNumber,
              episodeNumber: l.episodeNumber ?? r.episodeNumber,
              title: l.title,
              // Prefer server value for episodeTitle — it may have been backfilled
              // after the local entry was cached.
              episodeTitle: r.episodeTitle ?? l.episodeTitle,
              seriesName: l.seriesName ?? r.seriesName,
              // Prefer server value for thumbnail/backdrop — like
              // episodeTitle below, the image URL may have been backfilled
              // or regenerated after the local entry was cached, and unlike
              // title/seriesName a stale image URL can silently 404 forever
              // since nothing else ever re-syncs it.
              thumbnailUrl: r.thumbnailUrl ?? l.thumbnailUrl,
              backdropUrl: r.backdropUrl ?? l.backdropUrl,
              rating: r.rating ?? l.rating,
              runtime: r.runtime ?? l.runtime,
              plot: r.plot ?? l.plot,
              genre: r.genre ?? l.genre,
              year: r.year ?? l.year,
              aioItemId: l.aioItemId ?? r.aioItemId,
              aioIntegrationId: l.aioIntegrationId ?? r.aioIntegrationId,
            );
          }
          return r;
        }(),
    ];

    // Remote is authoritative for all content types. Items absent from the
    // server response were either cleared or are beyond the top-20 window —
    // either way, don't show them. Persist so future metadata lookups are fast.
    if (persist) {
      for (final p in result) {
        if (!ownsWork()) return const <Progress>[];
        if (!await resumeService.save(p, shouldCommit: ownsWork)) {
          return const <Progress>[];
        }
      }
    }

    return ownsWork() ? result : const <Progress>[];
  }

  bool _ownsXtreamViewer(
    Viewer viewer, {
    required int sourceGeneration,
    required int viewerGeneration,
  }) =>
      !_sourceOperationGeneration.isStale(sourceGeneration) &&
      !_viewerOperationGeneration.isStale(viewerGeneration) &&
      _sourceType == AppSourceType.xtream &&
      _activeViewer?.ulid == viewer.ulid;

  /// Queues [channels] for a lazy, debounced EPG fetch — only channels
  /// without fresh cached data are requested. Call this from a screen's
  /// `itemBuilder` (list/grid) so only currently visible channels get fetched
  /// as the user scrolls, instead of fetching the whole channel list upfront.
  void ensureEpgForChannels(
    List<Channel> channels, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (_sourceType != AppSourceType.xtream) return;
    final rangeKey = _epgRangeKey(startDate, endDate);
    final returningToCurrentGuide =
        rangeKey.isEmpty && _activeEpgRangeKey.isNotEmpty;
    if (rangeKey != _activeEpgRangeKey) {
      _activeEpgRangeKey = rangeKey;
      _pendingEpgStartDate = startDate;
      _pendingEpgEndDate = endDate;
      _pendingEpgChannelIds.clear();
      _pendingForcedEpgChannelIds.clear();
      _epgFetchDebounce?.cancel();
      _epgRequestGeneration += 1;
    }
    var added = false;
    for (final channel in channels) {
      if (rangeKey.isEmpty) {
        final forceRefresh =
            returningToCurrentGuide &&
            epgService.programsForChannel(channel).isEmpty;
        if (!forceRefresh && !epgService.shouldFetchDataForChannel(channel)) {
          continue;
        }
        if (forceRefresh) _pendingForcedEpgChannelIds.add(channel.id);
      } else {
        if (_hasFreshEpgRange(channel.id, rangeKey) ||
            !epgService.shouldFetchData(_epgRangeFetchId(channel, rangeKey))) {
          continue;
        }
      }
      if (_pendingEpgChannelIds.add(channel.id)) added = true;
    }
    if (!added) return;
    _epgFetchDebounce?.cancel();
    _epgFetchDebounce = Timer(_epgFetchDebounceDelay, _flushPendingEpgFetch);
  }

  Future<void> _flushPendingEpgFetch() async {
    if (_pendingEpgChannelIds.isEmpty) return;
    final ids = _pendingEpgChannelIds.toSet();
    _pendingEpgChannelIds.clear();
    final forcedIds = _pendingForcedEpgChannelIds.intersection(ids);
    _pendingForcedEpgChannelIds.removeAll(ids);
    final startDate = _pendingEpgStartDate;
    final endDate = _pendingEpgEndDate;
    final rangeKey = _activeEpgRangeKey;
    final generation = _epgRequestGeneration;
    final channels = _channels
        .where((channel) => ids.contains(channel.id))
        .where(
          (channel) => rangeKey.isEmpty
              ? forcedIds.contains(channel.id) ||
                    epgService.shouldFetchDataForChannel(channel)
              : !_hasFreshEpgRange(channel.id, rangeKey) &&
                    epgService.shouldFetchData(
                      _epgRangeFetchId(channel, rangeKey),
                    ),
        )
        .toList(growable: false);
    if (channels.isEmpty) return;
    final channelIds = channels.map(_epgChannelId).toList(growable: false);
    final fetchIds = rangeKey.isEmpty
        ? channelIds
        : channels
              .map((channel) => _epgRangeFetchId(channel, rangeKey))
              .toList(growable: false);
    final sourceGeneration = epgService.markFetchStarted(fetchIds);
    try {
      final programs = await xtreamService.getEpgBatch(
        channels,
        startDate: startDate,
        endDate: endDate,
      );
      if (generation != _epgRequestGeneration ||
          rangeKey != _activeEpgRangeKey) {
        epgService.markFetchFailed(
          fetchIds,
          sourceGeneration: sourceGeneration,
        );
        return;
      }
      if (rangeKey.isEmpty) {
        epgService.applySuccessfulResponse(
          channelIds,
          programs,
          sourceGeneration: sourceGeneration,
        );
      } else {
        _markEpgRangeFetched(channels, rangeKey);
        epgService
          ..mergePrograms(
            programs,
            channelIds: channelIds,
            replaceExisting: false,
            markFresh: false,
          )
          ..markFetched(fetchIds);
      }
      if (kDebugMode) {
        debugPrint(
          '[EPG] lazy fetch → ${programs.length} programs for ${channels.length} channels',
        );
      }
    } on Object catch (e) {
      epgService.markFetchFailed(
        fetchIds,
        sourceGeneration: sourceGeneration,
      );
      if (generation != _epgRequestGeneration ||
          rangeKey != _activeEpgRangeKey) {
        return;
      }
      if (kDebugMode) debugPrint('[EPG] lazy fetch failed: $e');
    }
  }

  Future<void> _loadXtreamEpg(List<Channel> channels) async {
    final generation = _epgRequestGeneration;
    final channelsToFetch = channels
        .where(epgService.shouldFetchDataForChannel)
        .toList(growable: false);
    if (channelsToFetch.isEmpty) return;
    final channelIds = channelsToFetch
        .map(_epgChannelId)
        .toList(growable: false);
    final sourceGeneration = epgService.markFetchStarted(channelIds);
    try {
      final programs = await xtreamService.getEpgBatch(channelsToFetch);
      if (generation != _epgRequestGeneration) {
        epgService.markFetchFailed(
          channelIds,
          sourceGeneration: sourceGeneration,
        );
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[EPG] getEpgBatch → ${programs.length} programs for ${channelsToFetch.length} channels',
        );
      }
      epgService.applySuccessfulResponse(
        channelIds,
        programs,
        sourceGeneration: sourceGeneration,
      );
    } on Object catch (e) {
      epgService.markFetchFailed(
        channelIds,
        sourceGeneration: sourceGeneration,
      );
      if (kDebugMode) debugPrint('[EPG] getEpgBatch failed: $e');
      // Don't clear existing EPG data on a batch failure. A transient network
      // error shouldn't wipe a previously loaded guide.
    }
  }

  String _epgChannelId(Channel channel) =>
      channel.epgChannelId ?? channel.tvgName ?? channel.name;

  String _epgRangeFetchId(Channel channel, String rangeKey) =>
      '${_epgChannelId(channel)}:$rangeKey';

  String _epgRangeKey(DateTime? startDate, DateTime? endDate) {
    if (startDate == null) return '';
    String dateKey(DateTime value) =>
        '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return '${dateKey(startDate)}:${dateKey(endDate ?? startDate)}';
  }

  bool _hasFreshEpgRange(int channelId, String rangeKey) {
    final key = '$channelId:$rangeKey';
    final fetchedAt = _fetchedEpgRanges[key];
    if (fetchedAt == null) return false;
    final elapsed = epgService.now.difference(fetchedAt);
    if (!elapsed.isNegative && elapsed < epgService.cacheTtl) return true;
    _fetchedEpgRanges.remove(key);
    return false;
  }

  void _markEpgRangeFetched(List<Channel> channels, String rangeKey) {
    final now = epgService.now;
    for (final channel in channels) {
      _fetchedEpgRanges['${channel.id}:$rangeKey'] = now;
    }
  }

  void _resetEpgSession({bool clearGuide = true}) {
    _epgRequestGeneration += 1;
    _epgFetchDebounce?.cancel();
    _epgFetchDebounce = null;
    _pendingEpgChannelIds.clear();
    _pendingForcedEpgChannelIds.clear();
    _fetchedEpgRanges.clear();
    _pendingEpgStartDate = null;
    _pendingEpgEndDate = null;
    _activeEpgRangeKey = '';
    epgService.invalidateSourceFetchState();
    if (clearGuide) epgService.clear();
  }

  Future<AppSourceType> _readSavedSourceType() async {
    final raw = await secureStorage.read(_sourceKey);
    if (raw == null) return AppSourceType.none;
    try {
      jsonDecode(raw);
      return AppSourceType.xtream;
    } on Object catch (_) {
      return AppSourceType.none;
    }
  }

  String _redact(String message, UserCredentials? credentials) {
    if (credentials == null) return message;
    var redacted = message;
    if (credentials.password.isNotEmpty) {
      redacted = redacted.replaceAll(credentials.password, '[redacted]');
    }
    if (credentials.username.length > 2) {
      redacted = redacted.replaceAll(credentials.username, '[redacted]');
    }
    return redacted;
  }

  bool _sameCredentials(UserCredentials? first, UserCredentials? second) =>
      first != null &&
      second != null &&
      first.server == second.server &&
      first.username == second.username &&
      first.password == second.password;

  void _clearNotificationOwner() {
    notificationStore.clearOwner();
    _unreadNotificationCount = 0;
    _activatedNotificationIds.clear();
  }

  // Scopes ViewerService's saved active-viewer ulid to this server+login so
  // switching logins on the same device can never reuse a viewer ulid saved
  // under a different login.
  String? _currentLoginKey() {
    final credentials = authNotifier.credentials;
    if (credentials == null) return null;
    return '${credentials.server}|${credentials.username}';
  }

  // Bounded like TvNotificationStore's own cap, so a long-running session
  // can't grow this set without limit.
  bool _markNotificationActivated(String id) {
    if (_activatedNotificationIds.contains(id)) return false;
    if (_activatedNotificationIds.length >= _maxActivatedNotificationIds) {
      _activatedNotificationIds.remove(_activatedNotificationIds.first);
    }
    _activatedNotificationIds.add(id);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _epgRequestGeneration += 1;
    _epgFetchDebounce?.cancel();
    _dvrContentRefreshDebounce?.cancel();
    _pushTokenSubscription?.cancel().ignore();
    unawaited(_tvNotificationController.close());
    unawaited(_notificationActivationController.close());
    unawaited(_pushNotificationService.dispose());
    super.dispose();
  }
}
