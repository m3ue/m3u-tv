import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';

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

/// Creates an [Override] that injects [appState] into the Riverpod
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

// EpgService is its own ChangeNotifier — this provider subscribes directly to
// EpgService.notifyListeners(), which fires only when EPG data loads.
// Widgets watching this will NOT rebuild on unrelated AppStateController
// notifications (channel refreshes, progress updates, etc.).
final epgServiceProvider = ChangeNotifierProvider<EpgService>((ref) {
  return ref.read(appStateControllerProvider).appState.epgService;
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

final isBootstrappingProvider = Provider<bool>((ref) {
  return ref.watch(appStateControllerProvider).appState.isBootstrapping;
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(appStateControllerProvider).appState.unreadNotificationCount;
});

final progressListProvider = Provider<List<Progress>>((ref) {
  return ref.watch(appStateControllerProvider).appState.progressList;
});

final dvrRecordingsProvider = Provider<List<DvrRecording>>((ref) {
  return ref.watch(appStateControllerProvider).appState.dvrRecordings;
});

final sourceLabelProvider = Provider<String>((ref) {
  return ref.watch(appStateControllerProvider).appState.sourceLabel;
});

final sourceErrorProvider = Provider<String?>((ref) {
  return ref.watch(appStateControllerProvider).appState.error;
});

final hasDvrFeatureProvider = Provider<bool>((ref) {
  return ref.watch(appStateControllerProvider).appState.hasDvrFeature;
});

// Favorites services are stable ChangeNotifier instances — they notify on
// their own channel (not through AppStateController). Widgets that need to
// react to favorites changes addListener() in initState as before; these
// providers are here so AppShell can pass them without coupling to _appState.
final liveFavoritesServiceProvider = Provider<FavoritesService>((ref) {
  return ref.read(appStateControllerProvider).appState.favoritesService;
});

final vodFavoritesServiceProvider = Provider<FavoritesService>((ref) {
  return ref.read(appStateControllerProvider).appState.vodFavoritesService;
});

final seriesFavoritesServiceProvider = Provider<FavoritesService>((ref) {
  return ref.read(appStateControllerProvider).appState.seriesFavoritesService;
});
