# m3u-tv Guidelines

**Stack**: Flutter (Dart), targeting Android TV and tvOS.
**Platforms**: Android TV, Apple TV (tvOS).

## Project location

All source lives under `flutter_client/`. Run every command from that directory.

## Context

This is the TV frontend for the `m3u-editor` system. It focuses on video playback (Live TV/VOD) and EPG (Electronic Program Guide) rendering. The app is D-pad driven — no touch input assumed on TV targets.

## Architecture

- **Navigation**: `dpad` package v3 (Shortcuts + Actions based spatial traversal) + `Navigator` for in-content routing.
- **State**: `ChangeNotifier` / `ListenableBuilder` via `AppStateController`.
- **Player**: `video_player` / platform player via `PlaybackOrchestrator`.
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

### Style
- Material 3 throughout. No `OutlinedButton` — use `FilledButton`, `FilledButton.tonal`, `FilledButton.icon`, or `FilledButton.tonalIcon`.
- Match existing file conventions. No new comments unless the WHY is non-obvious.

### Commands
- **Analyze**: `cd flutter_client && flutter analyze`
- **Test**: `cd flutter_client && flutter test`
- **Run (Android TV)**: `cd flutter_client && flutter run -d <device-id>`
