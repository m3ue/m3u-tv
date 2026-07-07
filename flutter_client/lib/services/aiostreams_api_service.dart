import 'dart:convert';
import 'dart:io';

import 'package:m3u_tv/services/xtream_service.dart';

/// A stream option returned by AIOStreams for a given IMDb/TMDB content ID.
class AIOStreamsStream {
  const AIOStreamsStream({
    required this.name,
    required this.title,
    required this.url,
    this.behaviorHints = const <String, dynamic>{},
  });

  factory AIOStreamsStream.fromJson(Map<String, dynamic> json) =>
      AIOStreamsStream(
        name: '${json['name'] ?? ''}',
        title: '${json['title'] ?? json['description'] ?? ''}',
        url: '${json['url'] ?? ''}',
        behaviorHints: json['behaviorHints'] is Map
            ? Map<String, dynamic>.from(
                json['behaviorHints'] as Map<Object?, Object?>,
              )
            : const <String, dynamic>{},
      );

  final String name;
  final String title;
  final String url;
  final Map<String, dynamic> behaviorHints;

  bool get isValid => url.isNotEmpty;
}

/// A single episode entry from a series meta response.
class AIOStreamsVideo {
  const AIOStreamsVideo({
    required this.id,
    required this.title,
    required this.season,
    required this.episode,
    this.thumbnail,
    this.description,
    this.released,
  });

  factory AIOStreamsVideo.fromJson(Map<String, dynamic> json) =>
      AIOStreamsVideo(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? json['name'] ?? ''}',
        season: _parseInt(json['season']) ?? 0,
        episode: _parseInt(json['episode']) ?? 0,
        thumbnail: json['thumbnail'] as String?,
        description: json['overview'] is String
            ? json['overview'] as String
            : (json['description'] is String
                  ? json['description'] as String
                  : null),
        released: json['released'] as String?,
      );

  final String id;
  final String title;
  final int season;
  final int episode;
  final String? thumbnail;
  final String? description;
  final String? released;
}

/// A catalog item (movie or series) from AIOStreams.
class AIOStreamsItem {
  const AIOStreamsItem({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.background,
    this.description,
    this.year,
    this.imdbRating,
    this.genres = const <String>[],
    this.videos = const <AIOStreamsVideo>[],
  });

  factory AIOStreamsItem.fromJson(Map<String, dynamic> json) {
    final rawGenres = json['genres'];
    final genres = rawGenres is List
        ? rawGenres.map((e) => '$e').toList(growable: false)
        : <String>[];
    final rawVideos = json['videos'];
    final videos = rawVideos is List
        ? rawVideos
              .whereType<Map<String, dynamic>>()
              .map(AIOStreamsVideo.fromJson)
              .where((v) => v.id.isNotEmpty && v.season > 0)
              .toList(growable: false)
        : <AIOStreamsVideo>[];
    return AIOStreamsItem(
      id: '${json['id'] ?? ''}',
      type: '${json['type'] ?? ''}',
      name: '${json['name'] ?? ''}',
      poster: json['poster'] as String?,
      background: json['background'] as String?,
      description: json['description'] as String?,
      year: json['year'] != null ? '${json['year']}' : null,
      imdbRating: json['imdbRating'] as String?,
      genres: genres,
      videos: videos,
    );
  }

  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? background;
  final String? description;
  final String? year;
  final String? imdbRating;
  final List<String> genres;
  final List<AIOStreamsVideo> videos;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Proxies AIOStreams Stremio addon requests via m3u-editor's proxy endpoints.
/// Auth tokens stay on the server — clients authenticate with playlist credentials.
class AIOStreamsApiService {
  AIOStreamsApiService({required this.xtreamService})
    : _httpClient = HttpClient();

  final XtreamService xtreamService;
  final HttpClient _httpClient;

  String get _base {
    final c = xtreamService.credentials;
    if (c == null) throw StateError('AIOStreamsApiService: not authenticated');
    return '${c.server}/${c.username}/${c.password}/aiostreams';
  }

  Future<Map<String, dynamic>?> _get(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Exception catch (_) {
      return null;
    }
  }

  /// Browse a catalog. Returns a list of meta items.
  Future<List<AIOStreamsItem>> getCatalog(
    int integrationId,
    String type,
    String catalogId, {
    int skip = 0,
    String? search,
    String? genre,
  }) async {
    final params = <String, String>{};
    if (skip > 0) params['skip'] = '$skip';
    if (search != null && search.isNotEmpty) params['search'] = search;
    if (genre != null && genre.isNotEmpty) params['genre'] = genre;

    final uri = Uri.parse(
      '$_base/$integrationId/catalog/$type/$catalogId.json',
    ).replace(queryParameters: params.isEmpty ? null : params);

    final json = await _get(uri);
    if (json == null) return const [];

    final metas = json['metas'];
    if (metas is! List) return const [];

    return metas
        .whereType<Map<String, dynamic>>()
        .map(AIOStreamsItem.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Fetch available streams for a content item (identified by IMDb/TMDB ID).
  Future<List<AIOStreamsStream>> getStreams(
    int integrationId,
    String type,
    String id,
  ) async {
    final uri = Uri.parse('$_base/$integrationId/stream/$type/$id.json');
    final json = await _get(uri);
    if (json == null) return const [];

    final streams = json['streams'];
    if (streams is! List) return const [];

    return streams
        .whereType<Map<String, dynamic>>()
        .map(AIOStreamsStream.fromJson)
        .where((s) => s.isValid)
        .toList(growable: false);
  }

  /// Fetch metadata for a content item.
  Future<AIOStreamsItem?> getMeta(
    int integrationId,
    String type,
    String id,
  ) async {
    final uri = Uri.parse('$_base/$integrationId/meta/$type/$id.json');
    final json = await _get(uri);
    if (json == null) return null;

    final meta = json['meta'];
    if (meta is! Map<String, dynamic>) return null;

    return AIOStreamsItem.fromJson(meta);
  }
}
