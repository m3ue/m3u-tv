// ignore_for_file: sort_constructors_first

enum ContentType { live, vod, episode }

class UserCredentials {
  const UserCredentials({
    required this.server,
    required this.username,
    required this.password,
  });

  final String server;
  final String username;
  final String password;

  UserCredentials normalized() => UserCredentials(
    server: server.replaceAll(RegExp(r'/+$'), ''),
    username: username,
    password: password,
  );
}

class Category {
  const Category({required this.id, required this.name, this.parentId = 0});

  final String id;
  final String name;
  final int parentId;

  factory Category.fromXtream(Map<String, Object?> json) => Category(
    id: '${json['category_id'] ?? ''}',
    name: '${json['category_name'] ?? ''}',
    parentId: _asInt(json['parent_id']),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          id == other.id &&
          name == other.name &&
          parentId == other.parentId;

  @override
  int get hashCode => Object.hash(id, name, parentId);

  @override
  String toString() => 'Category(id: $id, name: $name)';
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.categoryId,
    this.groupTitle,
    this.epgChannelId,
    this.tvgName,
    this.headers = const {},
    this.catchupSupported = false,
    this.catchupDays,
    this.catchupSource,
  });

  final int id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? categoryId;
  final String? groupTitle;
  final String? epgChannelId;
  final String? tvgName;
  final Map<String, String> headers;
  final bool catchupSupported;
  final int? catchupDays;
  final String? catchupSource;

  factory Channel.fromXtream(Map<String, Object?> json, String streamUrl) {
    final catchupSource = _asNullableString(json['catchup_source']);
    final catchupDays = _asIntOrNull(
      json['tv_archive_duration'] ??
          json['catchup_days'] ??
          json['catchup-days'],
    );
    final catchupType = _asNullableString(json['catchup']);
    final hasCatchupType = catchupType != null && catchupType != '0';
    final catchupSupported =
        _asBool(json['tv_archive']) || hasCatchupType || catchupSource != null;
    return Channel(
      id: _asInt(json['stream_id']),
      name: '${json['name'] ?? ''}',
      streamUrl: streamUrl,
      logoUrl: _asNullableString(json['stream_icon']),
      categoryId: _asNullableString(json['category_id']),
      epgChannelId: _asNullableString(json['epg_channel_id']),
      catchupSupported: catchupSupported,
      catchupDays: catchupDays,
      catchupSource: catchupSource,
    );
  }
}

class VodItem {
  const VodItem({
    required this.id,
    required this.name,
    required this.streamUrl,
    required this.containerExtension,
    this.logoUrl,
    this.categoryId,
    this.rating,
  });

  final int id;
  final String name;
  final String streamUrl;
  final String containerExtension;
  final String? logoUrl;
  final String? categoryId;
  final double? rating;

  factory VodItem.fromXtream(Map<String, Object?> json, String streamUrl) =>
      VodItem(
        id: _asInt(json['stream_id']),
        name: '${json['name'] ?? ''}',
        streamUrl: streamUrl,
        containerExtension: '${json['container_extension'] ?? 'mp4'}',
        logoUrl: _asNullableString(json['stream_icon']),
        categoryId: _asNullableString(json['category_id']),
        rating: _asDoubleOrNull(json['rating']),
      );
}

class VodInfo {
  const VodInfo({
    required this.id,
    required this.name,
    this.plot,
    this.genre,
    this.director,
    this.cast,
    this.releaseDate,
    this.year,
    this.duration,
    this.rating,
    this.coverUrl,
    this.backdropUrl,
    this.containerExtension,
    this.tmdbId,
  });

  final int id;
  final String name;
  final String? plot;
  final String? genre;
  final String? director;
  final String? cast;
  final String? releaseDate;
  final String? year;
  final String? duration;
  final double? rating;
  final String? coverUrl;
  final String? backdropUrl;
  final String? containerExtension;
  final int? tmdbId;

  factory VodInfo.fromXtream(Map<String, Object?> json) {
    final info = _asMap(json['info']);
    final movieData = _asMap(json['movie_data']);

    Object? pick(List<String> keys) {
      for (final source in [info, movieData, json]) {
        for (final key in keys) {
          if (source.containsKey(key)) return source[key];
        }
      }
      return null;
    }

    final releaseDate = _asNullableString(
      pick(['release_date', 'releasedate', 'releaseDate']),
    );
    final year =
        _asNullableString(pick(['year'])) ?? _yearFromDate(releaseDate);

    return VodInfo(
      id: _asInt(pick(['stream_id', 'vod_id', 'id'])),
      name: _asNullableString(pick(['name', 'title'])) ?? '',
      plot: _asNullableString(pick(['plot', 'description', 'desc'])),
      genre: _asNullableString(pick(['genre'])),
      director: _asNullableString(pick(['director'])),
      cast: _asNullableString(pick(['cast', 'actors'])),
      releaseDate: releaseDate,
      year: year,
      duration: _durationText(
        pick([
          'duration',
          'duration_secs',
          'duration_seconds',
          'episode_run_time',
        ]),
      ),
      rating: _asDoubleOrNull(info['rating']),
      coverUrl: _asNullableString(
        pick(['cover_big', 'movie_image', 'stream_icon', 'cover']),
      ),
      backdropUrl: _asNullableString(_firstListItem(info['backdrop_path'])),
      containerExtension: _asNullableString(
        pick(['container_extension', 'containerExtension']),
      ),
      tmdbId: _asIntOrNull(pick(['tmdb_id', 'tmdb'])),
    );
  }
}

