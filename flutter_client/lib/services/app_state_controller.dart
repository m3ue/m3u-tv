import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart' show Locale;
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_log_buffer.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/device_identity_service.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/diagnostics_report.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/dvr_coordinator.dart';
import 'package:m3u_tv/services/epg_coordinator.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/requests_coordinator.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/feature_flags.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';

export 'package:m3u_tv/services/dvr_coordinator.dart'
    show DvrAiringScheduleResult;

enum AppSourceType { none, xtream }

typedef MediaRequestOwner = ({
  int sourceGeneration,
  int notificationGeneration,
  AppSourceType sourceType,
  UserCredentials? credentials,
});

class AppStateController extends ChangeNotifier {
  factory AppStateController({
    AuthNotifier? authNotifier,
    XtreamService? xtreamService,
    SecureStorage? secureStorage,
    CacheService? cacheService,
    CatalogRepository? catalogRepository,
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
    IntroDbSettings? introDbSettings,
    PushNotificationService? pushNotificationService,
    DevicePairingService? devicePairingService,
    DeviceIdentityService? deviceIdentityService,
    ViewSettingsService? viewSettingsService,
    bool windowedLiveTv = kWindowedLiveTv,
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
    // The catalog is always SQLite-backed. Production passes the on-disk repo;
    // when a caller (chiefly tests) omits it, fall back to a private in-memory
    // database so there is exactly one catalog code path - never a JSON one.
    final resolvedCatalogRepository =
        catalogRepository ??
        cacheService?.catalogRepository ??
        CatalogRepository(CatalogDatabase.memory());
    final resolvedCacheService =
        cacheService ??
        CacheService(
          store: resolvedCacheStore,
          catalogRepository: resolvedCatalogRepository,
        );
    final resolvedXtreamService =
        xtreamService ??
        authNotifier?.xtreamService ??
        XtreamService(cache: resolvedCacheService);
    final resolvedDeviceIdentityService =
        deviceIdentityService ??
        DeviceIdentityService(storage: resolvedSecureStorage);
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
      catalogRepository: resolvedCatalogRepository,
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
      deviceIdentityService: resolvedDeviceIdentityService,
      tvNotificationService:
          tvNotificationService ??
          TvNotificationService(deviceIdentity: resolvedDeviceIdentityService),
      notificationStore:
          tvNotificationStore ?? TvNotificationStore(store: store),
      reverbService: reverbService ?? ReverbService(),
      aioFavoritesService:
          aioFavoritesService ?? AIOStreamsFavoritesService(store: store),
      proxyPlaybackSettings:
          proxyPlaybackSettings ?? ProxyPlaybackSettings(store: store),
      comskipSettings: comskipSettings ?? ComskipSettings(store: store),
      introDbSettings: introDbSettings ?? IntroDbSettings(store: store),
      pushNotificationService:
          pushNotificationService ?? PushNotificationService(),
      viewSettingsService:
          viewSettingsService ?? ViewSettingsService(store: store),
      windowedLiveTv: windowedLiveTv,
    );
  }

  AppStateController._({
    required this.authNotifier,
    required this.xtreamService,
    required this.secureStorage,
    required this.cacheService,
    required this._catalogRepository,
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
    required this.deviceIdentityService,
    required this._tvNotificationService,
    required this.notificationStore,
    required this._reverbService,
    required this.aioFavoritesService,
    required this.proxyPlaybackSettings,
    required this.comskipSettings,
    required this.introDbSettings,
    required this._pushNotificationService,
    required this.viewSettingsService,
    required this.windowedLiveTv,
  }) {
    epgService
      ..cacheTtl = cacheService.refreshInterval
      // SQLite is the guide's store of record; memory keeps now/next for
      // every channel and full schedules only for recently viewed ones.
      ..attachStore(_catalogRepository);
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
    authNotifier.addListener(_registerLogSecrets);
    _registerLogSecrets();
  }

