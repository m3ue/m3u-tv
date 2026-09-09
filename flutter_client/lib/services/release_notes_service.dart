import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One published GitHub release of the `m3u-tv` repo.
class ReleaseNote {
  const ReleaseNote({
    required this.tag,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
    this.prerelease = false,
  });

  factory ReleaseNote.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final rawName = (json['name'] as String?)?.trim();
    final publishedRaw = json['published_at'] as String?;
    return ReleaseNote(
      tag: tag,
      name: rawName != null && rawName.isNotEmpty ? rawName : tag,
      body: (json['body'] as String?)?.trim() ?? '',
      htmlUrl:
          (json['html_url'] as String?) ??
          'https://github.com/m3ue/m3u-tv/releases',
      publishedAt: publishedRaw != null
          ? DateTime.tryParse(publishedRaw)
          : null,
      prerelease: json['prerelease'] as bool? ?? false,
    );
  }

  /// Git tag, e.g. `v1.4.0`. Compared against the running version.
  final String tag;

  /// Human title GitHub shows for the release; falls back to [tag].
  final String name;

  /// Release notes in GitHub-flavoured Markdown (may be empty).
  final String body;

  final String htmlUrl;
  final DateTime? publishedAt;
  final bool prerelease;

  /// [tag] with a leading `v` removed, for `version_compare`-style checks.
  String get normalizedVersion => tag.replaceFirst(RegExp('^v'), '');

  Map<String, dynamic> toJson() => {
    'tag_name': tag,
    'name': name,
    'body': body,
    'html_url': htmlUrl,
    'published_at': publishedAt?.toIso8601String(),
    'prerelease': prerelease,
  };
}

/// Fetches the recent `m3u-tv` GitHub releases for the settings "What's New"
/// tab. Mirrors the editor's `VersionServiceProvider::fetchReleases()`, but
/// runs client-side: one unauthenticated request (GitHub allows 60/hr per IP,
/// far more than a settings screen needs), cached to a small JSON file in the
/// temp directory so a later offline visit still has something to show.
class ReleaseNotesService {
  ReleaseNotesService({
    http.Client? httpClient,
    Directory? cacheDirectory,
    this.cacheTtl = const Duration(hours: 6),
  }) : _httpClient = httpClient ?? http.Client(),
       _cacheDirectoryOverride = cacheDirectory;

  static final Uri _releasesUrl = Uri.parse(
    'https://api.github.com/repos/m3ue/m3u-tv/releases?per_page=30',
  );

  static const _cacheFileName = 'm3u_tv_releases.json';

  final http.Client _httpClient;
  final Directory? _cacheDirectoryOverride;
  final Duration cacheTtl;

  List<ReleaseNote>? _memoryCache;

  /// Returns releases newest-first. Order of resolution:
  /// 1. fresh in-memory / disk cache (unless [forceRefresh]);
  /// 2. a live GitHub request (result is cached);
  /// 3. stale disk cache, if the request failed;
  /// 4. an empty list.
  Future<List<ReleaseNote>> fetch({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) {
      return _memoryCache!;
    }

    final cached = await _readCache();
    if (!forceRefresh && cached != null && !cached.isStale(cacheTtl)) {
      _memoryCache = cached.releases;
      return cached.releases;
    }

    try {
      final response = await _httpClient
          .get(
            _releasesUrl,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'm3u-tv',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == HttpStatus.ok) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final releases = decoded
              .whereType<Map<String, dynamic>>()
              .where((r) => r['draft'] != true)
              .map(ReleaseNote.fromJson)
              .where((r) => r.tag.isNotEmpty)
              .toList();
          _memoryCache = releases;
          await _writeCache(releases);
          return releases;
        }
      }
    } on Exception catch (_) {
      // fall through to the stale cache / empty list
    }

    if (cached != null) {
      _memoryCache = cached.releases;
      return cached.releases;
    }
    return const [];
  }

  Future<File> _cacheFile() async {
    final dir = _cacheDirectoryOverride ?? await getTemporaryDirectory();
    return File('${dir.path}/$_cacheFileName');
  }

  Future<_CachedReleases?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final fetchedAt = DateTime.tryParse(
        decoded['fetched_at'] as String? ?? '',
      );
      final rawList = decoded['releases'];
      if (fetchedAt == null || rawList is! List) return null;
      final releases = rawList
          .whereType<Map<String, dynamic>>()
          .map(ReleaseNote.fromJson)
          .toList();
      return _CachedReleases(fetchedAt: fetchedAt, releases: releases);
    } on Exception catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<ReleaseNote> releases) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(
        jsonEncode({
          'fetched_at': DateTime.now().toUtc().toIso8601String(),
          'releases': releases.map((r) => r.toJson()).toList(),
        }),
      );
    } on Exception catch (_) {
      // A non-writable cache dir (e.g. a locked-down TV) just means no cache.
    }
  }
}

class _CachedReleases {
  const _CachedReleases({required this.fetchedAt, required this.releases});

  final DateTime fetchedAt;
  final List<ReleaseNote> releases;

  bool isStale(Duration ttl) => DateTime.now().difference(fetchedAt) > ttl;
}
