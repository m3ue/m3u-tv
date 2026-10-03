import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Which top-level screen the app opens on a fresh launch. Defaults to Home;
/// Settings is deliberately not an option.
enum DefaultStartPage {
  home('home', RouteNames.home),
  search('search', RouteNames.search),
  liveTv('liveTv', RouteNames.liveTv),
  movies('movies', RouteNames.vod),
  series('series', RouteNames.series);

  const DefaultStartPage(this.value, this.route);

  final String value;

  /// The router location this start page navigates to.
  final String route;

  static DefaultStartPage fromValue(String? value) =>
      DefaultStartPage.values.firstWhere(
        (page) => page.value == value,
        orElse: () => DefaultStartPage.home,
      );
}

/// Available layouts for the Live TV browsing screen.
enum LiveTvLayout {
  list('list'),
  grid('grid'),
  timeline('timeline');

  const LiveTvLayout(this.value);
  final String value;

  static LiveTvLayout fromValue(String? value) =>
      LiveTvLayout.values.firstWhere(
        (layout) => layout.value == value,
        orElse: () => LiveTvLayout.list,
      );
}

/// Starting position for the EPG timeline view.
enum EpgStartView {
  currentTime('currentTime'),
  primeTime('primeTime');

  const EpgStartView(this.value);
  final String value;

  static EpgStartView fromValue(String? value) =>
      EpgStartView.values.firstWhere(
        (view) => view.value == value,
        orElse: () => EpgStartView.currentTime,
      );
}

/// What to display for each row of the EPG timeline's fixed Channels column.
enum ChannelColumnLayout {
  logoAndTitle('logoAndTitle'),
  logoOnly('logoOnly'),
  titleOnly('titleOnly');

  const ChannelColumnLayout(this.value);
  final String value;

  static ChannelColumnLayout fromValue(String? value) =>
      ChannelColumnLayout.values.firstWhere(
        (layout) => layout.value == value,
        orElse: () => ChannelColumnLayout.logoOnly,
      );
}

/// Sort order for a sortable media grid (VOD, Series). Defaults to the
/// server's natural order so existing callers see no change. New sort
/// dimensions should be appended here rather than overloading existing
/// values.
enum MediaSortOption {
  defaultOrder('defaultOrder'),
  ratingDesc('ratingDesc'),
  releaseDateDesc('releaseDateDesc'),
  releaseDateAsc('releaseDateAsc');

  const MediaSortOption(this.value);
  final String value;

  static MediaSortOption fromValue(String? value) =>
      MediaSortOption.values.firstWhere(
        (option) => option.value == value,
        orElse: () => MediaSortOption.defaultOrder,
      );
}

/// Sort order for the Live TV channel list/grid. A separate enum from
/// [MediaSortOption] rather than appended values on it - VOD/Series sort by
/// rating/release date via a windowed SQL query, while channels have neither
/// field and are sorted in memory instead (see `sortChannels` in
/// `shared/channel_sort.dart`), so the two option sets share no cases and
/// would only strain `catalogSortFor`'s exhaustive switch to pretend
/// otherwise.
enum ChannelSortOption {
  playlistOrder('playlistOrder'),
  channelNumber('channelNumber'),
  alphabeticalAsc('alphabeticalAsc'),
  alphabeticalDesc('alphabeticalDesc');

  const ChannelSortOption(this.value);
  final String value;

  static ChannelSortOption fromValue(String? value) =>
      ChannelSortOption.values.firstWhere(
        (option) => option.value == value,
        orElse: () => ChannelSortOption.playlistOrder,
      );
}

/// Whether to optimize image rendering for visual quality or performance.
enum OptimizeFor {
  quality('quality'),
  speed('speed');

  const OptimizeFor(this.value);
  final String value;

  static OptimizeFor fromValue(String? value) => OptimizeFor.values.firstWhere(
    (opt) => opt.value == value,
    orElse: () => OptimizeFor.quality,
  );
}

/// Baseline multiplier applied under all three named sizes below, so one
/// tweak here nudges Normal/Large/Very Large up or down together while
/// keeping their relative ratios (1x/1.2x/1.5x) intact.
const double _fontSizeBase = 1.15;

