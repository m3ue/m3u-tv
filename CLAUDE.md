# m3u-tv Guidelines

**Stack**: Flutter (Dart), targeting Android TV and tvOS.
**Platforms**: Android TV, Apple TV (tvOS).

## Project location

All source lives under `flutter_client/`. Run every command from that directory.

## Context

This is the TV frontend for the `m3u-editor` system. It focuses on video playback (Live TV/VOD) and EPG (Electronic Program Guide) rendering. The app is D-pad driven — no touch input assumed on TV targets.

## Architecture

- **Navigation**: `dpad` package v3 (Shortcuts + Actions based spatial traversal) + `Navigator` for in-content routing.
- **State**: Riverpod 3 (`flutter_riverpod`), currently through its `legacy.dart` APIs (`ChangeNotifierProvider`, `StateProvider`); prefer `Notifier`/`AsyncNotifier` for new standalone state. Providers live in `lib/providers/app_providers.dart`. `AppStateController` is the underlying orchestrator - Riverpod owns a thin `_AppStateProxy` wrapper so widgets never reference `AppStateController` directly.
- **Player**: `PlaybackOrchestrator` over per-platform backends (ExoPlayer and mpv on Android, mpv/AVKit on Apple, libmpv on desktop, `<video>` on web, server transcode fallback). There is no `video_player` dependency.
- **UI**: Material 3, `DpadFocusable` for all interactive items, `DpadRegion` for focus grouping.

## Rules

### TV Interaction
1. **Tappable custom widgets**: Use `DpadInkWell` (`lib/shared/dpad_ink_well.dart`) instead of the manual `DpadFocusable + Material + InkWell` triple. It bakes in the fast-tap focus fix (explicit `FocusNode.requestFocus()` before the action) and auto-matches the border radius to the `GradientBorderEffect`. Supports `onLongTap` for D-pad hold and touch long-press simultaneously.
2. **Material buttons** (`FilledButton`, `IconButton`, etc.): Wrap in plain `DpadFocusable` — the button provides its own ink/ripple.
3. **Border effects**: `GradientBorderEffect(borderRadius: …)` matching the widget's corner radius. Pill/stadium → `circular(50)`. Cards → `circular(8)`. `DpadInkWell` derives this automatically from its `borderRadius` parameter when `effects` is not set.
4. **Edge navigation**: Leaf `DpadRegion`s use `horizontalEdge: DpadEdgeBehavior.stop` + `onEdge` to activate the sidebar on left-edge press.
5. **Back handling**: Handled globally in `AppShell` via `Shortcuts` mapping Escape / GoBack → `_BackIntent`.

### Localization (mandatory)
The app uses Flutter `gen_l10n`. All user-visible strings **must** be localized — no hard-coded string literals in widget trees.

- **ARB files**: `lib/l10n/app_en.arb` (source of truth) + `app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_zh.arb`.
- **Usage**: `AppLocalizations.of(context).<key>` — throws if delegates are missing, so always add `localizationsDelegates: AppLocalizations.localizationsDelegates` to every `MaterialApp` (including test helpers).
- **Generated files**: Run `flutter gen-l10n` after adding/changing ARB keys; never edit `lib/l10n/app_localizations*.dart` directly.
- **Import order**: `package:m3u_tv/l10n/app_localizations.dart` sorts under `l10n/` — place it after all `features/` imports and before `navigation/` imports.
- **Tests**: Every `MaterialApp` that renders a localized widget must include `localizationsDelegates: AppLocalizations.localizationsDelegates` and `supportedLocales: AppLocalizations.supportedLocales`.
- **New keys**: Add to all five ARBs before running gen-l10n. Keys follow the `<screen><Concept>` pattern (e.g. `settingsAccount`, `liveTvRecord`).

### State Management (Riverpod — mandatory for new features)

The app uses Riverpod 3 for reactive UI state. All new feature screens must follow this pattern:

**Reading data — always use providers, never `AppStateController` directly:**
```dart
class MyScreen extends ConsumerStatefulWidget { ... }
class _MyScreenState extends ConsumerState<MyScreen> {
  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(liveCategoriesProvider); // ✓
    // NOT: widget.appState.liveCategories               // ✗
  }
}
```

