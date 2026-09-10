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

/// Base font size multiplier for the UI.
enum AppFontSize {
  normal('normal', 1),
  large('large', 1.2),
  veryLarge('veryLarge', 1.5);

  const AppFontSize(this.value, this.scale);
  final String value;
  final double scale;

  static AppFontSize fromValue(String? value) => AppFontSize.values.firstWhere(
    (size) => size.value == value,
    orElse: () => AppFontSize.normal,
  );
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
  static const matchRefreshRateKey = 'm3ue_tv_match_refresh_rate';
  static const defaultStartPageKey = 'm3ue_tv_default_start_page';
  static const windowBoundsKey = 'm3ue_tv_window_bounds';
  static const optimizeForKey = 'm3ue_tv_optimize_for';
  static const fontSizeKey = 'm3ue_tv_font_size';

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

  /// Whether the Windows desktop backend may switch the monitor to a refresh
  /// rate matching the source frame rate when playback starts (the classic
  /// "24Hz mode" home-theater feature). Defaults off: the display mode change
  /// briefly blanks the whole screen, which is disruptive on a desktop
  /// monitor. Ignored on every platform other than the Windows mpv backend.
  Future<bool> matchRefreshRate() async {
    final raw = await _read(matchRefreshRateKey);
    return raw as bool? ?? false;
  }

  /// Synchronous access to the in-memory cached refresh-rate-match setting.
  bool get matchRefreshRateSync =>
      (_memory[matchRefreshRateKey] as bool?) ?? false;

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
    debugPrint(
      'VIEW_SETTINGS: fontSize read raw="$raw" → ${AppFontSize.fromValue(raw as String?)}',
    );
    return AppFontSize.fromValue(raw);
  }

  /// Synchronous access to the in-memory cached font size setting.
  AppFontSize get fontSizeSync =>
      AppFontSize.fromValue(_memory[fontSizeKey] as String?);

  Future<void> setFontSize(AppFontSize value) async {
    await _write(fontSizeKey, value.value);
    debugPrint(
      'VIEW_SETTINGS: setFontSize wrote ${value.value} → memory=${_memory[fontSizeKey]}',
    );
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
    debugPrint(
      'VIEW_SETTINGS: _write key="$key" value="$value" store=${store != null ? "present" : "NULL"}',
    );
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
