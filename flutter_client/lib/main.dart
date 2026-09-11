import 'dart:async';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType, shouldUseSidebar;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/device_performance.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/production_storage.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/window_state_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DevicePerformance.ensureDetected();
  if (kDebugMode) debugPrint(DevicePerformance.describe());
  _configureImageCache();
  tz_data.initializeTimeZones();
  final systemUiPolicy = SystemUiPolicy();
  await systemUiPolicy.applyBrowsing();
  final appState = await _buildAppState();
  // In speed mode, cap the decoded image cache at 50 MB to prevent memory
  // accumulation during long browsing sessions on low-RAM devices.
  final optimizeFor = await appState.viewSettingsService.optimizeFor();
  if (optimizeFor == OptimizeFor.speed) {
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        50 * 1024 * 1024; // 50 MB
    PaintingBinding.instance.imageCache.maximumSize = 200;
  }
  if (_isDesktop) {
    await _configureDesktopWindow(appState);
  }
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  if (_isMobilePushCapable(nativeTelevisionHint)) {
    unawaited(_initPushNotifications(appState));
  }
  // Pre-load persisted view settings into the in-memory cache so the
  // synchronous getters (fontSizeSync, optimizeForSync) return the correct
  // values on the very first build - without this, fontSizeSync defaults to
  // AppFontSize.normal and the user's saved choice is ignored until the
  // settings screen opens and triggers an async refresh.
  await appState.viewSettingsService.fontSize();
  // Resolve the user's preferred start page before the router is built so a
  // cold launch opens there instead of always on Home.
  final startPage = await appState.viewSettingsService.defaultStartPage();
  runApp(
    ProviderScope(
      overrides: [overrideAppState(appState)],
      child: MyApp(
        nativeTelevisionHint: nativeTelevisionHint,
        appState: appState,
        systemUiPolicy: systemUiPolicy,
        initialLocation: startPage.route,
      ),
    ),
  );
}

/// Raises Flutter's decoded-image memory cache above the 100 MB / 1000 entry
/// default. Posters and channel logos are disk-cached via
/// [MediaImageCacheManager], but the decoded bitmaps live in this in-memory
/// [ImageCache]; on a 4K TV a single poster grid can't fit one screenful in
/// 100 MB, so browsing (and every trip in and out of a detail screen) evicts
/// entries and forces a visible re-decode from disk. A larger ceiling keeps
/// recently browsed art resident so revisiting a screen is instant.
///
/// Sized per platform: Android TV boxes and sticks can sit on ~1 GB of RAM
/// with an aggressive low-memory killer, so they get the smallest ceiling;
/// tvOS has more headroom but still hard-caps per-app memory; desktop is
/// effectively unconstrained.
void _configureImageCache() {
  int maximumSizeBytes;
  int maximumSize;
  if (_isDesktop) {
    maximumSizeBytes = 384 * 1024 * 1024;
    maximumSize = 1500;
  } else if (Platform.isIOS) {
    // tvOS
    maximumSizeBytes = 256 * 1024 * 1024;
    maximumSize = 1200;
  } else {
    // Android TV - tightest RAM budget
    maximumSizeBytes = 160 * 1024 * 1024;
    maximumSize = 900;
  }
  // Low-end Android hardware (32-bit, low-RAM flag, <= ~2.2 GiB): halve the
  // ceiling so a poster-grid decode burst can't push RSS into LMK range
  // before the watchdog samples. The watchdog is the backstop, this is the
  // budget.
  if (DevicePerformance.isReduced) {
    maximumSizeBytes = (maximumSizeBytes * 0.5).round();
    maximumSize = (maximumSize * 0.6).round();
  }
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = maximumSizeBytes
    ..maximumSize = maximumSize;
}

bool get _isDesktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// Initializes the desktop window: restores the size/position the user left it
/// at last run, then keeps it in sync via a [WindowStateService] listener.
///
/// On macOS this also hides the native titlebar and lets app content extend
/// under the traffic lights (the "hidden inline titlebar" look). AppShell
/// paints the app's background color (0xFF09090b) into a DragToMoveArea + top
/// inset for macOS desktop so the window stays draggable, the titlebar reads
/// as a solid bar, and the sidebar logo doesn't sit under the traffic lights.
Future<void> _configureDesktopWindow(AppStateController appState) async {
  await windowManager.ensureInitialized();
  final windowOptions = Platform.isMacOS
      ? const WindowOptions(
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: true,
        )
      : const WindowOptions();
  final windowState = WindowStateService(appState.viewSettingsService);
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (Platform.isMacOS) {
      await windowManager.setTitle('');
    }
    await windowState.restore();
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(windowState);
}