  /// Scrubs the active username/password from every captured log line, on
  /// top of the buffer's generic URL patterns, so an uploaded report can
  /// never carry them.
  void _registerLogSecrets() {
    final credentials = authNotifier.credentials;
    AppLogBuffer.instance
      ..registerSecret(credentials?.username)
      ..registerSecret(credentials?.password);
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
  final DeviceIdentityService deviceIdentityService;

  /// The app-state file (credentials, settings, favorites, resume progress)
  /// and the content-cache file. Equal when a test forces a single store; a
  /// one-time key migration between them runs in [boot].
  final PersistentJsonStore _appStateStore;
  final PersistentJsonStore _cacheStore;
  final SecureStorage secureStorage;
  final CacheService cacheService;

  /// SQLite-backed catalog store. Always present - production opens it on disk,
  /// tests get a private in-memory database. Owned here so [dispose] can close
  /// it.
  final CatalogRepository _catalogRepository;

  /// When true (see [kWindowedLiveTv]) the live lineup lives only in the
  /// SQLite catalog: [channels] stays empty and the Live TV surfaces page
  /// their rows from [catalogRepository].
  final bool windowedLiveTv;
  final FavoritesService favoritesService;
  final FavoritesService vodFavoritesService;
  final FavoritesService seriesFavoritesService;
  final ResumeService resumeService;
  final AIOStreamsFavoritesService aioFavoritesService;
  final ProxyPlaybackSettings proxyPlaybackSettings;
  final ComskipSettings comskipSettings;
  final IntroDbSettings introDbSettings;
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

  /// Progress ticks for the background EPG sweep (`_sweepXtreamEpgInBackground`)
  /// - a `null` event means the sweep finished (or was superseded/disposed)
  /// and any progress UI should dismiss. This is separate from
  /// [tvNotifications] because sweep ticks are frequent, purely informational,
  /// and must never reach the desktop-notification dispatcher (which would
  /// spam OS notifications); the UI should only ever show them as an in-app
  /// toast.
  Stream<EpgSweepProgress?> get epgSweepProgress => _epg.sweepProgress;

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

  /// Device header for the Logs & Diagnostics screen and its uploads.
  Future<String> diagnosticsHeader({required String layout}) async {
    DeviceIdentity? identity;
    try {
      identity = await deviceIdentityService.resolve();
    } on Object catch (_) {
      identity = null;
    }
    final server = authNotifier.credentials?.server;
    return buildDiagnosticsHeader(
      layout: layout,
      identity: identity,
      serverHost: server == null
          ? null
          : Uri.tryParse(normalizeServerUrl(server))?.host,
    );
  }

  /// Uploads a Logs & Diagnostics report to the connected editor. Returns the
  /// stored upload's id, shown to the user so they can point an admin at it.
  Future<int> uploadDiagnosticLogs(String report) {
    final credentials = authNotifier.credentials;
    if (credentials == null) {
      throw StateError('Not connected');
    }
    return _tvNotificationService.uploadLogs(credentials, report);
  }

  /// Applies the per-device proxy playback preferences (enable proxy +
  /// live/VOD transcoding profile) to a backend stream URL. External URLs
  /// (e.g. AIOStreams sources) pass through unchanged. Every player of an
  /// editor stream (full-screen, the EPG preview) must go through this, so
  /// they request the same proxy stream and can share it.
  String applyProxyPlayback(String streamUrl, {required String type}) {
    final proxy = authNotifier.authResponse?.proxy;
    final server = xtreamService.credentials?.server;
    if (proxy == null || server == null) return streamUrl;
    return proxyPlaybackSettings.apply(
      streamUrl,
      type: type,
      forced: proxy.forced,
      serverBase: server,
    );
  }

  /// Whether [applyProxyPlayback] sends [streamUrl] through an explicit
  /// transcoding profile (see [ProxyPlaybackSettings.isTranscoding]).
  bool isTranscodedPlayback(String streamUrl, {required String type}) {
    final proxy = authNotifier.authResponse?.proxy;
    final server = xtreamService.credentials?.server;
    if (proxy == null || server == null) return false;
    return proxyPlaybackSettings.isTranscoding(
      streamUrl,
      type: type,
      forced: proxy.forced,
      serverBase: server,
    );
  }

  /// Stops the editor proxy stream a player session opened as [clientId]
  /// (see `EditorStreamSessionGateway`). No-op when not connected.
  Future<void> stopPlayerStream({
    required String type,
    required int streamId,
    required String clientId,
  }) async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return;
    await _tvNotificationService.stopPlayerStream(
      credentials,
      type: type,
      streamId: streamId,
      clientId: clientId,
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
  List<Progress> _progressList = const <Progress>[];
  Future<List<Progress>>? _recentlyWatchedRefresh;
  String? _recentlyWatchedRefreshViewerId;
  int? _recentlyWatchedRefreshSourceGeneration;
  int? _recentlyWatchedRefreshViewerGeneration;
  // Cancelling the debounce timer in [dispose] only helps if it hasn't fired
  // yet. Once [_flushDvrContentRefresh] is in flight its awaits can outlive
  // us, and it runs from a fire-and-forget Timer callback, so a
  // notifyListeners() on a disposed notifier would surface as an unhandled
  // async error rather than being caught anywhere.
  bool _disposed = false;

  /// Owns the guest's media requests list and its server calls.
  late final RequestsCoordinator _requests = RequestsCoordinator(
    xtreamService: xtreamService,
    credentials: () => authNotifier.credentials,
    captureOwnership: _captureMediaRequestOwnership,
    hasRequestsFeature: () => hasRequestsFeature,
    notifyListeners: notifyListeners,
  );

  /// Owns the DVR recordings/rules/storage state and its server calls.
  late final DvrCoordinator _dvr = DvrCoordinator(
    xtreamService: xtreamService,
    catalogRepository: _catalogRepository,
    credentials: () => authNotifier.credentials,
    captureOwnership: _captureDvrOwnership,
    hasDvrFeature: () => hasDvrFeature,
    notifyListeners: notifyListeners,
  );

  /// Owns the guide's fetch, sweep, persist and restore lifecycle.
  late final EpgCoordinator _epg = EpgCoordinator(
    epgService: epgService,
    xtreamService: xtreamService,
    cacheService: cacheService,
    sourceOperationGeneration: _sourceOperationGeneration,
    isXtreamSource: () => _sourceType == AppSourceType.xtream,
    channelPage: (offset, limit) => _catalogRepository.pageActiveItems<Channel>(
      kind: kCatalogKindLive,
      offset: offset,
      limit: limit,
    ),
    channelCount: () =>
        _catalogRepository.countActiveItems(kind: kCatalogKindLive),
    isLoadingContent: () => _isLoadingContent,
    notifyListeners: notifyListeners,
  );

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

  /// The whole live lineup in memory, or empty when [windowedLiveTv].
  List<Channel> get channels => _channels;

  /// SQLite catalog store (always present). VOD/series content lives here
  /// exclusively, and the live lineup too when [windowedLiveTv]; otherwise
  /// [channels] is the one full in-memory catalog list left.
  CatalogRepository get catalogRepository => _catalogRepository;
  List<DvrRecording> get dvrRecordings => _dvr.recordings;
  DvrStorageInfo? get dvrStorageInfo => _dvr.storageInfo;
  Set<int> get recordingChannelIds => _dvr.recordingChannelIds;
  List<DvrSeriesRule> get dvrSeriesRules => _dvr.seriesRules;
  List<Progress> get progressList => _progressList;
  List<MediaRequestSummary> get mediaRequests => _requests.requests;
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
    unawaited(introDbSettings.load());

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
      _epg.resetSession();
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
    if (_disposed || _sourceOperationGeneration.isStale(sourceGeneration)) {
      return;
    }
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
    // Resolve a bare host (scheme loosened on the connect form) to an absolute
    // URL up front so the notification/Reverb path downstream keys off the same
    // value the Xtream client normalizes to internally.
    final normalized = credentials.normalized();
    final sourceGeneration = _sourceOperationGeneration.advance();
    final rollbackGeneration = _sourceRollbackGeneration.current;
    if (_sourceReplacementOwners == 0) {
      return _connectXtream(
        normalized,
        sourceGeneration,
        rollbackGeneration: rollbackGeneration,
        ownsQueue: false,
      );
    }
    return _sourceReplacementQueue.run(() async {
      _sourceReplacementOwners += 1;
      try {
        return await _connectXtream(
          normalized,
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
            _dvr.onStatusPush(recording, credentials, ownsDvr),
        onRequestStatus: (request) =>
            _requests.onStatusPush(request, ownsRequests),
        onFavoriteToggled: _onFavoriteTogglePush,
        onDeviceDeregister: _onDeviceDeregisterPush,
        // Reconciles any status pushes missed while disconnected (app
        // suspended, network drop) — cheap, status-filtered fetch, not a poll.
        onConnected: () => unawaited(
          _dvr.refreshActiveWith(credentials, ownsDvr),
        ),
      );
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
  }

  /// Fetches the server's unread notification list. Used on live-stream end so
  /// an eviction notice ("A DVR recording has taken precedence...") can be shown
  /// as a toast even when the Reverb push channel is down - the notification
  /// is persisted server-side and only the push delivery is unreliable.
  Future<List<TvNotificationItem>> fetchUnreadNotifications() async {
    final credentials = authNotifier.credentials;
    if (credentials == null) return const [];
    try {
      final (_, unread) = await _tvNotificationService.fetchUnread(credentials);
      return unread;
    } on Object {
      return const [];
    }
  }

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
    if (session.deviceRevoked) {
      // An admin revoked this install in the editor. Drop to the pairing
      // screen; the credential itself still works so the user can re-pair.
      unawaited(disconnect());
      return null;
    }
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
      final identity = await _bestEffortIdentity();
      await _pushNotificationService.registerToken(
        credentials,
        token: token,
        platform: HostPlatform.isIOS ? 'ios' : 'android',
        deviceId: identity?.deviceId,
        deviceName: identity?.deviceName,
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

  /// Handles a `device.deregister` push. The event is broadcast to the whole
  /// playlist channel, so every device sees it — only the one whose id matches
  /// signs out and returns to the pairing screen.
  void _onDeviceDeregisterPush(String deviceId) {
    unawaited(() async {
      final myId = await _bestEffortIdentity().then((i) => i?.deviceId);
      if (myId != null && myId == deviceId) {
        await disconnect();
      }
    }());
  }

  Future<DeviceIdentity?> _bestEffortIdentity() async {
    try {
      return await deviceIdentityService.resolve();
    } on Object catch (_) {
      return null;
    }
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
      return await _pullFavorites(viewer, isCurrent: isCurrent);
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
    _epg.resetSession();
    _sourceType = AppSourceType.none;
    _viewers = const <Viewer>[];
    _viewerOperationGeneration.advance();
    _activeViewer = null;
    _liveCategories = const <Category>[];
    _vodCategories = const <Category>[];
    _seriesCategories = const <Category>[];
    _channels = const <Channel>[];
    _dvr.reset();
    _requests.reset();
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

  /// See [DvrCoordinator.refreshDvrSeriesRules].
  Future<void> refreshDvrSeriesRules() => _dvr.refreshDvrSeriesRules();

  /// See [DvrCoordinator.refreshDvrRecordings].
  Future<void> refreshDvrRecordings() => _dvr.refreshDvrRecordings();

  /// See [DvrCoordinator.scheduleDvrAiring].
  Future<DvrRecording?> scheduleDvrAiring({
    required int channelId,
    required String title,
    required DateTime startTime,
    required DateTime endTime,
  }) => _dvr.scheduleDvrAiring(
    channelId: channelId,
    title: title,
    startTime: startTime,
    endTime: endTime,
  );

  /// See [DvrCoordinator.scheduleDvrAirings].
  Future<List<DvrAiringScheduleResult>> scheduleDvrAirings(
    List<EpgShowEpisode> episodes,
  ) => _dvr.scheduleDvrAirings(episodes);

  /// See [DvrCoordinator.cancelDvrRecording].
  Future<void> cancelDvrRecording(String uuid) => _dvr.cancelDvrRecording(uuid);

  /// See [DvrCoordinator.deleteDvrRecording].
  Future<void> deleteDvrRecording(String uuid) => _dvr.deleteDvrRecording(uuid);

  /// See [DvrCoordinator.refreshActiveDvrRecordings].
  Future<void> refreshActiveDvrRecordings() =>
      _dvr.refreshActiveDvrRecordings();

  /// See [DvrCoordinator.refreshDvrStorage].
  Future<void> refreshDvrStorage() => _dvr.refreshDvrStorage();

  Future<void> clearAndRefresh({
    CacheClearScope scope = CacheClearScope.all,
  }) async {
    switch (scope) {
      case CacheClearScope.images:
        await _bestEffort(emptyMediaImageCacheIfAvailable);
        return;
      case CacheClearScope.epg:
        _epg.refreshGuide();
        return;
      case CacheClearScope.all:
      case CacheClearScope.content:
        break;
    }
    final sourceGeneration = _sourceOperationGeneration.advance();
    if (scope == CacheClearScope.all) _epg.resetSession(clearGuide: false);
    _isLoadingContent = true;
    _error = null;
    notifyListeners();
    aiostreamsApiService.clearCache();
    if (scope == CacheClearScope.all) {
      unawaited(_bestEffort(emptyMediaImageCacheIfAvailable));
    }
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

  /// See [RequestsCoordinator.searchContentRequests].
  Future<List<ContentRequestSearchResult>> searchContentRequests(
    String query, {
    String? type,
  }) => _requests.searchContentRequests(query, type: type);

  /// See [RequestsCoordinator.submitContentRequest].
  Future<MediaRequestSummary> submitContentRequest({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
    MediaRequestOwner? requestOwner,
  }) => _requests.submitContentRequest(
    type: type,
    integrationId: integrationId,
    externalId: externalId,
    seasons: seasons,
    requestOwner: requestOwner,
  );

  /// See [RequestsCoordinator.dismissMediaRequest].
  Future<void> dismissMediaRequest(int requestId) =>
      _requests.dismissMediaRequest(requestId);

  /// See [RequestsCoordinator.refreshMediaRequests].
  Future<void> refreshMediaRequests() => _requests.refreshMediaRequests();

  void updateProgressEntry(Progress updated) {
    bool sameItem(Progress p) {
      if (p.contentType != updated.contentType) return false;
      if (updated.contentType == ContentType.aiostreams) {
        return p.aioItemId == updated.aioItemId;
      }
      return p.streamId == updated.streamId;
    }

    // Whatever's playing is now the most-recently-watched item, so it moves to
    // the front - matching the order a fresh launch gets from the server's
    // recently-watched list. Updating an existing entry in place left it
    // wherever it was (often down in the "See All" overflow) until the next
    // hard reload re-sorted it.
    final alreadyFirst =
        _progressList.isNotEmpty && sameItem(_progressList.first);
    _progressList = [
      updated,
      for (final p in _progressList)
        if (!sameItem(p)) p,
    ];
    notifyListeners();
    // Playback reports every few seconds; positions already reach the resume
    // store (and ResumeService.recent overlays them), so only a change in
    // order needs a snapshot write.
    if (!alreadyFirst) _persistRecentlyWatched();
  }

  /// Drops a Continue Watching entry that no longer resolves to any catalog
  /// item (e.g. its stream_id went stale after a media-server library flush),
  /// so the dead card doesn't keep reappearing after a failed tap.
  void removeProgressEntry(Progress stale) {
    bool sameItem(Progress p) {
      if (p.contentType != stale.contentType) return false;
      if (stale.contentType == ContentType.aiostreams) {
        return p.aioItemId == stale.aioItemId;
      }
      return p.streamId == stale.streamId;
    }

    final next = [
      for (final p in _progressList)
        if (!sameItem(p)) p,
    ];
    if (next.length == _progressList.length) return;
    _progressList = next;
    notifyListeners();
    _runBackgroundPersistence(resumeService.remove(stale));
    _persistRecentlyWatched();
  }

  /// Stores the in-memory Continue Watching list as the cold-start snapshot,
  /// so a local change (an item played, a dead entry dropped) survives a
  /// relaunch that happens before the next server sync.
  void _persistRecentlyWatched() {
    final viewer = _activeViewer;
    if (viewer == null) return;
    _runBackgroundPersistence(
      resumeService.saveRecent(viewer.ulid, _progressList),
    );
  }

  /// The Continue Watching list last stored for [viewerId], falling back to
  /// every saved resume entry when nothing has been stored yet (first launch
  /// after upgrading).
  Future<List<Progress>> _storedRecentlyWatched(String viewerId) async =>
      await resumeService.recent(viewerId) ?? await resumeService.all(viewerId);

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
            // replace() wipes every cache key not in this map, so keep the
            // stored guide across a same-source refresh (EpgService writes it
            // through as it goes); drop it when the EPG source itself is
            // changing (the reset below clears the in-memory guide).
            'epgGuide': invalidateEpgFreshness
                ? const <EpgProgram>[]
                : CacheService.keepExisting,
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
            _epg.resetSession(
              clearGuide: _sourceType != AppSourceType.none,
            );
          }
          _sourceType = AppSourceType.xtream;
          _liveCategories = liveCategories;
          _vodCategories = vodCategories;
          _seriesCategories = seriesCategories;
          _channels = windowedLiveTv ? const <Channel>[] : channels;
          // DVR recordings/rules and media requests land via
          // [_applyDvrAndRequestExtras] after this commit. On a fresh
          // connection drop the previous account's values now; on a
          // same-account refresh keep them until the refetch resolves so the
          // Home/DVR screens do not flicker to empty.
          if (clearCache) {
            _dvr.reset(clearStorage: false);
            _requests.reset();
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

          // Prime EPG for the first screen's worth of channels, then sweep the
          // rest in the background so scrolling a large playlist lands on
          // already-loaded EPG. [ensureEpgForChannels] still fills any gaps the
          // sweep has not reached yet as rows scroll into view.
          unawaited(_epg.primeAndSweep(lineup: channels));
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
    _dvr.applyFetched(
      results[0] as List<DvrRecording>,
      results[1] as List<DvrSeriesRule>,
    );
    _requests.applyFetched(results[2] as List<MediaRequestSummary>);
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
    // Counts only: the screens page their rows from SQLite, so decoding
    // whole catalogs here just to test for content cost seconds of a cold
    // start on a large library.
    final itemCounts = await Future.wait([
      for (final key in const ['liveStreams', 'vodStreams', 'seriesStreams'])
        cacheService.itemCount(key),
    ]);
    final channels = windowedLiveTv || (itemCounts[0] ?? 0) == 0
        ? const <Channel>[]
        : (await cacheService.get<List<Channel>>('liveStreams'))?.data ??
              const <Channel>[];
    final viewers =
        (await cacheService.get<List<Viewer>>('viewers'))?.data ??
        const <Viewer>[];
    final hasContent =
        liveCategories.isNotEmpty ||
        vodCategories.isNotEmpty ||
        seriesCategories.isNotEmpty ||
        itemCounts.any((count) => (count ?? 0) > 0);
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
        : await _storedRecentlyWatched(activeViewer.ulid);
    if (_sourceOperationGeneration.isStale(sourceGeneration) ||
        _viewerOperationGeneration.isStale(viewerGeneration)) {
      return false;
    }
    await _epg.restoreCachedGuide();
    if (_sourceOperationGeneration.isStale(sourceGeneration) ||
        _viewerOperationGeneration.isStale(viewerGeneration)) {
      return false;
    }
    _sourceType = AppSourceType.xtream;
    _liveCategories = liveCategories;
    _vodCategories = vodCategories;
    _seriesCategories = seriesCategories;
    _channels = channels;
    _dvr.reset();
    _requests.reset();
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
          // Synthetic "up next" rows carry no progress of their own. A stale
          // local resume entry for the same episode must never shadow them,
          // so pass them straight through unmerged (and see the persist loop
          // below - they are never written to the resume store).
          if (r.upNext) return r;
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
              // Defensive: r.upNext is already false here (handled above), but
              // keep the flag flowing so a future refactor can't silently drop
              // it in the merge.
              upNext: r.upNext,
            );
          }
          return r;
        }(),
    ];

    // Remote is authoritative for all content types. Items absent from the
    // server response were either cleared or are beyond the top-20 window -
    // either way, don't show them. Persist the list as the next cold start's
    // snapshot and prune local entries it no longer contains (e.g. copies
    // left under an old stream_id after a media-server library flush), so a
    // relaunch never paints those stale cards again. saveRecent never stores
    // synthetic "up next" rows as resume entries - a later load would read
    // them back as plain 0-position episodes and drop the flag.
    if (persist &&
        !await resumeService.saveRecent(
          viewerId,
          result,
          prune: true,
          shouldCommit: ownsWork,
        )) {
      return const <Progress>[];
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

  /// Queues [channels] for a lazy, debounced EPG fetch - only channels
  /// without fresh cached data are requested. Call this from a screen's
  /// `itemBuilder` (list/grid) so only currently visible channels get fetched
  /// as the user scrolls. See [EpgCoordinator.ensureEpgForChannels].
  void ensureEpgForChannels(
    List<Channel> channels, {
    DateTime? startDate,
    DateTime? endDate,
  }) => _epg.ensureEpgForChannels(
    channels,
    startDate: startDate,
    endDate: endDate,
  );

  /// Fetches the full catchup retention window of EPG programs for
  /// [channel]. See [EpgCoordinator.ensureCatchupEpgForChannel].
  Future<void> ensureCatchupEpgForChannel(Channel channel) =>
      _epg.ensureCatchupEpgForChannel(channel);

  /// Re-primes the guide on resume when it has outlived
  /// [EpgService.cacheTtl]. See [EpgCoordinator.refreshEpgGuideIfStale].
  void refreshEpgGuideIfStale({bool retryOnFailure = true}) =>
      _epg.refreshEpgGuideIfStale(retryOnFailure: retryOnFailure);

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
    authNotifier.removeListener(_registerLogSecrets);
    _epg.dispose();
    _dvr.dispose();
    _pushTokenSubscription?.cancel().ignore();
    unawaited(_tvNotificationController.close());
    unawaited(_notificationActivationController.close());
    unawaited(_pushNotificationService.dispose());
    unawaited(_catalogRepository.close());
    super.dispose();
  }
}
