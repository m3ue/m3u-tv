// ignore_for_file: sort_constructors_first

enum ContentType { live, vod, episode, aiostreams }

final RegExp _schemePattern = RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://');

/// Strips trailing slashes and, if [server] has no explicit URI scheme
/// (e.g. a bare `192.168.1.10:8080` typed on a TV remote), prefixes it with
/// `http://` so it can be parsed as an absolute URI downstream.
String normalizeServerUrl(String server) {
  final trimmed = server.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty || _schemePattern.hasMatch(trimmed)) return trimmed;
  return 'http://$trimmed';
}

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
    server: normalizeServerUrl(server),
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
    this.edlUrl,
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
  final String? edlUrl;

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
      edlUrl: _asNullableString(pick(['edl_url'])),
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
    this.edlUrl,
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
  final String? edlUrl;

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
      edlUrl: _asNullableString(pick(['edl_url'])),
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

enum DvrRecordingStatus {
  scheduled,
  recording,
  postProcessing,
  completed,
  failed,
  cancelled,
  // Not a real server-side recording status - only ever seen on a `dvr.status`
  // push signalling the recording was deleted. See _onDvrStatusPush, which
  // removes the recording locally instead of rendering this state.
  deleted,
  unknown,
}

DvrRecordingStatus dvrRecordingStatusFromWire(String value) {
  return switch (value.trim().toLowerCase()) {
    'scheduled' => DvrRecordingStatus.scheduled,
    'recording' ||
    'in_progress' ||
    'in-progress' => DvrRecordingStatus.recording,
    'post_processing' ||
    'post-processing' ||
    'postprocessing' => DvrRecordingStatus.postProcessing,
    'completed' || 'complete' => DvrRecordingStatus.completed,
    'failed' || 'error' => DvrRecordingStatus.failed,
    'cancelled' || 'canceled' => DvrRecordingStatus.cancelled,
    'deleted' => DvrRecordingStatus.deleted,
    _ => DvrRecordingStatus.unknown,
  };
}

class DvrRecording {
  const DvrRecording({
    required this.uuid,
    required this.title,
    required this.status,
    this.subtitle,
    this.channelId,
    this.channelName,
    this.channelIconUrl,
    this.scheduledStart,
    this.scheduledEnd,
    this.actualStart,
    this.actualEnd,
    this.durationSeconds,
    this.fileSizeBytes,
    this.seasonNumber,
    this.episodeNumber,
    this.streamUrl,
    this.liveUrl,
    this.edlUrl,
    this.metadata = const <String, Object?>{},
    this.errorMessage,
  });

  final String uuid;
  final String title;
  final String? subtitle;
  final DvrRecordingStatus status;
  final int? channelId;
  final String? channelName;
  final String? channelIconUrl;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final int? durationSeconds;
  final int? fileSizeBytes;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? streamUrl;
  final String? liveUrl;
  final String? edlUrl;
  final Map<String, Object?> metadata;
  final String? errorMessage;

  bool get isInProgress => status == DvrRecordingStatus.recording;
  bool get isCompleted => status == DvrRecordingStatus.completed;

  String? get playbackUrl {
    if (isInProgress && liveUrl != null) return liveUrl;
    if (isCompleted && streamUrl != null) return streamUrl;
    return streamUrl ?? liveUrl;
  }

  bool get isPlayable => playbackUrl != null && playbackUrl!.isNotEmpty;

