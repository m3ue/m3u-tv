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
      resumeService: resumeService ?? ResumeService(store: store),
      viewerService: viewerService ?? ViewerService(store: store),
      epgService: epgService ?? EpgService(),
      m3uParser: m3uParser ?? M3UParser(),
    );
  }

  AppStateController._({
    required this.authNotifier,
    required this.xtreamService,
    required this.secureStorage,
    required this.cacheService,
    required this.favoritesService,
    required this.resumeService,
    required this.viewerService,
    required this.epgService,
    required this.m3uParser,
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
  final ResumeService resumeService;
  final ViewerService viewerService;
  final EpgService epgService;
  final M3UParser m3uParser;

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
          unawaited(
            _replaceWithXtreamContent(
              clearCache: false,
            ).then((_) => notifyListeners()),
          );
          return;
        }
        await _replaceWithXtreamContent(clearCache: false);
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

      _sourceType = AppSourceType.xtream;
      _liveCategories = liveCategories;
      _vodCategories = vodCategories;
      _seriesCategories = seriesCategories;
      _channels = channels;
      _vodItems = vodItems;
      _seriesList = seriesList;
      _error = null;
      notifyListeners();

      await _loadXtreamEpg(channels);
      final activeViewer = await viewerService.resolveActiveViewer(viewers);
      final progress = activeViewer == null
          ? const <Progress>[]
          : await _loadRecentlyWatched(activeViewer.ulid);

      if (clearCache) await cacheService.clear();
      await cacheService.set('sourceType', 'xtream');
      await cacheService.set('liveCategories', liveCategories);
      await cacheService.set('vodCategories', vodCategories);
      await cacheService.set('seriesCategories', seriesCategories);
      await cacheService.set('liveStreams', channels);
      await cacheService.set('vodStreams', vodItems);
      await cacheService.set('seriesStreams', seriesList);
      await secureStorage.write(
        _sourceKey,
        jsonEncode(<String, Object?>{'type': 'xtream'}),
      );

      _viewers = viewers;
      _activeViewer = activeViewer;
      _progressList = progress;
      _error = null;
      notifyListeners();
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
    _error = null;
    return true;
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
            // Merge: keep enriched metadata but adopt the server's position.
            if (r.positionSeconds != l.positionSeconds ||
                r.completed != l.completed) {
              return Progress(
                viewerId: l.viewerId,
                contentType: l.contentType,
                streamId: l.streamId,
                positionSeconds: r.positionSeconds,
                durationSeconds: r.durationSeconds ?? l.durationSeconds,
                completed: r.completed,
                seriesId: l.seriesId ?? r.seriesId,
                seasonNumber: l.seasonNumber ?? r.seasonNumber,
                title: l.title,
                episodeTitle: l.episodeTitle,
                seriesName: l.seriesName,
                thumbnailUrl: l.thumbnailUrl,
                backdropUrl: l.backdropUrl,
                rating: l.rating,
                runtime: l.runtime,
              );
            }
            return l;
          }
          return r;
        }(),
      // Include local-only entries (e.g. M3U source, or server not yet synced).
      for (final l in local)
        if (!remote.any(
          (r) => r.contentType == l.contentType && r.streamId == l.streamId,
        ))
          l,
    ];

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