/// Push is mobile-only: TV builds (Android TV, tvOS) rely on the existing
/// Reverb pipeline instead. tvOS reports `Platform.operatingSystem == 'tvos'`
/// (not 'ios'), so `Platform.isIOS` alone already excludes it.
bool _isMobilePushCapable(bool nativeTelevisionHint) =>
    (Platform.isAndroid && !nativeTelevisionHint) || Platform.isIOS;

Future<void> _initPushNotifications(AppStateController appState) async {
  try {
    await appState.initPushNotifications();
  } on Object catch (_) {
    // Best-effort: e.g. Firebase config not yet installed on this build.
    debugPrint('Push notification init failed');
  }
}

Future<AppStateController> _buildAppState() async {
  final operatingSystem = Platform.operatingSystem;
  final (store, cacheStore, dataDir) = await _createAppStateStores(
    operatingSystem,
  );
  final storage = createProductionStorage(
    operatingSystem: operatingSystem,
    persistentStore: store,
  );
  if (shouldMigrateLegacyCredentials(operatingSystem)) {
    await migrateLegacyCredentials(
      appStateStore: storage.appStateStore,
      credentialStorage: storage.credentialStorage,
    );
  }
  final catalogRepository = await _openCatalogRepository(dataDir);
  // The catalog is a disposable cache - it's re-fetched from the source on
  // every load - so there is nothing to migrate. Drop only the pre-SQLite
  // catalog blobs (`m3ue_cache_liveStreams`, ...) from the JSON stores;
  // SQLite fills itself on the next source load. The other `m3ue_cache_*`
  // keys (`sourceType`, `viewers`) still live in the JSON store and must be
  // left alone or the cached-content fast path in boot() never fires. Best
  // effort: a failure here only leaves dead bytes behind.
  final legacyCatalogKeys = <String>{
    for (final key in CacheService.catalogKeys) 'm3ue_cache_$key',
  };
  for (final legacyStore in {storage.appStateStore, cacheStore}) {
    try {
      await legacyStore.removeWhere(legacyCatalogKeys.contains);
    } on Object catch (error) {
      debugPrint('[Catalog] legacy cache purge deferred: $error');
    }
  }
  return AppStateController(
    persistentStore: storage.appStateStore,
    cacheStore: cacheStore,
    catalogRepository: catalogRepository,
    secureStorage: storage.credentialStorage,
  );
}

/// Opens the SQLite catalog database in [dataDir] and probes it with a trivial
/// query. There is no JSON fallback - the catalog is always a `CatalogRepository`.
///
/// The catalog is a disposable cache (it refills from the source on every
/// load), so a file that won't open or answer - corruption, a schema mismatch -
/// is recoverable: delete the file and reopen once. If even a fresh file can't
/// be opened (the platform has no usable sqlite3), fall back to an in-memory
/// database: still the same code path, just not persisted, so the app runs and
/// rebuilds the catalog each launch instead of failing to start.
Future<CatalogRepository> _openCatalogRepository(Directory dataDir) async {
  await dataDir.create(recursive: true);
  try {
    return await _openAndProbeCatalog(dataDir);
  } on Object catch (error, stackTrace) {
    debugPrint('[Catalog] discarding unusable catalog database: $error');
    if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
    for (final name in CatalogDatabase.databaseFileNames) {
      final file = File('${dataDir.path}/$name');
      try {
        if (file.existsSync()) await file.delete();
      } on Object {
        // Best effort - a leftover sidecar is harmless once the main file is gone.
      }
    }
    try {
      return await _openAndProbeCatalog(dataDir);
    } on Object catch (error, stackTrace) {
      debugPrint(
        '[Catalog] on-disk catalog unavailable, using in-memory: $error',
      );
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      return CatalogRepository(CatalogDatabase.memory());
    }
  }
}