  factory DvrRecording.fromXtream(Map<String, Object?> json) {
    Object? pick(List<String> keys) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && '$value'.isNotEmpty) return value;
      }
      return null;
    }

    final title = _asNullableString(pick(['title', 'name'])) ?? 'Recording';
    return DvrRecording(
      uuid: _asNullableString(pick(['uuid', 'id'])) ?? '',
      title: title,
      subtitle: _asNullableString(
        pick(['subtitle', 'episode_title', 'description']),
      ),
      status: dvrRecordingStatusFromWire('${pick(['status', 'state']) ?? ''}'),
      channelId: _asIntOrNull(pick(['channel_id', 'stream_id'])),
      channelName: _asNullableString(
        pick(['channel_name', 'channel', 'stream_name']),
      ),
      channelIconUrl: _asNullableString(
        pick(['channel_icon', 'channel_logo', 'stream_icon']),
      ),
      scheduledStart: _asDateTimeOrNull(
        pick(['scheduled_start', 'start_time', 'starts_at']),
      ),
      scheduledEnd: _asDateTimeOrNull(
        pick(['scheduled_end', 'end_time', 'ends_at']),
      ),
      actualStart: _asDateTimeOrNull(pick(['actual_start', 'started_at'])),
      actualEnd: _asDateTimeOrNull(pick(['actual_end', 'ended_at'])),
      durationSeconds: _asIntOrNull(
        pick(['duration_seconds', 'duration_secs', 'duration']),
      ),
      fileSizeBytes: _asIntOrNull(
        pick(['file_size_bytes', 'file_size', 'size_bytes']),
      ),
      seasonNumber: _asIntOrNull(pick(['season_number', 'season'])),
      episodeNumber: _asIntOrNull(pick(['episode_number', 'episode'])),
      streamUrl: _asNullableString(pick(['stream_url'])),
      liveUrl: _asNullableString(pick(['live_url'])),
      edlUrl: _asNullableString(pick(['edl_url'])),
      metadata: _asMap(pick(['metadata', 'meta'])),
      errorMessage: _asNullableString(
        pick(['error', 'error_message', 'message']),
      ),
    );
  }
}

/// DVR storage usage for the current playlist/guest, from m3u-editor's
/// `get_dvr_storage` action. `quotaBytes` and `percentUsed` are null when
/// the account/guest has no configured quota (unlimited storage).
class DvrStorageInfo {
  const DvrStorageInfo({
    required this.usedBytes,
    required this.recordingCount,
    required this.scope,
    this.quotaBytes,
    this.percentUsed,
  });

  final int usedBytes;
  final int? quotaBytes;
  final double? percentUsed;
  final int recordingCount;
  final String scope;

  factory DvrStorageInfo.fromXtream(Map<String, Object?> json) {
    return DvrStorageInfo(
      usedBytes: _asIntOrNull(json['used_bytes']) ?? 0,
      quotaBytes: _asIntOrNull(json['quota_bytes']),
      percentUsed: _asDoubleOrNull(json['percent_used']),
      recordingCount: _asIntOrNull(json['recording_count']) ?? 0,
      scope: _asNullableString(json['scope']) ?? 'account',
    );
  }
}

/// Pushed over Reverb when a favorite is toggled on another device signed
/// into the same viewer, so this device can apply the change immediately
/// instead of waiting for its next `get_favorites` pull.
class FavoriteToggleEvent {
  const FavoriteToggleEvent({
    required this.viewerId,
    required this.contentType,
    required this.favorited,
    this.streamId,
    this.aioItemId,
    this.title,
    this.thumbnailUrl,
    this.itemType,
    this.aioIntegrationId,
  });

  final String viewerId;

  /// 'live' | 'vod' | 'series' | 'aiostreams'
  final String contentType;
  final int? streamId;
  final String? aioItemId;
  final bool favorited;

  /// AIOStreams-only metadata, carried so a favorite pushed from another
  /// device can be rendered immediately without a live re-fetch from the
  /// addon. Always null for live/vod/series.
  final String? title;
  final String? thumbnailUrl;
  final String? itemType;
  final int? aioIntegrationId;

