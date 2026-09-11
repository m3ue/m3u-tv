import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'package:m3u_tv/services/device_performance.dart';
import 'package:m3u_tv/shared/media_image_http_file_service.dart';

/// Disk cache for media poster/thumbnail images.
///
/// Holds up to [_maxCacheObjects] files for 30 days. At ~40-80 KB per
/// (right-sized) poster a full 2000-object cache is ~100-150 MB on disk, which
/// is the point: a poster-dense TV UI blows through 300 objects in a couple of
/// screens and then re-fetches art the user just scrolled past. Low-end
/// hardware gets a smaller ceiling.
///
/// Network fetches go through [MediaImageHttpFileService] (pooled keep-alive
/// client, tier-scaled concurrency) instead of flutter_cache_manager's default.
class MediaImageCacheManager extends CacheManager with ImageCacheManager {
  factory MediaImageCacheManager() => _instance;

  MediaImageCacheManager._()
    : super(
        Platform.operatingSystem == 'tvos'
            ? Config(
                _key,
                maxNrOfCacheObjects: _maxCacheObjects,
                stalePeriod: const Duration(days: 30),
                repo: _tvosRepo(),
                fileService: MediaImageHttpFileService(),
              )
            : Config(
                _key,
                maxNrOfCacheObjects: _maxCacheObjects,
                stalePeriod: const Duration(days: 30),
                fileService: MediaImageHttpFileService(),
              ),
      );

  static int get _maxCacheObjects => DevicePerformance.isReduced ? 800 : 2000;

  static const _key = 'm3uMediaImages';
  static final MediaImageCacheManager _instance = MediaImageCacheManager._();

  /// flutter_cache_manager picks its cache-info repo by
  /// `Platform.isIOS/isAndroid/isMacOS`, none of which are true on tvOS
  /// (`Platform.operatingSystem == 'tvos'`), so it falls back to
  /// `JsonCacheInfoRepository`, which lazily resolves its storage directory
  /// via `getApplicationSupportDirectory()`. That directory cannot be created
  /// on a physical Apple TV (see path_provider_tvos's PathProviderPlugin.swift),
  /// so every cache write threw and images silently failed to load on device
  /// - the simulator permits the write, which is why this doesn't reproduce
  /// there. [tvosCacheDirectory] must be set (from `main.dart`, before any
  /// image widget builds) to a writable directory such as
  /// `getApplicationCacheDirectory()`'s result.
  static JsonCacheInfoRepository _tvosRepo() {
    final repo = JsonCacheInfoRepository(databaseName: _key);
    if (tvosCacheDirectory != null) {
      repo.directory = tvosCacheDirectory;
    }
    return repo;
  }

  static Directory? tvosCacheDirectory;
}

/// Empties the media image cache, skipping under `flutter test` (which sets
/// the `FLUTTER_TEST` environment variable). Constructing
/// [MediaImageCacheManager] there hits `path_provider`'s platform channel,
/// which test suites don't mock; `TestWidgetsFlutterBinding.ensureInitialized()`
/// alone isn't a reliable signal since some tests call it for unrelated
/// reasons, so this checks the environment variable directly instead.
Future<void> emptyMediaImageCacheIfAvailable() async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  await MediaImageCacheManager().emptyCache();
}
