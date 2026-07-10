import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

// ---------------------------------------------------------------------------
// Proxy: wraps AppStateController and forwards ChangeNotifier notifications.
//
// Riverpod owns the proxy's lifecycle — it disposes the proxy when the
// ProviderScope tears down. The proxy's dispose() removes the forwarding
// listener but deliberately does NOT call appState.dispose(), so the caller
// retains full lifecycle ownership of the underlying AppStateController.
// ---------------------------------------------------------------------------

class _AppStateProxy extends ChangeNotifier {
  _AppStateProxy(this.appState) {
    appState.addListener(notifyListeners);
  }

  final AppStateController appState;

  @override
  void dispose() {
    appState.removeListener(notifyListeners);
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Injection point. Override via [overrideAppState] inside ProviderScope to
// inject an AppStateController without transferring disposal ownership to
// Riverpod.
// ---------------------------------------------------------------------------

final appStateControllerProvider = ChangeNotifierProvider<_AppStateProxy>((_) {
  throw UnimplementedError(
    'appStateControllerProvider must be overridden via ProviderScope. '
    'Call overrideAppState(yourController) in the overrides list.',
  );
});

/// Creates a [ProviderOverride] that injects [appState] into the Riverpod
/// provider tree without transferring disposal ownership to Riverpod.
///
/// ```dart
/// ProviderScope(
///   overrides: [overrideAppState(myController)],
///   child: ...,
/// )
/// ```
Override overrideAppState(AppStateController appState) =>
    appStateControllerProvider.overrideWith(
      (ref) => _AppStateProxy(appState),
    );

// ---------------------------------------------------------------------------
// Service providers — stable references that never change after construction.
// Use ref.read (not ref.watch) since services don't need rebuild tracking.
// ---------------------------------------------------------------------------

final cacheServiceProvider = Provider<CacheService>((ref) {
  return ref.read(appStateControllerProvider).appState.cacheService;
});

final xtreamServiceProvider = Provider<XtreamService>((ref) {
  return ref.read(appStateControllerProvider).appState.xtreamService;
});

// ---------------------------------------------------------------------------
// Reactive data providers. These use ref.watch(appStateControllerProvider)
// so they subscribe to the proxy's notifications and rebuild whenever
// AppStateController.notifyListeners() fires.
// ---------------------------------------------------------------------------

final liveChannelsProvider = Provider<List<Channel>>((ref) {
  return ref.watch(appStateControllerProvider).appState.channels;
});

final liveCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(appStateControllerProvider).appState.liveCategories;
});

final vodItemsProvider = Provider<List<VodItem>>((ref) {
  return ref.watch(appStateControllerProvider).appState.vodItems;
});

final vodCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(appStateControllerProvider).appState.vodCategories;
});

final seriesListProvider = Provider<List<Series>>((ref) {
  return ref.watch(appStateControllerProvider).appState.seriesList;
});

final seriesCategoriesProvider = Provider<List<Category>>((ref) {
  return ref.watch(appStateControllerProvider).appState.seriesCategories;
});

final isLoadingContentProvider = Provider<bool>((ref) {
  return ref.watch(appStateControllerProvider).appState.isLoadingContent;
});

final isConfiguredProvider = Provider<bool>((ref) {
  return ref.watch(appStateControllerProvider).appState.isConfigured;
});

// ---------------------------------------------------------------------------
// LiveChannelsNotifier: hardened async version that owns the full
// fetch → cache → serve cycle for live channels.
//
// Implements stale-while-revalidate:
//   Fresh cache  → return immediately, no network call.
//   Stale cache  → fetch, cache, return fresh data.
//   No cache     → fetch, cache, return.
//   Not configured → return cached data or empty list.
// ---------------------------------------------------------------------------

final liveChannelsNotifierProvider =
    AsyncNotifierProvider<LiveChannelsNotifier, List<Channel>>(
      LiveChannelsNotifier.new,
    );

class LiveChannelsNotifier extends AsyncNotifier<List<Channel>> {
  @override
  Future<List<Channel>> build() async {
    // Keep alive across route changes — channels are global app state.
    ref.keepAlive();

    final cache = ref.read(cacheServiceProvider);
    final xtream = ref.read(xtreamServiceProvider);

    if (!xtream.isConfigured) {
      final entry = await cache.get<List<Channel>>('liveStreams');
      return entry?.data ?? const <Channel>[];
    }

    final entry = await cache.get<List<Channel>>('liveStreams');
    if (entry != null && !entry.isStale) return entry.data;

    final channels = await xtream.getLiveStreams();
    await cache.set('liveStreams', channels);
    return channels;
  }

  /// Forces a fresh fetch. Pass [clearCache] to also wipe persisted entries.
  Future<void> refresh({bool clearCache = false}) async {
    if (clearCache) {
      await ref.read(cacheServiceProvider).clear();
    }
    ref.invalidateSelf();
    await future;
  }
}