  static FavoriteToggleEvent? tryFromJson(Map<String, Object?> json) {
    final viewerId = json['viewer_id'];
    final contentType = json['content_type'];
    if (viewerId is! String || viewerId.isEmpty) return null;
    if (contentType is! String || contentType.isEmpty) return null;
    return FavoriteToggleEvent(
      viewerId: viewerId,
      contentType: contentType,
      streamId: _asIntOrNull(json['stream_id']),
      aioItemId: _asNullableString(json['aio_item_id']),
      favorited: json['favorited'] == true,
      title: _asNullableString(json['title']),
      thumbnailUrl: _asNullableString(json['thumbnail_url']),
      itemType: _asNullableString(json['item_type']),
      aioIntegrationId: _asIntOrNull(json['aio_integration_id']),
    );
  }
}

enum MediaRequestStatus {
  pendingApproval,
  approved,
  rejected,
  completed,
  unknown,
}

MediaRequestStatus mediaRequestStatusFromWire(String value) {
  return switch (value.trim().toLowerCase()) {
    'pending_approval' || 'pending' => MediaRequestStatus.pendingApproval,
    'rejected' => MediaRequestStatus.rejected,
    'completed' || 'imported' => MediaRequestStatus.completed,
    'approved' ||
    'monitored' ||
    'grabbing' ||
    'downloading' ||
    'import_pending' ||
    'importing' ||
    'queued' ||
    'paused' => MediaRequestStatus.approved,
    _ => MediaRequestStatus.unknown,
  };
}

/// Structured rating forwarded by `request_search`
/// (`ContentRequestService::search()`'s `rating` field - sourced from
/// Sonarr/Radarr's `ratings.imdb`/`ratings.tmdb`).
class ContentRequestRating {
  const ContentRequestRating({required this.value, this.votes, this.source});

  final double value;
  final int? votes;
  final String? source;

  static ContentRequestRating? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = json.cast<String, Object?>();
    final value = _asDoubleOrNull(map['value']);
    if (value == null) return null;
    return ContentRequestRating(
      value: value,
      votes: _asIntOrNull(map['votes']),
      source: _asNullableString(map['source']),
    );
  }
}

/// A single season of a series search result, mirroring
/// `ContentRequestService::search()`'s per-season shape - enough to let the
/// TV app pre-select missing seasons and show which ones the library already
/// has (`has_file`), without exposing Sonarr's full monitored/statistics shape.
class ContentRequestSeason {
  const ContentRequestSeason({
    required this.seasonNumber,
    this.episodeCount,
    this.episodeFileCount,
    this.hasFile = false,
  });

  final int seasonNumber;
  final int? episodeCount;
  final int? episodeFileCount;
  final bool hasFile;

  factory ContentRequestSeason.fromJson(Map<String, Object?> json) =>
      ContentRequestSeason(
        seasonNumber: _asInt(json['season_number']),
        episodeCount: _asIntOrNull(json['episode_count']),
        episodeFileCount: _asIntOrNull(json['episode_file_count']),
        hasFile: json['has_file'] == true,
      );
}

/// A single search result from `request_search`, combining a title's Arr
/// metadata with the guest-enabled ArrIntegration that can fulfil it.
class ContentRequestSearchResult {
  const ContentRequestSearchResult({
    required this.type,
    required this.externalId,
    required this.integrationId,
    required this.integrationName,
    required this.title,
    this.year,
    this.overview,
    this.poster,
    this.fanart,
    this.genres = const <String>[],
    this.rating,
    this.runtimeMinutes,
    this.certification,
    this.seasons = const <ContentRequestSeason>[],
    this.alreadyAvailable = false,
  });

  final String type;
  final String externalId;
  final int integrationId;
  final String integrationName;
  final String title;
  final String? year;
  final String? overview;
  final String? poster;
  final String? fanart;
  final List<String> genres;
  final ContentRequestRating? rating;
  final int? runtimeMinutes;
  final String? certification;
  final List<ContentRequestSeason> seasons;
  final bool alreadyAvailable;

