import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart' show Locale;

import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

enum AppSourceType { none, xtream, m3u }

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
    M3UParser? m3uParser,
    PersistentJsonStore? persistentStore,
    TvNotificationService? tvNotificationService,
    TvNotificationStore? tvNotificationStore,
    ReverbService? reverbService,
    AIOStreamsFavoritesService? aioFavoritesService,
    ProxyPlaybackSettings? proxyPlaybackSettings,
    PushNotificationService? pushNotificationService,
  }) {
    final store = persistentStore ?? PersistentJsonStore();
    final resolvedSecureStorage =
        secureStorage ?? FileSecureStorage(store: store);
    final resolvedCacheService = cacheService ?? CacheService(store: store);
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
      m3uParser: m3uParser ?? M3UParser(),
      traktService: TraktService(storage: resolvedSecureStorage),
      tvNotificationService: tvNotificationService ?? TvNotificationService(),
      notificationStore:
          tvNotificationStore ?? TvNotificationStore(store: store),
      reverbService: reverbService ?? ReverbService(),
      aioFavoritesService:
          aioFavoritesService ?? AIOStreamsFavoritesService(store: store),
      proxyPlaybackSettings:
          proxyPlaybackSettings ?? ProxyPlaybackSettings(store: store),
      pushNotificationService:
          pushNotificationService ?? PushNotificationService(),
    );
  }

  AppStateController._({
    required this.authNotifier,
    required this.xtreamService,
    required this.secureStorage,
    required this.cacheService,
    required this.favoritesService,
    required this.vodFavoritesService,
    required this.seriesFavoritesService,
    required this.resumeService,
    required this.viewerService,
    required this.epgService,
    required this.m3uParser,
    required this.traktService,
    required this._tvNotificationService,
    required this.notificationStore,
    required this._reverbService,
    required this.aioFavoritesService,
    required this.proxyPlaybackSettings,
    required this._pushNotificationService,
  });

  static const _sourceKey = 'm3ue_tv_source';
  static const _epgIntervalKey = 'm3ue_tv_epg_interval_minutes';
  static const _localeKey = 'm3ue_tv_locale';

  static const List<Duration> epgRefreshOptions = <Duration>[
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(hours: 6),
  ];

  final AuthNotifier authNotifier;
  final XtreamService xtreamService;
  final SecureStorage secureStorage;
  final CacheService cacheService;
  final FavoritesService favoritesService;
  final FavoritesService vodFavoritesService;
  final FavoritesService seriesFavoritesService;
  final ResumeService resumeService;
  final AIOStreamsFavoritesService aioFavoritesService;
  final ProxyPlaybackSettings proxyPlaybackSettings;
  final TvNotificationService _tvNotificationService;
  final TvNotificationStore notificationStore;
  final ReverbService _reverbService;
  final PushNotificationService _pushNotificationService;
  String? _pushToken;
  final StreamController<TvNotificationItem> _tvNotificationController =
      StreamController<TvNotificationItem>.broadcast();
  int _unreadNotificationCount = 0;

  /// Stream of incoming TV push notifications (from Reverb WebSocket or
  /// unread notifications fetched on boot). Listen to this in the UI to
  /// show snackbars or banners.
  Stream<TvNotificationItem> get tvNotifications =>
      _tvNotificationController.stream;

  int get unreadNotificationCount => _unreadNotificationCount;

  Future<void> _refreshUnreadNotificationCount() async {
    final subscribed = await notificationStore.subscribedChannels();
    _unreadNotificationCount = await notificationStore.unreadCount(
      channelFilter: subscribed.isEmpty ? null : subscribed,
    );
    notifyListeners();
  }

  Future<void> markNotificationRead(String id) async {
    await notificationStore.markRead(id);
    await _refreshUnreadNotificationCount();
    final credentials = authNotifier.credentials;
    if (credentials != null) {
      unawaited(
        _tvNotificationService.markRead(credentials, id).catchError((_) {}),
      );
    }
  }

  Future<void> markAllNotificationsRead() async {
    final unread = (await notificationStore.all()).where((n) => !n.isRead);
    final credentials = authNotifier.credentials;
    final ids = unread.map((n) => n.item.id).toList(growable: false);
    await notificationStore.markAllRead();
    await _refreshUnreadNotificationCount();
    if (credentials != null) {
      for (final id in ids) {
        unawaited(
          _tvNotificationService.markRead(credentials, id).catchError((_) {}),
        );
      }
    }
  }

  Future<void> setNotificationChannels(Set<String> channels) async {
    await notificationStore.setSubscribedChannels(channels);
    await _refreshUnreadNotificationCount();
  }

  final ViewerService viewerService;
  final EpgService epgService;
  final M3UParser m3uParser;
  final TraktService traktService;

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
  Set<int> _recordingChannelIds = const <int>{};
  List<MediaRequestSummary> _mediaRequests = const <MediaRequestSummary>[];
  List<Progress> _progressList = const <Progress>[];
  Future<List<Progress>>? _recentlyWatchedRefresh;
  String? _recentlyWatchedRefreshViewerId;
  final Set<int> _pendingEpgChannelIds = <int>{};
  Timer? _epgFetchDebounce;
  static const _epgPrimeCount = 60;
  static const _epgFetchDebounceDelay = Duration(milliseconds: 250);

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
  Set<int> get recordingChannelIds => _recordingChannelIds;
  List<Progress> get progressList => _progressList;
  List<MediaRequestSummary> get mediaRequests => _mediaRequests;
  bool get hasDvrFeature =>
      authNotifier.authResponse?.hasFeature('dvr') ?? false;
  bool get hasRequestsFeature =>
      authNotifier.authResponse?.hasFeature('requests') ?? false;
  RequestsCapability? get requestsCapability =>
      authNotifier.authResponse?.requests;
  bool get hasAioStreams => authNotifier.authResponse?.hasAioStreams ?? false;
  List<AIOStreamsIntegration> get aiostreamsIntegrations =>
      authNotifier.authResponse?.aiostreamsIntegrations ?? const [];
  late final AIOStreamsApiService aiostreamsApiService = AIOStreamsApiService(
    xtreamService: xtreamService,
  );
  String get sourceLabel => switch (_sourceType) {
    AppSourceType.xtream => 'Xtream',
    AppSourceType.m3u => 'M3U',
    AppSourceType.none => 'Not connected',
  };

  String? get serverTimezone =>
      _sourceType == AppSourceType.xtream ? xtreamService.serverTimezone : null;

  Future<void> boot() async {
    _isBootstrapping = true;
    _error = null;
    notifyListeners();
    unawaited(traktService.init());
    unawaited(proxyPlaybackSettings.load());

    final savedLocale = await secureStorage.read(_localeKey);
    if (savedLocale != null) _locale = Locale(savedLocale);

    final savedIntervalRaw = await secureStorage.read(_epgIntervalKey);
    if (savedIntervalRaw != null) {
      final minutes = int.tryParse(savedIntervalRaw);
      if (minutes != null && minutes > 0) {
        cacheService.refreshInterval = Duration(minutes: minutes);
      }
    }

    final savedSource = await _readSavedSourceType();
    if (savedSource == AppSourceType.xtream ||
        savedSource == AppSourceType.none) {
      final restored = await authNotifier.loadSavedCredentials();
      if (restored) {
        final credentials = authNotifier.credentials!;
        if (await _hydrateCachedXtreamContent()) {
          _isBootstrapping = false;
          notifyListeners();
          unawaited(_refreshRecentlyWatchedForActiveViewer());
          unawaited(_replaceWithXtreamContent(clearCache: false));
          unawaited(_connectTvNotifications(credentials));
          unawaited(_registerPushToken(credentials));
          return;
        }
        final loaded = await _replaceWithXtreamContent(clearCache: false);
        if (loaded) {
          unawaited(_connectTvNotifications(credentials));
          unawaited(_registerPushToken(credentials));
        }
      } else if (savedSource == AppSourceType.xtream &&
          authNotifier.error != null) {
        _sourceType = AppSourceType.xtream;
        _error = authNotifier.error;
      }
    } else if (savedSource == AppSourceType.m3u) {
      await _loadSavedM3uSource();
    }

    _isBootstrapping = false;
    notifyListeners();
  }

  Future<bool> connectXtream(UserCredentials credentials) async {
    _isLoadingContent = true;
    _error = null;
    notifyListeners();

    final connected = await authNotifier.connect(credentials);
    if (!connected) {
      _isLoadingContent = false;
      _error = _redact(
        authNotifier.error ?? 'Authentication failed',
        credentials,
      );
      notifyListeners();
      return false;
    }

    final loaded = await _replaceWithXtreamContent(clearCache: true);
    _isLoadingContent = false;
    notifyListeners();
    if (loaded) {
      unawaited(_connectTvNotifications(credentials));
      unawaited(_registerPushToken(credentials));
    }
    return loaded;
  }

  Future<bool> switchToM3u({
    required String playlistText,
    String name = 'Direct M3U',
  }) async {
    _isLoadingContent = true;
    _error = null;
    notifyListeners();

    try {
      final playlist = m3uParser.parse(playlistText);
      await cacheService.clear();
      await cacheService.set('sourceType', 'm3u');
      await cacheService.set('liveCategories', playlist.categories);
      await cacheService.set('liveStreams', playlist.channels);
      await secureStorage.write(
        _sourceKey,
        jsonEncode(<String, Object?>{
          'type': 'm3u',
          'name': name,
          'playlist': playlistText,
        }),
      );
      _sourceType = AppSourceType.m3u;
      _liveCategories = playlist.categories;
      _vodCategories = const <Category>[];
      _seriesCategories = const <Category>[];
      _channels = playlist.channels;
      _vodItems = const <VodItem>[];
      _seriesList = const <Series>[];
      _dvrRecordings = const <DvrRecording>[];
      _recordingChannelIds = const <int>{};
      _mediaRequests = const <MediaRequestSummary>[];
      _activeViewer = const Viewer(
        id: 0,
        ulid: 'local-m3u',
        name: 'Local M3U',
        isAdmin: true,
      );
      _progressList = await resumeService.all(_activeViewer!.ulid);
      _isLoadingContent = false;
      notifyListeners();
      return true;
    } on M3UParseException catch (error) {
      _error = 'M3U parse error: ${error.message}';
      _isLoadingContent = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _connectTvNotifications(UserCredentials credentials) async {
    try {
      final session = await _reconcileUnreadNotifications(credentials);
      // Older server versions don't return Reverb config — skip WebSocket setup
      // rather than hammering a connection that can never succeed.
      if (session == null) return;
      await _reverbService.connect(
        session: session,
        credentials: credentials,
        onNotification: _onPushNotification,
        onDvrStatus: _onDvrStatusPush,
        onRequestStatus: _onRequestStatusPush,
        // Reconciles any status pushes missed while disconnected (app
        // suspended, network drop) — cheap, status-filtered fetch, not a poll.
        onConnected: () => unawaited(refreshActiveDvrRecordings()),
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
    UserCredentials credentials,
  ) async {
    final (session, unread) = await _tvNotificationService.fetchUnread(
      credentials,
    );
    if (session.availableChannels.isNotEmpty) {
      await notificationStore.setServerChannels(session.availableChannels);
    }
    // Sync local store with the server's authoritative unread list: stale
    // local unreads are marked read, new server items are added. Only
    // genuinely new items (not seen before) are surfaced as toasts — this
    // should not replay banners for notifications the user already received.
    final newItems = await notificationStore.syncUnreadWithServer(unread);
    await _refreshUnreadNotificationCount();
    final subscribed = await notificationStore.subscribedChannels();
    for (final item in newItems) {
      if (subscribed.isEmpty || subscribed.contains(item.channel)) {
        _tvNotificationController.add(item);
      }
    }
    if (session.channelName.isEmpty || session.reverb.appKey.isEmpty) {
      return null;
    }
    return session;
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
    try {
      await _reconcileUnreadNotifications(credentials);
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
    await _reverbService.resume();
  }

  /// Called by `main.dart` once Firebase hands back an FCM registration
  /// token (mobile only — TV builds never call this). Registers immediately
  /// if credentials are already connected; otherwise the token is held and
  /// registered the next time [_connectTvNotifications] runs.
  void setPushToken(String token) {
    _pushToken = token;
    final credentials = authNotifier.credentials;
    if (credentials != null) {
      unawaited(_registerPushToken(credentials));
    }
  }

  Future<void> _registerPushToken(UserCredentials credentials) async {
    final token = _pushToken;
    if (token == null) return;
    try {
      await _pushNotificationService.registerToken(
        credentials,
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } on Object catch (_) {
      // Push registration is best-effort, same as TV notifications above.
    }
  }

  void _onPushNotification(TvNotificationItem item) {
    unawaited(_storeAndNotify(item));
  }

  void _onDvrStatusPush(DvrRecording recording) {
    final channelId = recording.channelId;
    if (channelId != null) {
      final updated = Set<int>.of(_recordingChannelIds);
      if (recording.isInProgress) {
        updated.add(channelId);
      } else {
        updated.remove(channelId);
      }
      if (!setEquals(_recordingChannelIds, updated)) {
        _recordingChannelIds = updated;
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
        _dvrRecordings = next;
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
    unawaited(_refreshDvrRecordingDetail(recording.uuid));
  }

  Future<void> _refreshDvrRecordingDetail(String uuid) async {
    try {
      final detail = await xtreamService.getDvrRecording(uuid);
      final next = [..._dvrRecordings];
      final index = next.indexWhere((r) => r.uuid == uuid);
      if (index >= 0) {
        next[index] = detail;
      } else {
        next.insert(0, detail);
      }
      _dvrRecordings = next;
      notifyListeners();
    } on Object catch (error) {
      debugPrint('DVR: refresh recording detail after push failed: $error');
    }
  }

  /// Mirrors [_onDvrStatusPush]: updates the local requests list in place
  /// from the lightweight `request.status` push (approved/rejected/completed
  /// by MediaRequestStatusEvent on the server) instead of re-polling
  /// request_history.
  void _onRequestStatusPush(MediaRequestSummary request) {
    final next = [..._mediaRequests];
    final index = next.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.insert(0, request);
    }
    _mediaRequests = next;
    notifyListeners();
  }

  Future<void> _storeAndNotify(TvNotificationItem item) async {
    await notificationStore.add(item);
    await _refreshUnreadNotificationCount();
    // Only surface the notification in the stream (banners/toasts) if the
    // channel passes the user's subscription filter.
    final subscribed = await notificationStore.subscribedChannels();
    if (subscribed.isEmpty || subscribed.contains(item.channel)) {
      _tvNotificationController.add(item);
    }
  }

  Future<void> disconnect() async {
    await _reverbService.disconnect();
    await authNotifier.disconnect();
    await secureStorage.delete(_sourceKey);
    _sourceType = AppSourceType.none;
    _viewers = const <Viewer>[];
    _activeViewer = null;
    _liveCategories = const <Category>[];
    _vodCategories = const <Category>[];
    _seriesCategories = const <Category>[];
    _channels = const <Channel>[];
    _vodItems = const <VodItem>[];
    _seriesList = const <Series>[];
    _dvrRecordings = const <DvrRecording>[];
    _recordingChannelIds = const <int>{};
    _mediaRequests = const <MediaRequestSummary>[];
    _progressList = const <Progress>[];
    _error = null;
    notifyListeners();
  }

  Duration get epgRefreshInterval => cacheService.refreshInterval;

  Future<void> setEpgRefreshInterval(Duration interval) async {
    cacheService.refreshInterval = interval;
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

  Future<void> clearAndRefresh() async {
    _isLoadingContent = true;
    _error = null;
    notifyListeners();
    aiostreamsApiService.clearCache();
    if (_sourceType == AppSourceType.xtream && !authNotifier.isConfigured) {
      _isLoadingContent = false;
      await boot();
      return;
    }
    await _replaceWithXtreamContent(clearCache: true);
    _isLoadingContent = false;
    notifyListeners();
  }

  Future<void> switchViewer(Viewer viewer) async {
    await viewerService.setActiveViewer(viewer);
    _activeViewer = viewer;
    _progressList = await _loadRecentlyWatched(viewer.ulid);
    notifyListeners();
  }

  Future<Viewer?> createViewer(String name) async {
    try {
      final viewer = await xtreamService.createViewer(name);
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
  Future<DvrRecording?> scheduleDvr(Channel channel, EpgProgram program) async {
    await xtreamService.scheduleDvr(
      channelId: channel.id,
      title: program.title,
      startTime: program.start,
      endTime: program.end,
    );
    try {
      _dvrRecordings = await xtreamService.getDvrRecordings();
      _recordingChannelIds = _extractRecordingChannelIds(_dvrRecordings);
    } on Object catch (error, stackTrace) {
      debugPrint('DVR: refresh after schedule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    notifyListeners();
    for (final recording in _dvrRecordings) {
      if (recording.channelId != channel.id) continue;
      final start = recording.scheduledStart;
      if (start == null) continue;
      if (program.start.difference(start).abs() <= const Duration(minutes: 1)) {
        return recording;
      }
    }
    return null;
  }

  static Set<int> _extractRecordingChannelIds(List<DvrRecording> recordings) {
    return recordings
        .where((recording) => recording.isInProgress)
        .map((recording) => recording.channelId)
        .whereType<int>()
        .toSet();
  }

  /// Lightweight poll for which channels are currently recording, used to
  /// mark Live TV tiles without waiting for a full app refresh. Callers
  /// (e.g. LiveTvScreen) are expected to invoke this on a short timer only
  /// while the screen is visible — `status=recording` keeps the request
  /// small regardless of total recording history.
  Future<void> refreshActiveDvrRecordings() async {
    if (!hasDvrFeature) return;
    try {
      final active = await xtreamService.getDvrRecordings(
        status: DvrRecordingStatus.recording,
        limit: 200,
      );
      final ids = _extractRecordingChannelIds(active);
      if (setEquals(_recordingChannelIds, ids)) return;
      _recordingChannelIds = ids;
      notifyListeners();
    } on Object catch (error) {
      debugPrint('DVR: refresh active recordings failed: $error');
    }
  }

  /// Searches guest-enabled Arr integrations via `request_search`. Thin
  /// pass-through — the Requests screen owns its own search-in-flight/error
  /// state since results aren't part of the app's persistent state.
  Future<List<ContentRequestSearchResult>> searchContentRequests(
    String query, {
    String? type,
  }) => xtreamService.searchContentRequests(query, type: type);

  /// Submits a content request and adds it to the local requests list so it
  /// shows up immediately, without waiting for a `request.status` push.
  Future<MediaRequestSummary> submitContentRequest({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
  }) async {
    final request = await xtreamService.submitContentRequest(
      type: type,
      integrationId: integrationId,
      externalId: externalId,
      seasons: seasons,
    );
    _mediaRequests = [request, ..._mediaRequests];
    notifyListeners();
    return request;
  }

  /// Dismisses a completed or rejected request and removes it locally.
  Future<void> dismissMediaRequest(int requestId) async {
    await xtreamService.dismissMediaRequest(requestId);
    _mediaRequests = _mediaRequests
        .where((request) => request.id != requestId)
        .toList(growable: false);
    notifyListeners();
  }

  /// Refreshes the requesting guest's request history from the server. Used
  /// when the Requests screen becomes visible, since a push can be missed
  /// while the app is backgrounded and no other screen holds this list warm.
  Future<void> refreshMediaRequests() async {
    if (!hasRequestsFeature) return;
    try {
      _mediaRequests = await xtreamService.getMediaRequests();
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

  Future<bool> _replaceWithXtreamContent({required bool clearCache}) async {
    try {
      final liveCategoriesFuture = xtreamService.getLiveCategories();
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
      final mediaRequestsFuture = hasRequestsFeature
          ? xtreamService.getMediaRequests().catchError(
              (Object _) => const <MediaRequestSummary>[],
            )
          : Future<List<MediaRequestSummary>>.value(
              const <MediaRequestSummary>[],
            );
      final viewersFuture = xtreamService.getViewers();

      final results = await Future.wait<Object>(<Future<Object>>[
        liveCategoriesFuture,
        vodCategoriesFuture,
        seriesCategoriesFuture,
        channelsFuture,
        vodItemsFuture,
        seriesFuture,
        recordingsFuture,
        viewersFuture,
        mediaRequestsFuture,
      ]);

      final viewers = results[7] as List<Viewer>;
      final channels = results[3] as List<Channel>;
      final liveCategories = results[0] as List<Category>;
      final vodCategories = results[1] as List<Category>;
      final seriesCategories = results[2] as List<Category>;
      final vodItems = results[4] as List<VodItem>;
      final seriesList = results[5] as List<Series>;
      final dvrRecordings = results[6] as List<DvrRecording>;
      final mediaRequests = results[8] as List<MediaRequestSummary>;

      final activeViewer = await viewerService.resolveActiveViewer(viewers);
      final fetched = activeViewer == null
          ? const <Progress>[]
          : await _loadRecentlyWatchedDeduped(activeViewer.ulid);
      // Keep local progress if the server returned nothing (e.g. sync lag).
      final progress = fetched.isEmpty && _progressList.isNotEmpty
          ? _progressList
          : fetched;

      _sourceType = AppSourceType.xtream;
      _liveCategories = liveCategories;
      _vodCategories = vodCategories;
      _seriesCategories = seriesCategories;
      _channels = channels;
      _vodItems = vodItems;
      _seriesList = seriesList;
      _dvrRecordings = dvrRecordings;
      _recordingChannelIds = _extractRecordingChannelIds(dvrRecordings);
      _mediaRequests = mediaRequests;
      _viewers = viewers;
      _activeViewer = activeViewer;
      _progressList = progress;
      _error = null;
      notifyListeners();

      // Prime EPG for the first screen's worth of channels only; the rest is
      // fetched lazily as screens request it via [ensureEpgForChannels] (e.g.
      // as the channel list scrolls into view). Fetching all channels' EPG
      // upfront was the main bottleneck on large playlists.
      unawaited(_loadXtreamEpg(channels.take(_epgPrimeCount).toList()));

      if (clearCache) {
        await cacheService.clear();
        aiostreamsApiService.clearCache();
      }
      await cacheService.set('sourceType', 'xtream');
      await cacheService.set('liveCategories', liveCategories);
      await cacheService.set('vodCategories', vodCategories);
      await cacheService.set('seriesCategories', seriesCategories);
      await cacheService.set('liveStreams', channels);
      await cacheService.set('vodStreams', vodItems);
      await cacheService.set('seriesStreams', seriesList);
      await cacheService.set('viewers', viewers);
      await secureStorage.write(
        _sourceKey,
        jsonEncode(<String, Object?>{'type': 'xtream'}),
      );
      return true;
    } on Object catch (error) {
      _error = _redact(userFacingXtreamError(error), xtreamService.credentials);
      return false;
    }
  }

  Future<bool> _hydrateCachedXtreamContent() async {
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

    _sourceType = AppSourceType.xtream;
    _liveCategories = liveCategories;
    _vodCategories = vodCategories;
    _seriesCategories = seriesCategories;
    _channels = channels;
    _vodItems = vodItems;
    _seriesList = seriesList;
    _dvrRecordings = const <DvrRecording>[];
    _recordingChannelIds = const <int>{};
    _mediaRequests = const <MediaRequestSummary>[];
    _viewers = viewers;
    _activeViewer = await viewerService.resolveActiveViewer(viewers);
    final activeViewer = _activeViewer;
    _progressList = activeViewer == null
        ? const <Progress>[]
        : await resumeService.all(activeViewer.ulid);
    _error = null;
    return true;
  }

  Future<void> _refreshRecentlyWatchedForActiveViewer() async {
    final viewer = _activeViewer;
    if (viewer == null) return;
    try {
      final progress = await _loadRecentlyWatchedDeduped(viewer.ulid);
      if (progress.isEmpty && _progressList.isNotEmpty) return;
      _progressList = progress;
      notifyListeners();
    } on Object catch (_) {}
  }

  Future<List<Progress>> _loadRecentlyWatchedDeduped(String viewerId) {
    final inFlight = _recentlyWatchedRefresh;
    if (inFlight != null && _recentlyWatchedRefreshViewerId == viewerId) {
      return inFlight;
    }
    late final Future<List<Progress>> future;
    _recentlyWatchedRefreshViewerId = viewerId;
    future = _loadRecentlyWatched(viewerId).whenComplete(() {
      if (identical(_recentlyWatchedRefresh, future)) {
        _recentlyWatchedRefresh = null;
        _recentlyWatchedRefreshViewerId = null;
      }
    });
    _recentlyWatchedRefresh = future;
    return future;
  }

  Future<List<Progress>> _loadRecentlyWatched(String viewerId) async {
    final remote = await xtreamService.getRecentlyWatched(viewerId);
    final local = await resumeService.all(viewerId);

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
              thumbnailUrl: l.thumbnailUrl ?? r.thumbnailUrl,
              backdropUrl: l.backdropUrl ?? r.backdropUrl,
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
    for (final p in result) {
      await resumeService.save(p);
    }

    return result;
  }

  /// Queues [channels] for a lazy, debounced EPG fetch — only channels
  /// without fresh cached data are requested. Call this from a screen's
  /// `itemBuilder` (list/grid) so only currently visible channels get fetched
  /// as the user scrolls, instead of fetching the whole channel list upfront.
  void ensureEpgForChannels(List<Channel> channels) {
    if (_sourceType != AppSourceType.xtream) return;
    var added = false;
    for (final channel in channels) {
      if (epgService.hasFreshDataForChannel(channel)) continue;
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
    final channels = _channels
        .where((channel) => ids.contains(channel.id))
        .toList(growable: false);
    if (channels.isEmpty) return;
    final channelIds = channels.map(
      (channel) => channel.epgChannelId ?? channel.tvgName ?? channel.name,
    );
    try {
      final programs = await xtreamService.getEpgBatch(channels);
      epgService
        ..mergePrograms(programs)
        ..markFetched(channelIds);
      if (kDebugMode) {
        debugPrint(
          '[EPG] lazy fetch → ${programs.length} programs for ${channels.length} channels',
        );
      }
    } on Object catch (e) {
      // Mark as fetched even on failure so a persistently erroring channel
      // doesn't get re-queued (and reschedule the debounce timer) on every
      // rebuild — it'll be retried once cacheTtl expires.
      epgService.markFetched(channelIds);
      if (kDebugMode) debugPrint('[EPG] lazy fetch failed: $e');
    }
  }

  Future<void> _loadXtreamEpg(List<Channel> channels) async {
    try {
      final programs = await xtreamService.getEpgBatch(channels);
      if (kDebugMode) {
        debugPrint(
          '[EPG] getEpgBatch → ${programs.length} programs for ${channels.length} channels',
        );
      }
      if (programs.isNotEmpty) {
        // EpgService.loadPrograms() calls notifyListeners() on the EpgService
        // itself — widgets watching epgServiceProvider will rebuild without
        // triggering a full AppStateController rebuild.
        epgService.loadPrograms(programs);
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[EPG] getEpgBatch failed: $e');
      // Don't clear existing EPG data on a batch failure. A transient network
      // error shouldn't wipe a previously loaded guide.
    }
  }

  Future<void> _loadSavedM3uSource() async {
    final raw = await secureStorage.read(_sourceKey);
    if (raw == null) return;
    final json = jsonDecode(raw) as Map<String, Object?>;
    final playlist = json['playlist'];
    if (playlist is String) {
      await switchToM3u(
        playlistText: playlist,
        name: '${json['name'] ?? 'Direct M3U'}',
      );
    }
  }

  Future<AppSourceType> _readSavedSourceType() async {
    final raw = await secureStorage.read(_sourceKey);
    if (raw == null) return AppSourceType.none;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return json['type'] == 'm3u' ? AppSourceType.m3u : AppSourceType.xtream;
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

  @override
  void dispose() {
    _epgFetchDebounce?.cancel();
    super.dispose();
  }
}