/// Base font size multiplier for the UI.
enum AppFontSize {
  normal('normal', 1 * _fontSizeBase),
  large('large', 1.2 * _fontSizeBase),
  veryLarge('veryLarge', 1.5 * _fontSizeBase);

  const AppFontSize(this.value, this.scale);
  final String value;
  final double scale;

  static AppFontSize fromValue(String? value) => AppFontSize.values.firstWhere(
    (size) => size.value == value,
    orElse: () => AppFontSize.normal,
  );

  /// The effective size to render/show as selected: [stored] when the user
  /// has explicitly chosen one, otherwise a device-aware default. TV starts
  /// at [veryLarge] - content read from couch distance needs to start
  /// bigger than the desktop/mobile default. The single source of truth for
  /// this fallback - `main.dart` (drives the actual render scale) and the
  /// Settings screen (drives which chip shows as selected) both call this so
  /// they can't drift apart.
  static AppFontSize resolveDefault({
    required AppFontSize? stored,
    required bool isTv,
  }) => stored ?? (isTv ? AppFontSize.veryLarge : AppFontSize.normal);
}

/// Persists non-credential view preferences such as the Live TV default layout
/// and the EPG default starting view.
class ViewSettingsService extends ChangeNotifier {
  ViewSettingsService({
    Map<String, Object?>? memory,
    this.store,
  }) : _memory = memory ?? <String, Object?>{};

  static const liveTvLayoutKey = 'm3ue_tv_live_layout';
  static const epgStartViewKey = 'm3ue_tv_epg_start_view';
  static const channelColumnLayoutKey = 'm3ue_tv_channel_column_layout';
  static const hdrEnabledKey = 'm3ue_tv_hdr_enabled';
  static const rememberMediaSortKey = 'm3ue_tv_remember_vod_sort';
  static const vodSortOptionKey = 'm3ue_tv_vod_sort_option';
  static const seriesSortOptionKey = 'm3ue_tv_series_sort_option';
  static const liveTvSortOptionKey = 'm3ue_tv_live_tv_sort_option';
  static const vodFavoritesFirstKey = 'm3ue_tv_vod_favorites_first';
  static const seriesFavoritesFirstKey = 'm3ue_tv_series_favorites_first';
  static const liveTvFavoritesFirstKey = 'm3ue_tv_live_tv_favorites_first';
  static const matchRefreshRateKey = 'm3ue_tv_match_refresh_rate';
  static const defaultStartPageKey = 'm3ue_tv_default_start_page';
  static const windowBoundsKey = 'm3ue_tv_window_bounds';
  static const optimizeForKey = 'm3ue_tv_optimize_for';
  static const fontSizeKey = 'm3ue_tv_font_size';
  static const navigationSoundEnabledKey = 'm3ue_tv_navigation_sound_enabled';
  static const volumeKey = 'm3ue_tv_volume';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? store;

  Future<DefaultStartPage> defaultStartPage() async {
    final raw = await _read(defaultStartPageKey);
    return DefaultStartPage.fromValue(raw as String?);
  }

  /// Synchronous access to the in-memory cached start page. Valid once
  /// [defaultStartPage] has resolved at least once.
  DefaultStartPage get defaultStartPageSync =>
      DefaultStartPage.fromValue(_memory[defaultStartPageKey] as String?);

  Future<void> setDefaultStartPage(DefaultStartPage page) async {
    await _write(defaultStartPageKey, page.value);
    notifyListeners();
  }

  Future<LiveTvLayout> liveTvLayout() async {
    final raw = await _read(liveTvLayoutKey);
    return LiveTvLayout.fromValue(raw as String?);
  }

  /// Whether a Live TV layout has ever been persisted via this service.
  /// Used to gate one-time migration of the legacy per-viewer layout
  /// preference into this shared store.
  Future<bool> hasLiveTvLayout() async =>
      (await _read(liveTvLayoutKey)) != null;

  /// Synchronous access to the in-memory cached layout. Use after the service
  /// has been loaded or when a [notifyListeners] rebuild is imminent.
  LiveTvLayout get liveTvLayoutSync =>
      LiveTvLayout.fromValue(_memory[liveTvLayoutKey] as String?);