  factory ContentRequestSearchResult.fromJson(Map<String, Object?> json) =>
      ContentRequestSearchResult(
        type: '${json['type'] ?? ''}',
        externalId: '${json['external_id'] ?? ''}',
        integrationId: _asInt(json['integration_id']),
        integrationName: '${json['integration_name'] ?? ''}',
        title: '${json['title'] ?? ''}',
        year: _asNullableString(json['year']),
        overview: _asNullableString(json['overview']),
        poster: _asNullableString(json['poster']),
        fanart: _asNullableString(json['fanart']),
        genres: _asList(
          json['genres'],
        ).map((genre) => '$genre').toList(growable: false),
        rating: ContentRequestRating.fromJson(json['rating']),
        runtimeMinutes: _asIntOrNull(json['runtime']),
        certification: _asNullableString(json['certification']),
        seasons: _asList(json['seasons'])
            .whereType<Map<String, dynamic>>()
            .map((season) => ContentRequestSeason.fromJson(_asMap(season)))
            .toList(growable: false),
        alreadyAvailable: json['already_available'] == true,
      );
}

/// A guest's content request, mirroring m3u-editor's
/// `ContentRequestService::formatRequest()` wire shape. Also the shape of the
/// `request.status` Reverb push (see MediaRequestStatusEvent on the server).
class MediaRequestSummary {
  const MediaRequestSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.status,
    this.externalId,
    this.integrationId,
    this.integrationName,
    this.seasonNumber,
    this.episodeNumber,
    this.requestedAt,
    this.canDismiss = false,
    this.progress,
    this.quality,
    this.sizeBytes,
    this.timeLeft,
  });

  final int id;
  final String type;
  final String title;
  final MediaRequestStatus status;
  final String? externalId;
  final int? integrationId;
  final String? integrationName;
  final int? seasonNumber;
  final int? episodeNumber;
  final DateTime? requestedAt;
  final bool canDismiss;
  final int? progress;
  final String? quality;
  final int? sizeBytes;
  final String? timeLeft;

  factory MediaRequestSummary.fromJson(Map<String, Object?> json) =>
      MediaRequestSummary(
        id: _asInt(json['id']),
        type: '${json['type'] ?? ''}',
        title: '${json['title'] ?? ''}',
        status: mediaRequestStatusFromWire('${json['status'] ?? ''}'),
        externalId: _asNullableString(json['external_id']),
        integrationId: _asIntOrNull(json['integration_id']),
        integrationName: _asNullableString(json['integration_name']),
        seasonNumber: _asIntOrNull(json['season_number']),
        episodeNumber: _asIntOrNull(json['episode_number']),
        requestedAt: _asDateTimeOrNull(json['requested_at']),
        canDismiss: json['can_dismiss'] == true,
        progress: _asIntOrNull(json['progress']),
        quality: _asNullableString(json['quality']),
        sizeBytes: _asIntOrNull(json['size']),
        timeLeft: _asNullableString(json['time_left']),
      );
}

class EpgProgram {
  const EpgProgram({
    required this.channelId,
    required this.title,
    required this.description,
    required this.start,
    required this.end,
    this.subtitle,
  });

  final String channelId;
  final String title;
  final String description;
  final DateTime start;
  final DateTime end;

  /// Episode-name / programme-episode subtitle, when the upstream source
  /// exposes one (see m3u-editor #1410). Distinct from [title]; null when
  /// absent so display sites can fall back to [title].
  final String? subtitle;

