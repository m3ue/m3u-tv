// Xtream API Types

export interface XtreamCredentials {
  server: string;
  username: string;
  password: string;
}

export interface XtreamUserInfo {
  username: string;
  password: string;
  message: string;
  auth: number;
  status: string;
  exp_date: string;
  is_trial: string;
  active_cons: string;
  created_at: string;
  max_connections: string;
  allowed_output_formats: string[];
}

export interface XtreamServerInfo {
  url: string;
  port: string;
  https_port: string;
  server_protocol: string;
  rtmp_port: string;
  timezone: string;
  timestamp_now: number;
  time_now: string;
}

export interface XtreamM3UEditorInfo {
  version: string;
  features: string[];
}

export interface XtreamAuthResponse {
  user_info: XtreamUserInfo;
  server_info: XtreamServerInfo;
  m3u_editor?: XtreamM3UEditorInfo;
}

// Viewer & Progress Types (m3u-editor specific)

export interface PlaylistViewer {
  id: number;
  ulid: string;
  name: string;
  is_admin: boolean;
}

export type WatchContentType = 'live' | 'vod' | 'episode';

export interface WatchProgress {
  content_type: WatchContentType;
  stream_id: number;
  series_id?: number;
  season_number?: number;
  position_seconds: number;
  duration_seconds?: number;
  completed: boolean;
  watch_count: number;
  last_watched_at: string;
}

export interface UpdateProgressParams {
  viewer_id: string;
  content_type: WatchContentType;
  stream_id: number;
  position_seconds?: number;
  duration_seconds?: number;
  completed?: boolean;
  series_id?: number;
  season_number?: number;
}

// Categories
export interface XtreamCategory {
  category_id: string;
  category_name: string;
  parent_id: number;
}

// Live Streams
export interface XtreamLiveStream {
  num: number;
  name: string;
  stream_type: string;
  stream_id: number;
  stream_icon: string;
  epg_channel_id: string | null;
  added: string;
  is_adult: string;
  category_id: string;
  category_ids?: number[];
  custom_sid: string;
  tv_archive: number;
  direct_source: string;
  tv_archive_duration: number;
}

// VOD Streams
export interface XtreamVodStream {
  num: number;
  name: string;
  stream_type: string;
  stream_id: number;
  stream_icon: string;
  rating: string;
  rating_5based: number;
  added: string;
  is_adult: string;
  category_id: string;
  category_ids?: number[];
  container_extension: string;
  custom_sid: string;
  direct_source: string;
}

export interface XtreamVodInfo {
  info: {
    kinopoisk_url?: string;
    tmdb_id?: number;
    name: string;
    o_name?: string;
    cover_big?: string;
    movie_image?: string;
    release_date?: string;
    youtube_trailer?: string;
    director?: string;
    actors?: string;
    cast?: string;
    description?: string;
    plot?: string;
    age?: string;
    mpaa_rating?: string;
    rating_count_kinopoisk?: number;
    country?: string;
    genre?: string;
    duration_secs?: string | number;
    duration?: string;
    bitrate?: number;
    rating?: string | number;
    backdrop_path?: string[];
    video?: {
      index?: number;
      codec_name?: string;
      codec_type?: string;
      width?: number;
      height?: number;
    };
    audio?: {
      index?: number;
      codec_name?: string;
      codec_type?: string;
      sample_rate?: string;
      channels?: number;
    };
  };
  movie_data: {
    stream_id: number;
    name: string;
    added: string;
    category_id: string;
    category_ids?: number[];
    container_extension: string;
    custom_sid: string;
    direct_source: string;
  };
}

// Series
export interface XtreamSeries {
  num: number;
  name: string;
  series_id: number;
  cover: string;
  plot: string;
  cast: string;
  director: string;
  genre: string;
  release_date: string;
  releaseDate?: string;
  last_modified: string;
  rating: string;
  rating_5based: number;
  backdrop_path: string[];
  youtube_trailer: string;
  episode_run_time: string;
  category_id: string;
  category_ids?: number[];
}

export interface XtreamEpisode {
  id: string;
  episode_num: number;
  title: string;
  container_extension: string;
  info: {
    tmdb_id?: number;
    release_date?: string;
    plot?: string;
    duration_secs?: number;
    duration?: string;
    movie_image?: string;
    bitrate?: number;
    rating?: number;
    season?: number;
  };
  custom_sid: string;
  added: string;
  season: number;
  direct_source: string;
}

export interface XtreamSeason {
  air_date: string;
  episode_count: number;
  id: number;
  name: string;
  overview: string;
  season_number: number;
  cover?: string;
  cover_big?: string;
}

export interface XtreamSeriesInfo {
  seasons: XtreamSeason[];
  info: {
    name: string;
    cover: string;
    plot: string;
    cast: string;
    director: string;
    genre: string;
    release_date: string;
    releaseDate?: string;
    last_modified: string;
    rating: string;
    rating_5based: number;
    backdrop_path: string[];
    youtube_trailer: string;
    episode_run_time: string;
    category_id: string;
    category_ids?: number[];
  };
  episodes: {
    [seasonNumber: string]: XtreamEpisode[];
  };
}

// EPG
export interface XtreamEpgListing {
  id: string;
  epg_id: string;
  title: string;
  lang: string;
  start: string;
  end: string;
  description: string;
  channel_id: string;
  start_timestamp: number;
  stop_timestamp: number;
  now_playing?: number;
  has_archive?: number;
}

export interface XtreamShortEpg {
  epg_listings: XtreamEpgListing[];
}

// DVR Types (m3u-editor specific)

export type DvrRecordingStatus =
  | 'scheduled'
  | 'recording'
  | 'post_processing'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface DvrRecording {
  uuid: string;
  title: string;
  subtitle?: string;
  status: DvrRecordingStatus;
  channel_name?: string;
  channel_id?: number;
  scheduled_start: string;
  scheduled_end: string;
  actual_start?: string;
  actual_end?: string;
  duration_seconds?: number;
  file_size_bytes?: number;
  season?: number;
  episode?: number;
  stream_url?: string;
  live_url?: string;
  edl_url?: string;
  has_edl?: boolean;
  metadata?: Record<string, unknown>;
  epg_programme_data?: Record<string, unknown>;
  error_message?: string;
}

export interface ScheduleDvrParams {
  channel_id: number;
  title: string;
  start_time: string;
  end_time: string;
  programme_id?: string;
  start_early_seconds?: number;
  end_late_seconds?: number;
}

export interface CreateDvrSeriesRuleParams {
  channel_id: number;
  title: string;
  match_mode?: 'contains' | 'exact' | 'starts_with';
  series_mode?: 'all' | 'new_flag' | 'unique_se';
  keep_last?: number;
}

// UI Types
export interface ContentItem {
  id: number;
  type: 'live' | 'vod' | 'series';
  name: string;
  icon: string;
  categoryId: string;
  categoryName?: string;
  rating?: number;
  year?: string;
  plot?: string;
  streamUrl?: string;
  epgChannelId?: string;
  containerExtension?: string;
}

export interface CategoryWithContent {
  category: XtreamCategory;
  items: ContentItem[];
}
