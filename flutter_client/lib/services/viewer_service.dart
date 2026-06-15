// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

class ViewerService {
  ViewerService({Map<String, Object?>? memory, PersistentJsonStore? store})
    : _memory = memory ?? <String, Object?>{},
      _store = store;

  static const _activeViewerKey = 'm3ue_tv_active_viewer';

  final Map<String, Object?> _memory;
  final PersistentJsonStore? _store;

  Future<Viewer?> resolveActiveViewer(List<Viewer> viewers) async {
    if (viewers.isEmpty) return null;
    final savedRaw = _store == null
        ? _memory[_activeViewerKey]
        : await _store.read(_activeViewerKey);
    final savedUlid = savedRaw as String?;
    final saved = savedUlid == null
        ? null
        : viewers.where((viewer) => viewer.ulid == savedUlid).firstOrNull;
    final active =
        saved ??
        viewers.where((viewer) => viewer.isAdmin).firstOrNull ??
        viewers.first;
    await setActiveViewer(active);
    return active;
  }

  Future<void> setActiveViewer(Viewer viewer) async {
    _memory[_activeViewerKey] = viewer.ulid;
    await _store?.write(_activeViewerKey, viewer.ulid);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