  Future<void> setLiveTvLayout(LiveTvLayout layout) async {
    await _write(liveTvLayoutKey, layout.value);
    notifyListeners();
  }

  Future<EpgStartView> epgStartView() async {
    final raw = await _read(epgStartViewKey);
    return EpgStartView.fromValue(raw as String?);
  }

  /// Synchronous access to the in-memory cached EPG start view.
  EpgStartView get epgStartViewSync =>
      EpgStartView.fromValue(_memory[epgStartViewKey] as String?);

  Future<void> setEpgStartView(EpgStartView view) async {
    await _write(epgStartViewKey, view.value);
    notifyListeners();
  }

  Future<ChannelColumnLayout> channelColumnLayout() async {
    final raw = await _read(channelColumnLayoutKey);
    return ChannelColumnLayout.fromValue(raw as String?);
  }

  /// Synchronous access to the in-memory cached channel column layout.
  ChannelColumnLayout get channelColumnLayoutSync =>
      ChannelColumnLayout.fromValue(_memory[channelColumnLayoutKey] as String?);

  Future<void> setChannelColumnLayout(ChannelColumnLayout layout) async {
    await _write(channelColumnLayoutKey, layout.value);
    notifyListeners();
  }

  /// Whether native mpv desktop backends (Linux/Windows) are allowed to
  /// switch playback and the OS display into HDR mode. Defaults on, matching
  /// the always-on behavior before this setting existed.
  Future<bool> hdrEnabled() async {
    final raw = await _read(hdrEnabledKey);
    return raw as bool? ?? true;
  }

  /// Synchronous access to the in-memory cached HDR setting.
  bool get hdrEnabledSync => (_memory[hdrEnabledKey] as bool?) ?? true;

  Future<void> setHdrEnabled(
    // ignore: avoid_positional_boolean_parameters
    bool enabled,
  ) async {
    await _write(hdrEnabledKey, enabled);
    notifyListeners();
  }