**Existing providers** (all in `lib/providers/app_providers.dart`):
- Data: `liveCategoriesProvider`, `vodCategoriesProvider`, `seriesCategoriesProvider`, and `catalogRepositoryProvider` for catalog rows. Channels, movies and series live in the SQLite catalog, not in memory: page them (`CatalogWindow`, `LiveChannelQuery`) or resolve ids (`activeItemsByIds`). `liveChannelsProvider` is only populated when `windowedLiveTvProvider` is false (the `kWindowedLiveTv` comparison path, due to be removed).
- Status: `isConfiguredProvider`, `isBootstrappingProvider`, `isLoadingContentProvider`
- Services (stable, use `ref.read`): `epgServiceProvider`, `liveFavoritesServiceProvider`, `vodFavoritesServiceProvider`, `seriesFavoritesServiceProvider`
- Home extras: `progressListProvider`, `dvrRecordingsProvider`, `sourceLabelProvider`, `sourceErrorProvider`, `hasDvrFeatureProvider`

**Adding a new provider** — add it to `app_providers.dart` using `ref.watch(appStateControllerProvider)` so it reacts to `AppStateController.notifyListeners()`:
```dart
final myNewProvider = Provider<MyType>((ref) {
  return ref.watch(appStateControllerProvider).appState.myNewField;
});
```

**Actions / mutations** still go through `AppStateController` directly (passed as callbacks from `AppShell`). Screens receive action callbacks as constructor params — they do not call `ref.read(appStateControllerProvider).appState.doSomething()`.

**Tests** — wrap with `ProviderScope` and override only the providers the screen watches:
```dart
// Seed an in-memory CatalogRepository inside tester.runAsync: drift's real
// I/O doesn't resolve under the test's fakeAsync zone.
ProviderScope(
  overrides: [
    isConfiguredProvider.overrideWith((_) => true),
    catalogRepositoryProvider.overrideWith((_) => repo),
  ],
  child: MaterialApp(home: MyScreen(...)),
)
```

### Performance (keep work off the UI isolate)
- **JSON/HTTP**: REST calls go through `ApiClient` (`lib/services/api_client.dart`) - shared timeout, `ApiException`, web-safe, large bodies decoded off-isolate. Don't hand-roll `HttpClient` + `jsonDecode` in a service or widget. Exceptions: Xtream catalog downloads (their own byte-streaming transport) and the live-stream preflight probes in `PlaybackOrchestrator`, which must abort mid-body.
- **Big payloads**: use `json_isolate.dart` (`runOffMainIsolate`, `decodeJsonBytesOffMainIsolate`, `BackgroundWorker` for recurring bursts). Pass bytes, not decoded Strings, to an isolate.
- **SQLite**: bulk catalog/EPG writes and full-guide reads go through `CatalogDatabase.computeWithDatabase` above `_offloadThresholdRows`; closures sent to it must capture only sendable values (static helpers, no `this`).
- **build()**: never sort, filter or look up per-item data for a whole list in `build()`. Memoize derived lists on their inputs (see `LiveTvScreen._visibleChannelsFor`) and do per-item lookups in the item builder. Large catalogs (channels, movies, series) are paged from SQLite rather than filtered in Dart: sort and filter in the query (`CatalogSort`, `nameSortKey` for natural order). Sort large lists with `sortByNatural` (precomputed keys), not `list.sort(compareNatural)`.
- **High-frequency state** (playback position, clocks): use a `ValueNotifier` + `ValueListenableBuilder` scoped to the widgets that show it, not `setState` on a large screen.

### Style
- Material 3 throughout. No `OutlinedButton` — use `FilledButton`, `FilledButton.tonal`, `FilledButton.icon`, or `FilledButton.tonalIcon`.
- Match existing file conventions. No new comments unless the WHY is non-obvious.

### Commands
- **Analyze**: `cd flutter_client && flutter analyze lib test` (scoped to avoid the analyzer treating vendored SPM checkouts under `ios/build/`/`macos/build/` — e.g. `firebase_messaging`'s own `pubspec.yaml` — as a nested project to lint; `analyzer.exclude` globs don't suppress this once a directory has its own `pubspec.yaml`)
- **Test**: `cd flutter_client && flutter test test/path/to/file_test.dart` - run only the files covering the change (optionally `--plain-name`), not the whole suite.
- **Run (Android TV)**: `cd flutter_client && flutter run -d <device-id>`
