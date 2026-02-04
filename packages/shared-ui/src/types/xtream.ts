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

export interface XtreamAuthResponse {
  user_info: XtreamUserInfo;
  server_info: XtreamServerInfo;
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
    duration_secs?: number;
    duration?: string;
    bitrate?: number;
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