class Series {
  const Series({
    required this.id,
    required this.name,
    this.coverUrl,
    this.backdropUrl,
    this.categoryId,
    this.plot,
    this.rating,
    this.tmdbId,
  });

  final int id;
  final String name;
  final String? coverUrl;
  final String? backdropUrl;
  final String? categoryId;
  final String? plot;
  final double? rating;
  final int? tmdbId;

  factory Series.fromXtream(Map<String, Object?> json) => Series(
    id: _asInt(json['series_id']),
    name: '${json['name'] ?? ''}',
    coverUrl: _asNullableString(json['cover']),
    backdropUrl: _asNullableString(_firstListItem(json['backdrop_path'])),
    categoryId: _asNullableString(json['category_id']),
    plot: _asNullableString(json['plot']),
    rating: _asDoubleOrNull(json['rating']),
    tmdbId: _asIntOrNull(json['tmdb_id'] ?? json['tmdb']),
  );
}

class Season {
  const Season({
    required this.number,
    required this.name,
    this.episodeCount = 0,
  });

  final int number;
  final String name;
  final int episodeCount;

  factory Season.fromXtream(Map<String, Object?> json) {
    final number = _asInt(json['season_number']);
    return Season(
      number: number,
      name: '${json['name'] ?? 'Season $number'}',
      episodeCount: _asInt(json['episode_count']),
    );
  }
}

class Episode {
  const Episode({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.containerExtension,
    required this.seasonNumber,
    this.plot,
    this.thumbnailUrl,
    this.rating,
    this.duration,
    this.releaseDate,
    this.streamUrl,
  });

  final String id;
  final int episodeNumber;
  final String title;
  final String containerExtension;
  final int seasonNumber;
  final String? plot;
  final String? thumbnailUrl;
  final double? rating;
  final String? duration;
  final String? releaseDate;
  final String? streamUrl;

  factory Episode.fromXtream(Map<String, Object?> json, {String? streamUrl}) {
    final info =
        (json['info'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    Object? pick(List<String> keys) {
      for (final k in keys) {
        final v = info[k] ?? json[k];
        if (v != null && v != '') return v;
      }
      return null;
    }

    return Episode(
      id: '${json['id'] ?? ''}',
      episodeNumber: _asInt(json['episode_num']),
      title: '${json['title'] ?? ''}',
      containerExtension: '${json['container_extension'] ?? 'mp4'}',
      seasonNumber: _asInt(json['season'] ?? info['season']),
      plot: _asNullableString(pick(['plot', 'description', 'desc'])),
      thumbnailUrl: _asNullableString(
        pick(['movie_image', 'cover_big', 'cover', 'thumbnail']),
      ),
      rating: _asDoubleOrNull(pick(['rating'])),
      duration: _durationText(
        pick(['duration', 'duration_secs', 'duration_seconds']),
      ),
      releaseDate: _asNullableString(
        pick(['release_date', 'releasedate', 'air_date']),
      ),
      streamUrl: streamUrl,
    );
  }
}

class SeriesInfo {
  const SeriesInfo({
    required this.series,
    required this.seasons,
    required this.episodesBySeason,
  });

  final Series series;
  final List<Season> seasons;
  final Map<int, List<Episode>> episodesBySeason;
}

class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
  });

  final String channelId;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;
}

class EpgCurrentNext {
  const EpgCurrentNext({
    required this.current,
    this.next,
    required this.progress,
  });

  final EpgProgram current;
  final EpgProgram? next;
  final double progress;
}

class Viewer {
  const Viewer({
    required this.id,
    required this.ulid,
    required this.name,
    required this.isAdmin,
  });

  final int id;
  final String ulid;
  final String name;
  final bool isAdmin;

  factory Viewer.fromJson(Map<String, Object?> json) => Viewer(
    id: _asInt(json['id']),
    ulid: '${json['ulid'] ?? ''}',
    name: '${json['name'] ?? ''}',
    isAdmin: json['is_admin'] == true,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'ulid': ulid,
    'name': name,
    'is_admin': isAdmin,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Viewer &&
          id == other.id &&
          ulid == other.ulid &&
          name == other.name &&
          isAdmin == other.isAdmin;

  @override
  int get hashCode => Object.hash(id, ulid, name, isAdmin);
}

class Progress {
  const Progress({
    required this.viewerId,
    required this.contentType,
    required this.streamId,
    required this.positionSeconds,
    this.durationSeconds,
    this.completed = false,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
    this.title,
    this.episodeTitle,
    this.seriesName,
    this.thumbnailUrl,
    this.backdropUrl,
    this.rating,
    this.runtime,
    this.tmdbId,
    this.plot,
    this.genre,
    this.year,
  });

