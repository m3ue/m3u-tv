import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

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

/// Sort order for the VOD (Movies) grid. Defaults to the server's natural
/// order so existing callers see no change. New sort dimensions should be
/// appended here rather than overloading existing values.
enum VodSortOption {
  defaultOrder('defaultOrder'),
  ratingDesc('ratingDesc');

  const VodSortOption(this.value);
  final String value;

  static VodSortOption fromValue(String? value) =>
      VodSortOption.values.firstWhere(
        (option) => option.value == value,
        orElse: () => VodSortOption.defaultOrder,
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
  static const rememberVodSortKey = 'm3ue_tv_remember_vod_sort';
  static const vodSortOptionKey = 'm3ue_tv_vod_sort_option';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? store;

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

  /// Whether the user's chosen VOD sort order survives across launches.
  /// Defaults to `false` so existing users keep today's session-only behavior
  /// (resets to server order on each fresh boot of the app). Persisted as
  /// its own key so toggling this off doesn't clear a separately-stored
  /// [vodSortOption] - the latter is simply ignored until re-enabled.
  Future<bool> rememberVodSort() async {
    final raw = await _read(rememberVodSortKey);
    return raw as bool? ?? false;
  }

  /// Synchronous accessor — see [hdrEnabledSync].
  bool get rememberVodSortSync =>
      (_memory[rememberVodSortKey] as bool?) ?? false;

  Future<void> setRememberVodSort(
    // ignore: avoid_positional_boolean_parameters
    bool value,
  ) async {
    await _write(rememberVodSortKey, value);
    notifyListeners();
  }

  Future<VodSortOption> vodSortOption() async {
    final raw = await _read(vodSortOptionKey);
    return VodSortOption.fromValue(raw as String?);
  }

  /// Synchronous accessor — see [hdrEnabledSync].
  VodSortOption get vodSortOptionSync =>
      VodSortOption.fromValue(_memory[vodSortOptionKey] as String?);

  Future<void> setVodSortOption(VodSortOption option) async {
    await _write(vodSortOptionKey, option.value);
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
