import 'package:flutter/foundation.dart';

/// Progress snapshot for an AIOStreams item (movie or series episode).
class AIOStreamsProgressItem {
  const AIOStreamsProgressItem({
    required this.itemId,
    required this.type,
    required this.name,
    required this.integrationId,
    required this.positionSeconds,
    required this.lastWatched,
    this.poster,
    this.durationSeconds,
  });

  factory AIOStreamsProgressItem.fromJson(Map<String, Object?> json) =>
      AIOStreamsProgressItem(
        itemId: '${json['item_id'] ?? ''}',
        type: '${json['item_type'] ?? ''}',
        name: '${json['name'] ?? ''}',
        integrationId: (json['integration_id'] as num?)?.toInt() ?? 0,
        positionSeconds: (json['position_seconds'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
        poster: json['poster_url'] as String?,
        lastWatched: json['last_watched_at'] is String
            ? DateTime.tryParse('${json['last_watched_at']}') ?? DateTime.now()
            : DateTime.now(),
      );

  final String itemId;
  final String type;
  final String name;
  final int integrationId;
  final int positionSeconds;
  final int? durationSeconds;
  final String? poster;
  final DateTime lastWatched;

  bool get completed =>
      durationSeconds != null &&
      durationSeconds! > 0 &&
      positionSeconds / durationSeconds! >= 0.9;
}

/// Holds AIOStreams watch progress loaded from the server.
/// Progress is persisted server-side so it is shared across devices for the same account.
class AIOStreamsProgressService extends ChangeNotifier {
  AIOStreamsProgressService();

  final List<AIOStreamsProgressItem> _items = [];

  List<AIOStreamsProgressItem> get continueWatching =>
      List.unmodifiable(_items.where((i) => !i.completed));

  /// Replaces the in-memory list with data received from the server.
  void loadFromServer(List<AIOStreamsProgressItem> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  /// Updates or inserts a progress entry after a successful server save.
  void updateEntry(AIOStreamsProgressItem item) {
    final idx = _items.indexWhere((i) => i.itemId == item.itemId);
    if (idx >= 0) {
      _items[idx] = item;
    } else {
      _items.insert(0, item);
    }
    notifyListeners();
  }
}
