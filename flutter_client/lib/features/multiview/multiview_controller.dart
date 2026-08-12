import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Holds the set of live channels queued for the Multiview grid.
///
/// Purely an in-memory session selection — like the single player's "now
/// playing" state, it is not persisted and resets on app restart. Channels
/// are added/removed from the Live TV context menu; the Multiview grid
/// screen reads the current list when it opens and owns the actual player
/// instances.
class MultiviewController extends ChangeNotifier {
  static const int maxStreams = 9;

  final List<Channel> _channels = <Channel>[];

  List<Channel> get channels => List<Channel>.unmodifiable(_channels);
  bool get isFull => _channels.length >= maxStreams;
  bool contains(int channelId) => _channels.any((c) => c.id == channelId);

  /// Adds [channel], or removes it if already queued. Returns whether it
  /// ended up in the selection.
  bool toggle(Channel channel) {
    if (contains(channel.id)) {
      _channels.removeWhere((c) => c.id == channel.id);
      notifyListeners();
      return false;
    }
    if (isFull) return false;
    _channels.add(channel);
    notifyListeners();
    return true;
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _channels.length ||
        newIndex < 0 ||
        newIndex >= _channels.length) {
      return;
    }
    final channel = _channels.removeAt(oldIndex);
    _channels.insert(newIndex, channel);
    notifyListeners();
  }

  void clear() {
    if (_channels.isEmpty) return;
    _channels.clear();
    notifyListeners();
  }
}
