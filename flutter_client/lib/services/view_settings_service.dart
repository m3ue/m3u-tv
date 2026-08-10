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

/// Persists non-credential view preferences such as the Live TV default layout
/// and the EPG default starting view.
class ViewSettingsService extends ChangeNotifier {
  ViewSettingsService({
    Map<String, Object?>? memory,
    this.store,
  }) : _memory = memory ?? <String, Object?>{};

  static const liveTvLayoutKey = 'm3ue_tv_live_layout';
  static const epgStartViewKey = 'm3ue_tv_epg_start_view';

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