  /// Whether the user's chosen media sort order (VOD, Series, Live TV)
  /// survives across launches. Defaults to `false` so existing users keep
  /// today's session-only behavior (resets to server order on each fresh
  /// boot of the app). Shared across every sortable screen - persisted as
  /// its own key so toggling this off doesn't clear the separately-stored
  /// [vodSortOption]/[seriesSortOption]/[liveTvSortOption], which are simply
  /// ignored until re-enabled.
  Future<bool> rememberMediaSort() async {
    final raw = await _read(rememberMediaSortKey);
    return raw as bool? ?? false;
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  bool get rememberMediaSortSync =>
      (_memory[rememberMediaSortKey] as bool?) ?? false;

  Future<void> setRememberMediaSort(
    // ignore: avoid_positional_boolean_parameters
    bool value,
  ) async {
    await _write(rememberMediaSortKey, value);
    notifyListeners();
  }

  Future<MediaSortOption> vodSortOption() async {
    final raw = await _read(vodSortOptionKey);
    return MediaSortOption.fromValue(raw as String?);
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  MediaSortOption get vodSortOptionSync =>
      MediaSortOption.fromValue(_memory[vodSortOptionKey] as String?);

  Future<void> setVodSortOption(MediaSortOption option) async {
    await _write(vodSortOptionKey, option.value);
    notifyListeners();
  }

  Future<MediaSortOption> seriesSortOption() async {
    final raw = await _read(seriesSortOptionKey);
    return MediaSortOption.fromValue(raw as String?);
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  MediaSortOption get seriesSortOptionSync =>
      MediaSortOption.fromValue(_memory[seriesSortOptionKey] as String?);

  Future<void> setSeriesSortOption(MediaSortOption option) async {
    await _write(seriesSortOptionKey, option.value);
    notifyListeners();
  }

  Future<ChannelSortOption> liveTvSortOption() async {
    final raw = await _read(liveTvSortOptionKey);
    return ChannelSortOption.fromValue(raw as String?);
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  ChannelSortOption get liveTvSortOptionSync =>
      ChannelSortOption.fromValue(_memory[liveTvSortOptionKey] as String?);

  Future<void> setLiveTvSortOption(ChannelSortOption option) async {
    await _write(liveTvSortOptionKey, option.value);
    notifyListeners();
  }

  /// Whether favorited movies sort ahead of everything else in the VOD grid
  /// (each half keeping the active [vodSortOption]). Defaults on. Like the
  /// sort options, only read/written by the screen while [rememberMediaSort]
  /// is on - otherwise every launch starts back at this default.
  Future<bool> vodFavoritesFirst() async {
    final raw = await _read(vodFavoritesFirstKey);
    return raw as bool? ?? true;
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  bool get vodFavoritesFirstSync =>
      (_memory[vodFavoritesFirstKey] as bool?) ?? true;

  Future<void> setVodFavoritesFirst(
    // ignore: avoid_positional_boolean_parameters
    bool value,
  ) async {
    await _write(vodFavoritesFirstKey, value);
    notifyListeners();
  }

  /// Series counterpart of [vodFavoritesFirst], stored independently.
  Future<bool> seriesFavoritesFirst() async {
    final raw = await _read(seriesFavoritesFirstKey);
    return raw as bool? ?? true;
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  bool get seriesFavoritesFirstSync =>
      (_memory[seriesFavoritesFirstKey] as bool?) ?? true;

  Future<void> setSeriesFavoritesFirst(
    // ignore: avoid_positional_boolean_parameters
    bool value,
  ) async {
    await _write(seriesFavoritesFirstKey, value);
    notifyListeners();
  }

  /// Live TV counterpart of [vodFavoritesFirst], stored independently.
  Future<bool> liveTvFavoritesFirst() async {
    final raw = await _read(liveTvFavoritesFirstKey);
    return raw as bool? ?? true;
  }

  /// Synchronous accessor - see [hdrEnabledSync].
  bool get liveTvFavoritesFirstSync =>
      (_memory[liveTvFavoritesFirstKey] as bool?) ?? true;

  Future<void> setLiveTvFavoritesFirst(
    // ignore: avoid_positional_boolean_parameters
    bool value,
  ) async {
    await _write(liveTvFavoritesFirstKey, value);
    notifyListeners();
  }

  /// Whether the Windows/Android backends may switch the display to a
  /// refresh rate matching the source frame rate when playback starts (the
  /// classic "24Hz mode" home-theater feature). Defaults off on those two
  /// platforms: the display mode change briefly blanks/flashes the screen.
  /// Defaults **on** for tvOS, since its `AVDisplayManager`-driven refresh
  /// matching shipped unconditionally before this setting existed -- this
  /// keeps existing tvOS users' behavior unchanged now that it's a real
  /// toggle. Ignored on every other platform.
  Future<bool> matchRefreshRate() async {
    final raw = await _read(matchRefreshRateKey);
    return raw as bool? ?? _defaultMatchRefreshRate;
  }

  /// Synchronous access to the in-memory cached refresh-rate-match setting.
  bool get matchRefreshRateSync =>
      (_memory[matchRefreshRateKey] as bool?) ?? _defaultMatchRefreshRate;

  static bool get _defaultMatchRefreshRate =>
      !kIsWeb && Platform.operatingSystem == 'tvos';

  Future<void> setMatchRefreshRate(
    // ignore: avoid_positional_boolean_parameters
    bool enabled,
  ) async {
    await _write(matchRefreshRateKey, enabled);
    notifyListeners();
  }

  /// Last persisted desktop window geometry (Windows/macOS/Linux only), or
  /// null if the window has never been moved/resized on this install. Stored
  /// as `{x, y, width, height, maximized}` so a cold launch can reopen where
  /// the user left off.
  Future<WindowBounds?> windowBounds() async {
    final raw = await _read(windowBoundsKey);
    return WindowBounds.fromJson(raw);
  }

  Future<void> setWindowBounds(WindowBounds bounds) async {
    await _write(windowBoundsKey, bounds.toJson());
  }

  Future<OptimizeFor> optimizeFor() async {
    final raw = await _read(optimizeForKey);
    return OptimizeFor.fromValue(raw as String?);
  }

  /// Synchronous access to the in-memory cached optimize-for setting.
  OptimizeFor get optimizeForSync =>
      OptimizeFor.fromValue(_memory[optimizeForKey] as String?);

  Future<void> setOptimizeFor(OptimizeFor value) async {
    await _write(optimizeForKey, value.value);
    notifyListeners();
  }

  Future<AppFontSize> fontSize() async {
    final raw = await _read(fontSizeKey);
    return AppFontSize.fromValue(raw as String?);
  }

  /// The persisted font size, or null if the user has never chosen one. See
  /// [fontSizeSyncOrNull] for why this differs from [fontSize].
  Future<AppFontSize?> fontSizeOrNull() async {
    final raw = await _read(fontSizeKey);
    return raw == null ? null : AppFontSize.fromValue(raw as String?);
  }

  /// Synchronous access to the in-memory cached font size setting.
  AppFontSize get fontSizeSync =>
      AppFontSize.fromValue(_memory[fontSizeKey] as String?);

  /// Synchronous access to the persisted font size, or null if the user has
  /// never chosen one. Lets callers apply a device-specific default (e.g. TV
  /// defaults to [AppFontSize.large]) only on first launch, instead of the
  /// fixed [AppFontSize.normal] fallback [fontSizeSync] always returns.
  /// Only meaningful after [fontSize] has been awaited at least once (see the
  /// preload in `main.dart`) - before that the key is simply absent from the
  /// in-memory cache and this also returns null.
  AppFontSize? get fontSizeSyncOrNull {
    final raw = _memory[fontSizeKey] as String?;
    return raw == null ? null : AppFontSize.fromValue(raw);
  }

  Future<void> setFontSize(AppFontSize value) async {
    await _write(fontSizeKey, value.value);
    notifyListeners();
  }

  /// Whether the D-pad navigation "click" sound plays on TV/desktop focus
  /// changes. Defaults on, matching the always-on behavior before this
  /// setting existed. Ignored on touch devices, which never play it.
  Future<bool> navigationSoundEnabled() async {
    final raw = await _read(navigationSoundEnabledKey);
    return raw as bool? ?? true;
  }

  /// Synchronous access to the in-memory cached navigation sound setting.
  bool get navigationSoundEnabledSync =>
      (_memory[navigationSoundEnabledKey] as bool?) ?? true;

  Future<void> setNavigationSoundEnabled(
    // ignore: avoid_positional_boolean_parameters
    bool enabled,
  ) async {
    await _write(navigationSoundEnabledKey, enabled);
    notifyListeners();
  }

  /// Desktop-only app playback volume (independent of system volume),
  /// applied as the default for every new stream and on launch. Defaults to
  /// full volume, matching today's behavior before this setting existed.
  Future<double> volume() async {
    final raw = await _read(volumeKey);
    return (raw as num?)?.toDouble() ?? 1.0;
  }

  /// Synchronous access to the in-memory cached volume setting.
  double get volumeSync => (_memory[volumeKey] as num?)?.toDouble() ?? 1.0;

  Future<void> setVolume(double value) async {
    await _write(volumeKey, value.clamp(0.0, 1.0));
    notifyListeners();
  }

  Future<Object?> _read(String key) async {
    final store = this.store;
    if (store == null) return _memory[key];
    final value = await store.read(key);
    _memory[key] = value;
    return value;
  }

  Future<void> _write(String key, Object? value) async {
    _memory[key] = value;
    await store?.write(key, value);
  }
}

/// Persisted desktop window geometry. Position/size are in logical pixels as
/// reported by `window_manager`; [maximized] takes precedence on restore.
@immutable
class WindowBounds {
  const WindowBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maximized,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final bool maximized;

  static WindowBounds? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final width = (raw['width'] as num?)?.toDouble();
    final height = (raw['height'] as num?)?.toDouble();
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    if (width == null || height == null || x == null || y == null) return null;
    // Guard against absurd or degenerate saved sizes (e.g. a minimized window
    // that reported a near-zero rect) so restore never opens an unusable frame.
    if (width < 400 || height < 300 || width > 20000 || height > 20000) {
      return null;
    }
    return WindowBounds(
      x: x,
      y: y,
      width: width,
      height: height,
      maximized: raw['maximized'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'maximized': maximized,
  };
}