  /// The episode name when available, otherwise the show title. Prefer this
  /// over reading [title] directly at any display or persistence site.
  String get displayTitle => subtitle ?? title;
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
    this.aioItemId,
    this.aioIntegrationId,
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
  // AIOStreams-specific identity (IMDb ID like tt1234567)
  final String? aioItemId;
  final int? aioIntegrationId;

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
        ? _asIntOrNull(json['season_number'])
        : null,
    episodeNumber: json.containsKey('episode_number')
        ? _asIntOrNull(json['episode_number'])
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
    aioItemId: json['aio_item_id'] as String?,
    aioIntegrationId: json.containsKey('aio_integration_id')
        ? _asIntOrNull(json['aio_integration_id'])
        : null,
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
    if (aioItemId != null) 'aio_item_id': aioItemId,
    if (aioIntegrationId != null) 'aio_integration_id': aioIntegrationId,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Progress &&
          viewerId == other.viewerId &&
          contentType == other.contentType &&
          // AIO items are keyed by aioItemId, not streamId.
          (contentType == ContentType.aiostreams
              ? aioItemId == other.aioItemId
              : streamId == other.streamId) &&
          positionSeconds == other.positionSeconds &&
          durationSeconds == other.durationSeconds &&
          completed == other.completed &&
          seriesId == other.seriesId &&
          seasonNumber == other.seasonNumber;

  @override
  int get hashCode => Object.hash(
    viewerId,
    contentType,
    contentType == ContentType.aiostreams ? aioItemId : streamId,
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
    ContentType.aiostreams => 'aiostreams',
  };
}

ContentType contentTypeFromWire(String value) => switch (value) {
  'live' => ContentType.live,
  'episode' => ContentType.episode,
  'aiostreams' => ContentType.aiostreams,
  _ => ContentType.vod,
};

enum DvrSeriesMode { all, newFlag, uniqueSe }

extension DvrSeriesModeWire on DvrSeriesMode {
  String get wireValue => switch (this) {
    DvrSeriesMode.all => 'all',
    DvrSeriesMode.newFlag => 'new_flag',
    DvrSeriesMode.uniqueSe => 'unique_se',
  };
}

/// Parses `DvrSeriesMode` from its m3u-editor wire value. `null` falls back to
/// `uniqueSe` - the server's column default (`dvr_setting.default_series_mode`).
/// Tolerates the legacy `new_only` / `new` spellings that earlier client
/// releases sent before the wire values were corrected.
DvrSeriesMode dvrSeriesModeFromWire(String? value) {
  switch (value) {
    case 'all':
      return DvrSeriesMode.all;
    case 'new_flag':
    case 'new_only':
    case 'new':
      return DvrSeriesMode.newFlag;
    case 'unique_se':
    case null:
      return DvrSeriesMode.uniqueSe;
    default:
      return DvrSeriesMode.uniqueSe;
  }
}

enum DvrMatchMode { contains, exact, startsWith, tmdb }

extension DvrMatchModeWire on DvrMatchMode {
  String get wireValue => switch (this) {
    DvrMatchMode.contains => 'contains',
    DvrMatchMode.exact => 'exact',
    DvrMatchMode.startsWith => 'starts_with',
    DvrMatchMode.tmdb => 'tmdb',
  };
}

DvrMatchMode dvrMatchModeFromWire(String? value) {
  switch (value) {
    case 'exact':
      return DvrMatchMode.exact;
    case 'starts_with':
      return DvrMatchMode.startsWith;
    case 'tmdb':
      return DvrMatchMode.tmdb;
    case 'contains':
    case null:
      return DvrMatchMode.contains;
    default:
      return DvrMatchMode.contains;
  }
}

class DvrSeriesRule {
  const DvrSeriesRule({
    required this.id,
    required this.channelId,
    this.channelName,
    required this.seriesTitle,
    required this.matchMode,
    required this.seriesMode,
    this.keepLast,
    this.priority,
    required this.enabled,
    required this.enableComskip,
    this.startEarlySeconds,
    this.endLateSeconds,
    this.createdAt,
    this.updatedAt,
    this.recordingCount = 0,
  });

  final int id;
  final int channelId;
  final String? channelName;
  final String seriesTitle;
  final DvrMatchMode matchMode;
  final DvrSeriesMode seriesMode;
  final int? keepLast;
  final int? priority;
  final bool enabled;
  final bool enableComskip;
  final int? startEarlySeconds;
  final int? endLateSeconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int recordingCount;

