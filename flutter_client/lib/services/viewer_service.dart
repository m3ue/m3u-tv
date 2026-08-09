// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class ViewerService {
  ViewerService({Map<String, Object?>? memory, PersistentJsonStore? store})
    : _memory = memory ?? <String, Object?>{},
      _store = store;

  static const _activeViewerKeyBase = 'm3ue_tv_active_viewer';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;

  /// Scopes the saved active-viewer ulid to a specific server+login so that
  /// switching logins on the same device can never reuse a viewer ulid saved
  /// under a different login (which would misattribute watch progress /
  /// favorites to the wrong person). [loginKey] should uniquely identify
  /// "this server + this username", e.g. `'$server|$username'`.
  static String _keyFor(String? loginKey) =>
      loginKey == null || loginKey.isEmpty
      ? _activeViewerKeyBase
      : '${_activeViewerKeyBase}_$loginKey';

  Future<Viewer?> resolveActiveViewer(
    List<Viewer> viewers, {
    String? loginKey,
    bool persist = true,
  }) async {
    if (viewers.isEmpty) return null;
    final key = _keyFor(loginKey);
    final savedRaw = _store == null ? _memory[key] : await _store.read(key);
    final savedUlid = savedRaw as String?;
    final saved = savedUlid == null
        ? null
        : viewers.where((viewer) => viewer.ulid == savedUlid).firstOrNull;
    final active =
        saved ??
        viewers.where((viewer) => viewer.isAdmin).firstOrNull ??
        viewers.first;
    if (persist) await setActiveViewer(active, loginKey: loginKey);
    return active;
  }

  Future<void> setActiveViewer(Viewer viewer, {String? loginKey}) async {
    final key = _keyFor(loginKey);
    _memory[key] = viewer.ulid;
    await _store?.write(key, viewer.ulid);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