Future<CatalogRepository> _openAndProbeCatalog(Directory dataDir) async {
  final repository = CatalogRepository(CatalogDatabase.open(dataDir));
  try {
    await repository.isEmpty().timeout(const Duration(seconds: 5));
    return repository;
  } on Object {
    await repository.close().catchError((_) {});
    rethrow;
  }
}

/// Returns the app-state store, the content-cache store, and the directory
/// both live in. The cache (whole channel/VOD/series catalog) is a sibling
/// `cache.json` so a small single-key write to `app_state.json` - e.g. the
/// resume tracker every ~10s during playback - never has to re-serialize the
/// catalog.
Future<(PersistentJsonStore, PersistentJsonStore, Directory)>
_createAppStateStores(String operatingSystem) async {
  if (operatingSystem == 'tvos') {
    // Documents exists but is read-only on a physical Apple TV; only
    // Library/Caches and tmp are writable there. See path_provider_tvos's
    // PathProviderPlugin.swift for the on-device sandbox measurements.
    final dir = await getApplicationCacheDirectory();
    // MediaImageCacheManager's flutter_cache_manager Config has no explicit
    // `repo`, so on tvOS (not Android/iOS/macOS by flutter_cache_manager's
    // own platform check) it defaults to JsonCacheInfoRepository, which
    // lazily resolves its storage directory via getApplicationSupportDirectory
    // - a directory that cannot be created on a physical Apple TV. That threw
    // on every image cache write, so posters/logos silently failed to load on
    // device while working fine in the simulator. Resolving Caches here,
    // before any image widget builds, lets the manager use a writable
    // directory instead.
    MediaImageCacheManager.tvosCacheDirectory = dir;
    return (
      PersistentJsonStore(file: File('${dir.path}/app_state.json')),
      PersistentJsonStore(file: File('${dir.path}/cache.json')),
      dir,
    );
  }
  if (operatingSystem == 'android' || operatingSystem == 'ios') {
    final dir = await getApplicationDocumentsDirectory();
    return (
      PersistentJsonStore(file: File('${dir.path}/app_state.json')),
      PersistentJsonStore(file: File('${dir.path}/cache.json')),
      dir,
    );
  }
  return (
    PersistentJsonStore(),
    PersistentJsonStore(fileName: 'cache.json'),
    Directory(PersistentJsonStore.defaultDirectoryPath()),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.nativeTelevisionHint = false,
    this.appState,
    this.systemUiPolicy,
    this.initialLocation = RouteNames.home,
  });

  final bool nativeTelevisionHint;
  final AppStateController? appState;
  final SystemUiPolicy? systemUiPolicy;
  final String initialLocation;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = createGoRouter(
    appState: widget.appState ?? AppStateController(),
    nativeTelevisionHint: widget.nativeTelevisionHint,
    systemUiPolicy: widget.systemUiPolicy,
    initialLocation: widget.initialLocation,
  );
  OptimizeFor? _lastOptimizeFor;

  @override
  void initState() {
    super.initState();
    widget.appState?.addListener(_onAppStateChanged);
    widget.appState?.viewSettingsService.addListener(_onAppStateChanged);
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState?.removeListener(_onAppStateChanged);
      oldWidget.appState?.viewSettingsService.removeListener(
        _onAppStateChanged,
      );
      widget.appState?.addListener(_onAppStateChanged);
      widget.appState?.viewSettingsService.addListener(_onAppStateChanged);
    }
  }

  @override
  void dispose() {
    widget.appState?.viewSettingsService.removeListener(_onAppStateChanged);
    widget.appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    // Update the image cache cap only when the optimize-for setting actually
    // changes -- this listener also fires on unrelated AppStateController
    // notifications (e.g. the 30s DVR poll), and clearing the cache on every
    // one of those would force live logos/posters to re-decode constantly.
    final optimizeFor = widget.appState?.viewSettingsService.optimizeForSync;
    if (optimizeFor != _lastOptimizeFor) {
      _lastOptimizeFor = optimizeFor;
      if (optimizeFor == OptimizeFor.speed) {
        PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
        PaintingBinding.instance.imageCache.maximumSize = 200;
      } else {
        PaintingBinding.instance.imageCache.maximumSizeBytes =
            100 * 1024 * 1024;
        PaintingBinding.instance.imageCache.maximumSize = 1000;
      }
      // Clear cached images so they re-decode at the new oversample/filter
      // quality - stale entries from the previous mode waste GPU memory.
      PaintingBinding.instance.imageCache.clear();
    }
    // boot() calls notifyListeners() synchronously from AppShellState.initState,
    // which fires mid-build. Deferring to post-frame avoids the setState-during-
    // build assertion in all phases (idle mount, persistent-callbacks frame, etc.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4f39f6);
    const secondary = Color(0xFFec003f);
    const background = Color(0xFF09090b);
    const card = Color(0xFF18181b);
    const elevated = Color(0xFF18181b);

    return MaterialApp.router(
      title: 'M3U TV',
      routerConfig: _router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: widget.appState?.locale,
      builder: (context, child) {
        final deviceType = resolveDeviceType(
          context,
          nativeTelevisionHint: widget.nativeTelevisionHint,
        );
        final isTvOrDesktop = shouldUseSidebar(deviceType);
        final viewSettings = widget.appState?.viewSettingsService;
        final optimizeFor =
            viewSettings?.optimizeForSync ?? OptimizeFor.quality;
        // TV defaults to Large: it drives the app's whole visual scale now
        // (text, icons, posters), and content read from couch distance needs
        // to start bigger than the desktop/mobile default. Only applies when
        // the user has never explicitly chosen a size.
        final fontSize =
            viewSettings?.fontSizeSyncOrNull ??
            (deviceType == DeviceType.tv
                ? AppFontSize.large
                : AppFontSize.normal);
        final routerChild = child ?? const SizedBox.shrink();
        return Dpad(
          theme: const DpadThemeData(
            effects: [
              GradientBorderEffect(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
            // The package default (220ms animateTo) drives a Ticker that
            // calls ScrollPosition.forcePixels() every animation frame.
            // DpadFocusable's autoScroll, the directional-traversal
            // fallback, and Dpad.ensureVisible() all funnel through this
            // same animated path, including when Dpad's restoreFocus
            // (see below) re-focuses a nearby widget after a fast-scrolled
            // item's FocusNode is disposed by a lazy list — landing that
            // reentrant animateTo() squarely inside the list's own
            // semantics pass and throwing
            // '!attached || !owner!._debugDoingSemantics' on every tick
            // until the animation finishes (see feedback_scroll_sync_
            // jumpto memory). Duration.zero makes every one of those calls
            // a single non-repeating jumpTo() instead, so there's no
            // ticker left to keep re-triggering the assertion.
            scrollDuration: Duration.zero,
          ),
          // restoreFocus keeps focus alive on TV/desktop (needed for D-pad).
          // On phone/tablet it actively harms scroll: when focus drifts to a
          // FocusScopeNode during a fling, _scheduleRestore fires, calls
          // requestFocus(lastFocused), and DpadScroll.ensureVisible kills the
          // fling mid-scroll with an animateTo() counter-animation.
          restoreFocus: isTvOrDesktop,
          // Click sound is D-pad navigation feedback, not wanted on touch.
          onFocusChange: isTvOrDesktop
              ? (node) {
                  if (node != null) {
                    unawaited(SystemSound.play(SystemSoundType.click));
                  }
                }
              : null,
          child: ImageQualityScope(
            optimizeFor: optimizeFor,
            child: FontSizeScope(
              fontSize: fontSize,
              child: Builder(
                builder: (context) {
                  final scale = FontSizeScope.scaleOf(context);
                  if (scale == 1) return routerChild;
                  return MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: routerChild,
                  );
                },
              ),
            ),
          ),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: primary,
              brightness: Brightness.dark,
            ).copyWith(
              primary: primary,
              error: const Color(0xFFff0033),
              onError: Colors.white,
              onPrimary: Colors.white,
              secondary: secondary,
              surface: background,
              surfaceContainerLowest: background,
              surfaceContainerLow: card,
              surfaceContainer: card,
              surfaceContainerHigh: card,
              surfaceContainerHighest: elevated,
            ),
        tabBarTheme: TabBarThemeData(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.10);
            }
            return null;
          }),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: primary,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      themeMode: ThemeMode.dark,
    );
  }
}
