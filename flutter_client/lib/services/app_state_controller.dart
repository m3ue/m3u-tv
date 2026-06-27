import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
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
  });

  static const _sourceKey = 'm3ue_tv_source';
  static const _epgIntervalKey = 'm3ue_tv_epg_interval_minutes';

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
  final ViewerService viewerService;
  final EpgService epgService;
  final M3UParser m3uParser;
  final TraktService traktService;

  AppSourceType _sourceType = AppSourceType.none;
  bool _isBootstrapping = false;
  bool _isLoadingContent = false;
  String? _error;
  Viewer? _activeViewer;
  List<Viewer> _viewers = const <Viewer>[];
  List<Category> _liveCategories = const <Category>[];
  List<Category> _vodCategories = const <Category>[];
  List<Category> _seriesCategories = const <Category>[];
  List<Channel> _channels = const <Channel>[];
  List<VodItem> _vodItems = const <VodItem>[];
  List<Series> _seriesList = const <Series>[];
  List<Progress> _progressList = const <Progress>[];
  Future<List<Progress>>? _recentlyWatchedRefresh;
  String? _recentlyWatchedRefreshViewerId;

  AppSourceType get sourceType => _sourceType;
  bool get isBootstrapping => _isBootstrapping;
  bool get isLoadingContent => _isLoadingContent;
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
  List<Progress> get progressList => _progressList;
  String get sourceLabel => switch (_sourceType) {
    AppSourceType.xtream => 'Xtream',
    AppSourceType.m3u => 'M3U',
    AppSourceType.none => 'Not connected',
  };

  Future<void> boot() async {
    _isBootstrapping = true;
    _error = null;
    notifyListeners();
    unawaited(traktService.init());

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
        if (await _hydrateCachedXtreamContent()) {
          _isBootstrapping = false;
          notifyListeners();
          unawaited(_refreshRecentlyWatchedForActiveViewer());
          unawaited(_replaceWithXtreamContent(clearCache: false));
          return;
        }
        await _replaceWithXtreamContent(clearCache: false);
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

  Future<void> disconnect() async {
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

  Future<void> clearAndRefresh() async {
    _isLoadingContent = true;
    _error = null;
    notifyListeners();
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

  void updateProgressEntry(Progress updated) {
    final idx = _progressList.indexWhere(
      (p) =>
          p.contentType == updated.contentType &&
          p.streamId == updated.streamId,
    );
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
      final viewersFuture = xtreamService.getViewers();

      final results = await Future.wait<Object>(<Future<Object>>[
        liveCategoriesFuture,
        vodCategoriesFuture,
        seriesCategoriesFuture,
        channelsFuture,
        vodItemsFuture,
        seriesFuture,
        viewersFuture,
      ]);

      final viewers = results[6] as List<Viewer>;
      final channels = results[3] as List<Channel>;
      final liveCategories = results[0] as List<Category>;
      final vodCategories = results[1] as List<Category>;
      final seriesCategories = results[2] as List<Category>;
      final vodItems = results[4] as List<VodItem>;
      final seriesList = results[5] as List<Series>;

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
      _viewers = viewers;
      _activeViewer = activeViewer;
      _progressList = progress;
      _error = null;
      notifyListeners();

      await _loadXtreamEpg(channels);

      if (clearCache) await cacheService.clear();
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

    // Build a lookup of locally-stored entries keyed by (contentType, streamId).
    // Local entries carry enriched metadata (title, thumbnail, etc.) that was
    // saved during playback via progressReporter. Remote entries carry the
    // authoritative server position but no enrichment.
    final localMap = {
      for (final p in local) (p.contentType, p.streamId): p,
    };

    // For each remote entry, prefer the local copy when it has enriched
    // metadata; otherwise use remote (which has the latest position).
    // Any remote position advance is merged in by saving below.
    final result = <Progress>[
      for (final r in remote)
        () {
          final l = localMap[(r.contentType, r.streamId)];
          // Local wins if it has enrichment; remote wins otherwise so the
          // latest server position is reflected.
          if (l != null && l.title != null && l.title!.isNotEmpty) {
            // Always merge: keep enriched local metadata but adopt server
            // position and fill in any fields the local entry may be missing
            // (e.g. fields added to the API after the local entry was cached).
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
              episodeTitle: l.episodeTitle,
              seriesName: l.seriesName,
              thumbnailUrl: l.thumbnailUrl,
              backdropUrl: l.backdropUrl,
              rating: l.rating ?? r.rating,
              runtime: l.runtime ?? r.runtime,
              plot: l.plot ?? r.plot,
              genre: l.genre ?? r.genre,
              year: l.year ?? r.year,
            );
          }
          return r;
        }(),
    ];
    // Remote is authoritative for which entries exist. Local-only entries
    // (cleared on the server) are excluded so ghost cards don't reappear.

    // Persist the merged list so future local reads are up to date.
    for (final p in result) {
      await resumeService.save(p);
    }

    return result;
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
        epgService.loadPrograms(programs);
        notifyListeners();
      }
    } on Object catch (e) {
      if (kDebugMode) debugPrint('[EPG] getEpgBatch failed: $e');
      // Don't clear existing EPG data on a batch failure — a transient network
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
}
