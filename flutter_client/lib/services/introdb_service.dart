import 'dart:convert';
import 'dart:io';

/// A single segment range (start/end in milliseconds) as returned by
/// TheIntroDB's `/media` endpoint. Either bound may be null per the API's
/// own per-segment-type semantics (see [IntroDbService]).
class IntroDbSegment {
  const IntroDbSegment({this.startMs, this.endMs});

  factory IntroDbSegment.fromJson(Map<String, dynamic> json) {
    final start = json['start_ms'];
    final end = json['end_ms'];
    return IntroDbSegment(
      startMs: start is num ? start.toInt() : null,
      endMs: end is num ? end.toInt() : null,
    );
  }

  final int? startMs;
  final int? endMs;
}

/// The subset of TheIntroDB's `MediaResponse` this app consumes: the first
/// intro and credits entries, when present.
class IntroDbSegments {
  const IntroDbSegments({this.intro, this.credits});

  factory IntroDbSegments.fromJson(Map<String, dynamic> json) {
    IntroDbSegment? firstSegment(String key) {
      final list = json[key];
      if (list is! List || list.isEmpty) return null;
      final first = list.first;
      return first is Map<String, dynamic>
          ? IntroDbSegment.fromJson(first)
          : null;
    }

    return IntroDbSegments(
      intro: firstSegment('intro'),
      credits: firstSegment('credits'),
    );
  }

  final IntroDbSegment? intro;
  final IntroDbSegment? credits;

  bool get isEmpty => intro == null && credits == null;
}

class _IntroDbCacheEntry {
  _IntroDbCacheEntry(this.data) : _fetchedAt = DateTime.now();
  final IntroDbSegments? data;
  final DateTime _fetchedAt;
  bool get isExpired => DateTime.now().difference(_fetchedAt) > _kCacheTtl;
}

const _kCacheTtl = Duration(minutes: 30);
const _kBaseUrl = 'https://api.theintrodb.org/v4';

/// Client for TheIntroDB (https://theintrodb.org), a free community-run API
/// of crowd-verified intro/credits timestamps. v4 keys media by TVDB id, but
/// still accepts a TMDB or IMDb id and resolves it (including TMDB episode
/// numbering) server-side, so that's what we send. Read-only and
/// unauthenticated, no API key required.
class IntroDbService {
  IntroDbService() : _httpClient = HttpClient();

  final HttpClient _httpClient;
  final Map<String, _IntroDbCacheEntry> _cache = {};

  void clearCache() => _cache.clear();

  /// Looks up intro/credits timestamps for a movie or TV episode. Prefers
  /// [tmdbId]; falls back to [imdbId] (format `tt[0-9]{7,8}`) when no TMDB
  /// id is available, e.g. for AIOStreams content. Returns null on any
  /// failure, 404 (no data), or when neither identifier is usable — callers
  /// should treat that exactly like "no data" and skip the feature silently.
  Future<IntroDbSegments?> getSegments({
    int? tmdbId,
    String? imdbId,
    required bool isSeries,
    int? season,
    int? episode,
  }) async {
    final params = <String, String>{};
    if (tmdbId != null) {
      params['tmdb_id'] = '$tmdbId';
    } else if (imdbId != null && imdbId.isNotEmpty) {
      params['imdb_id'] = imdbId;
    } else {
      return null;
    }
    if (isSeries) {
      if (season == null || episode == null) return null;
      params['season'] = '$season';
      params['episode'] = '$episode';
    }

    final cacheKey = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    final cached = _cache[cacheKey];
    if (cached != null && !cached.isExpired) return cached.data;

    final uri = Uri.parse('$_kBaseUrl/media').replace(queryParameters: params);
    IntroDbSegments? result;
    try {
      final request = await _httpClient.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decodeStream(response);
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          final segments = IntroDbSegments.fromJson(decoded);
          result = segments.isEmpty ? null : segments;
        }
      } else {
        await response.drain<void>();
      }
    } on Exception catch (_) {
      result = null;
    }

    _cache[cacheKey] = _IntroDbCacheEntry(result);
    return result;
  }
}