  final String viewerId;
  final ContentType contentType;
  final int streamId;
  final int positionSeconds;
  final int? durationSeconds;
  final bool completed;
  final int? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? title;
  final String? episodeTitle;
  final String? seriesName;
  final String? thumbnailUrl;
  final String? backdropUrl;
  final String? rating;
  final String? runtime;
  final int? tmdbId;
  final String? plot;
  final String? genre;
  final String? year;

  factory Progress.fromJson(
    Map<String, Object?> json, {
    String? viewerId,
  }) => Progress(
    viewerId: viewerId ?? '${json['viewer_id'] ?? ''}',
    contentType: contentTypeFromWire('${json['content_type'] ?? 'vod'}'),
    streamId: _asInt(json['stream_id']),
    positionSeconds: _asInt(json['position_seconds']),
    durationSeconds: json.containsKey('duration_seconds')
        ? _asInt(json['duration_seconds'])
        : null,
    completed: json['completed'] == true || json['completed'] == 1,
    seriesId: json.containsKey('series_id') ? _asInt(json['series_id']) : null,
    seasonNumber: json.containsKey('season_number')
        ? _asInt(json['season_number'])
        : null,
    episodeNumber: json.containsKey('episode_number')
        ? _asInt(json['episode_number'])
        : null,
    title: json['title'] as String?,
    episodeTitle: json['episode_title'] as String?,
    seriesName: json['series_name'] as String?,
    thumbnailUrl: json['thumbnail_url'] as String?,
    backdropUrl: json['backdrop_url'] as String?,
    rating: json['rating'] != null ? '${json['rating']}' : null,
    runtime: json['runtime'] as String?,
    tmdbId: json.containsKey('tmdb_id') ? _asIntOrNull(json['tmdb_id']) : null,
    plot: json['plot'] as String?,
    genre: json['genre'] as String?,
    year: json['year'] != null ? '${json['year']}' : null,
  );

  Map<String, Object?> toJson() => {
    'viewer_id': viewerId,
    'content_type': contentType.wireName,
    'stream_id': streamId,
    'position_seconds': positionSeconds,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
    'completed': completed,
    if (seriesId != null) 'series_id': seriesId,
    if (seasonNumber != null) 'season_number': seasonNumber,
    if (episodeNumber != null) 'episode_number': episodeNumber,
    if (title != null) 'title': title,
    if (episodeTitle != null) 'episode_title': episodeTitle,
    if (seriesName != null) 'series_name': seriesName,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    if (backdropUrl != null) 'backdrop_url': backdropUrl,
    if (rating != null) 'rating': rating,
    if (runtime != null) 'runtime': runtime,
    if (tmdbId != null) 'tmdb_id': tmdbId,
    if (plot != null) 'plot': plot,
    if (genre != null) 'genre': genre,
    if (year != null) 'year': year,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Progress &&
          viewerId == other.viewerId &&
          contentType == other.contentType &&
          streamId == other.streamId &&
          positionSeconds == other.positionSeconds &&
          durationSeconds == other.durationSeconds &&
          completed == other.completed &&
          seriesId == other.seriesId &&
          seasonNumber == other.seasonNumber;

  @override
  int get hashCode => Object.hash(
    viewerId,
    contentType,
    streamId,
    positionSeconds,
    durationSeconds,
    completed,
    seriesId,
    seasonNumber,
  );
}

extension ContentTypeWire on ContentType {
  String get wireName => switch (this) {
    ContentType.live => 'live',
    ContentType.vod => 'vod',
    ContentType.episode => 'episode',
  };
}

ContentType contentTypeFromWire(String value) => switch (value) {
  'live' => ContentType.live,
  'episode' => ContentType.episode,
  _ => ContentType.vod,
};

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = '$value'.trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'default';
}

String? _asNullableString(Object? value) {
  if (value == null) return null;
  final text = '$value';
  return text.isEmpty ? null : text;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const <String, Object?>{};
}

String? _durationText(Object? value) {
  if (value == null) return null;
  if (value is num) return _durationFromSeconds(value.toInt());
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final seconds = int.tryParse(text);
  if (seconds != null && seconds > 300) return _durationFromSeconds(seconds);
  return text;
}

String _durationFromSeconds(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
  if (hours > 0) return '${hours}h';
  return '${minutes}m';
}

Object? _firstListItem(Object? value) {
  if (value is List && value.isNotEmpty) return value.first;
  return value;
}

String? _yearFromDate(String? value) {
  if (value == null || value.length < 4) return null;
  final match = RegExp(r'\d{4}').firstMatch(value);
  return match?.group(0);
}
