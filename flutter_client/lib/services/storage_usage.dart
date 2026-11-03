import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

/// What one saved playlist keeps on the device (see [StorageUsage]).
@immutable
class PlaylistStorage {
  const PlaylistStorage({
    required this.playlist,
    required this.usage,
    required this.updatedAt,
    required this.isShown,
    required this.bytesOnDisk,
  });

  final SavedPlaylist playlist;

  /// Its stored catalog, or null when none is kept.
  final CatalogSourceUsage? usage;

  /// When its catalog was last downloaded.
  final DateTime? updatedAt;

  /// Whether it is the playlist on screen.
  final bool isShown;
  final int bytesOnDisk;

  int get itemCount =>
      (usage?.channels ?? 0) + (usage?.movies ?? 0) + (usage?.series ?? 0);
}

/// What the app is storing, for Settings > Storage.
@immutable
class StorageUsage {
  const StorageUsage({
    required this.playlists,
    required this.guideProgrammes,
    required this.guideBytes,
    required this.catalogBytes,
    required this.artworkBytes,
  });

  final List<PlaylistStorage> playlists;
  final int guideProgrammes;
  final int guideBytes;

  /// The whole catalog database: every playlist's lists plus the guide.
  final int catalogBytes;

  /// The artwork cache, or null where it can't be measured.
  final int? artworkBytes;

  int get totalBytes => catalogBytes + (artworkBytes ?? 0);
}