  factory DvrSeriesRule.fromXtream(Map<String, Object?> json) {
    int? asIntOrNull(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    bool asBool(Object? v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) return v == '1' || v.toLowerCase() == 'true';
      return false;
    }

    DateTime? asDate(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toUtc() : null;
    return DvrSeriesRule(
      id: asIntOrNull(json['id']) ?? 0,
      channelId: asIntOrNull(json['channel_id']) ?? 0,
      channelName: json['channel_name'] as String?,
      seriesTitle: (json['series_title'] as String?) ?? '',
      matchMode: dvrMatchModeFromWire(json['match_mode'] as String?),
      seriesMode: dvrSeriesModeFromWire(json['series_mode'] as String?),
      keepLast: asIntOrNull(json['keep_last']),
      priority: asIntOrNull(json['priority']),
      enabled: asBool(json['enabled']),
      enableComskip: asBool(json['enable_comskip']),
      startEarlySeconds: asIntOrNull(json['start_early_seconds']),
      endLateSeconds: asIntOrNull(json['end_late_seconds']),
      createdAt: asDate(json['created_at']),
      updatedAt: asDate(json['updated_at']),
      recordingCount: asIntOrNull(json['recording_count']) ?? 0,
    );
  }
}

/// The seven tunable options exposed by the series-rule configure sheet.
/// All fields are nullable - null means "use server default / omit from request".
/// Passed to `XtreamService.createDvrSeriesRule` via AppShell's
/// `_createDvrSeriesRule` callback.
class DvrSeriesRuleOptions {
  const DvrSeriesRuleOptions({
    this.channelId,
    this.matchMode,
    this.seriesMode,
    this.keepLast,
    this.priority,
    this.startEarlySeconds,
    this.endLateSeconds,
  });

  /// Pin to a specific channel; null means "any channel".
  final int? channelId;

  /// null = server default.
  final DvrMatchMode? matchMode;

  /// null = server default (unique_se on this server).
  final DvrSeriesMode? seriesMode;

  /// null = server default. 0 is valid and means "keep nothing".
  final int? keepLast;

  /// null = server default. Server default is typically 50.
  final int? priority;

  /// null = server default. Seconds to start recording early.
  final int? startEarlySeconds;

  /// null = server default. Seconds to end recording late.
  final int? endLateSeconds;
}

class EpgShowChannel {
  const EpgShowChannel({required this.channelId, this.channelName});

  final int channelId;
  final String? channelName;

  factory EpgShowChannel.fromXtream(Map<String, Object?> json) {
    int? asIntOrNull(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    return EpgShowChannel(
      channelId: asIntOrNull(json['channel_id']) ?? 0,
      channelName: json['channel_name'] as String?,
    );
  }
}

class EpgShowEpisode {
  const EpgShowEpisode({
    required this.channelId,
    this.channelName,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.season,
    this.episode,
    this.description,
    this.subtitle,
  });

  final int channelId;
  final String? channelName;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final int? season;
  final int? episode;
  final String? description;

  /// Episode name from `search_epg_shows.recent_episodes[].subtitle`. Distinct
  /// from [title]; null when absent so display sites can fall back to [title].
  final String? subtitle;

  /// The episode name when available, otherwise the show title. Prefer this
  /// over reading [title] directly at any display or persistence site.
  String get displayTitle => subtitle ?? title;

  factory EpgShowEpisode.fromXtream(Map<String, Object?> json) {
    int? asIntOrNull(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    DateTime parseDate(Object? v) => v is String
        ? (DateTime.tryParse(v) ?? DateTime.now().toUtc())
        : DateTime.now().toUtc();
    return EpgShowEpisode(
      channelId: asIntOrNull(json['channel_id']) ?? 0,
      channelName: json['channel_name'] as String?,
      title: (json['title'] as String?) ?? '',
      startTime: parseDate(json['start_time']).toUtc(),
      endTime: parseDate(json['end_time']).toUtc(),
      season: asIntOrNull(json['season']),
      episode: asIntOrNull(json['episode']),
      description: json['description'] as String?,
      subtitle: nullIfBlank(_asNullableString(json['subtitle'])),
    );
  }
}

class EpgShow {
  const EpgShow({
    required this.normalizedTitle,
    required this.displayTitle,
    required this.channelCount,
    required this.channels,
    required this.episodeCount,
    this.nextAiringAt,
    required this.recentEpisodes,
    this.airingNow = const <EpgShowEpisode>[],
    this.hasSeriesRule = false,
    this.seriesRuleId,
  });

  final String normalizedTitle;
  final String displayTitle;
  final int channelCount;
  final List<EpgShowChannel> channels;
  final int episodeCount;
  final DateTime? nextAiringAt;
  final List<EpgShowEpisode> recentEpisodes;

  /// Programmes currently in progress, from `search_epg_shows.airing_now`.
  /// Same entry shape as [recentEpisodes] - the server shares one payload
  /// builder for both. Empty (never null) when nothing is airing, and empty
  /// against servers predating m3u-editor #1414.
  final List<EpgShowEpisode> airingNow;

  /// True when a persistent DVR series rule already exists for this show
  /// (mirrors `search_epg_shows.has_series_rule`). Surfaces the
  /// "Series rule active" toggle state on the detail screen without a
  /// separate `listDvrSeriesRules` round-trip.
  final bool hasSeriesRule;

  /// Server id of the existing series rule, when one was found. Lets the
  /// detail screen delete the rule without asking the user to pick which
  /// row. Null when [hasSeriesRule] is false.
  final int? seriesRuleId;

  factory EpgShow.fromXtream(Map<String, Object?> json) {
    int asInt(Object? v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    int? asIntOrNull(Object? v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    DateTime? asDate(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toUtc() : null;
    final channels =
        (json['channels'] as List?)
            ?.whereType<Map<dynamic, dynamic>>()
            .map((m) => EpgShowChannel.fromXtream(m.cast<String, Object?>()))
            .toList() ??
        const <EpgShowChannel>[];
    final episodes =
        (json['recent_episodes'] as List?)
            ?.whereType<Map<dynamic, dynamic>>()
            .map((m) => EpgShowEpisode.fromXtream(m.cast<String, Object?>()))
            .toList() ??
        const <EpgShowEpisode>[];
    final airingNow = _asList(json['airing_now'])
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => EpgShowEpisode.fromXtream(m.cast<String, Object?>()))
        .toList();
    return EpgShow(
      normalizedTitle: (json['normalized_title'] as String?) ?? '',
      displayTitle: (json['display_title'] as String?) ?? '',
      channelCount: asInt(json['channel_count']),
      channels: channels,
      episodeCount: asInt(json['episode_count']),
      nextAiringAt: asDate(json['next_airing_at']),
      recentEpisodes: episodes,
      airingNow: airingNow,
      hasSeriesRule: json['has_series_rule'] == true,
      seriesRuleId: asIntOrNull(json['series_rule_id']),
    );
  }
}

List<Object?> _asList(Object? value) =>
    value is List ? value.cast<Object?>() : const <Object?>[];

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
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return '$value';
  return null;
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

DateTime? _asDateTimeOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    );
  }
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  return parsed?.toUtc();
}

String? _yearFromDate(String? value) {
  if (value == null || value.length < 4) return null;
  final match = RegExp(r'\d{4}').firstMatch(value);
  return match?.group(0);
}

/// Treats `null` and blank/whitespace-only strings as "absent" so optional
/// fields fall back cleanly at the display site without leaking the upstream
/// `''` placeholder.
String? nullIfBlank(String? value) =>
    (value == null || value.trim().isEmpty) ? null : value;
