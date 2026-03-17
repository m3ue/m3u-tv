import {
  XtreamCredentials,
  XtreamAuthResponse,
  XtreamCategory,
  XtreamLiveStream,
  XtreamVodStream,
  XtreamVodInfo,
  XtreamSeries,
  XtreamSeriesInfo,
  XtreamShortEpg,
  XtreamEpgListing,
  ContentItem,
  PlaylistViewer,
  WatchProgress,
  UpdateProgressParams,
  WatchContentType,
} from '../types/xtream';

const M3UE_CLIENT_HEADER = 'X-M3UE-Client';
const M3UE_CLIENT_VALUE = 'm3u-tv';

class XtreamService {
  private credentials: XtreamCredentials | null = null;
  private isM3UEditor: boolean = false;

  setCredentials(credentials: XtreamCredentials) {
    // Ensure server URL doesn't have trailing slash
    this.credentials = {
      ...credentials,
      server: credentials.server.replace(/\/+$/, ''),
    };
  }

  clearCredentials(): void {
    this.credentials = null;
  }

  getCredentials(): XtreamCredentials | null {
    return this.credentials;
  }

  isConfigured(): boolean {
    return this.credentials !== null;
  }

  private getBaseUrl(): string {
    if (!this.credentials) {
      throw new Error('Xtream credentials not configured');
    }
    return this.credentials.server;
  }

  private getApiUrl(action?: string, params?: Record<string, string>): string {
    if (!this.credentials) {
      throw new Error('Xtream credentials not configured');
    }
    const { username, password } = this.credentials;
    let url = `${this.getBaseUrl()}/player_api.php?username=${username}&password=${password}`;
    if (action) {
      url += `&action=${action}`;
    }
    if (params) {
      Object.entries(params).forEach(([key, value]) => {
        url += `&${key}=${value}`;
      });
    }
    return url;
  }

  setM3UEditor(value: boolean): void {
    this.isM3UEditor = value;
  }

  getIsM3UEditor(): boolean {
    return this.isM3UEditor;
  }

  private getClientHeaders(): Record<string, string> {
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (this.isM3UEditor) {
      headers[M3UE_CLIENT_HEADER] = M3UE_CLIENT_VALUE;
    }
    return headers;
  }

  private async fetchJson<T>(url: string): Promise<T> {
    const response = await fetch(url, {
      method: 'GET',
      headers: this.getClientHeaders(),
    });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  }

  private async fetchPost<T>(url: string, body: Record<string, string>): Promise<T> {
    const form = new URLSearchParams(body);
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        ...this.getClientHeaders(),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: form.toString(),
    });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    return response.json();
  }

  // Authentication
  async authenticate(): Promise<XtreamAuthResponse> {
    const url = this.getApiUrl();
    return this.fetchJson<XtreamAuthResponse>(url);
  }

  // Live TV
  async getLiveCategories(): Promise<XtreamCategory[]> {
    const url = this.getApiUrl('get_live_categories');
    return this.fetchJson<XtreamCategory[]>(url);
  }

  async getLiveStreams(categoryId?: string): Promise<XtreamLiveStream[]> {
    const params = categoryId ? { category_id: categoryId } : undefined;
    const url = this.getApiUrl('get_live_streams', params);
    return this.fetchJson<XtreamLiveStream[]>(url);
  }

  getLiveStreamUrl(streamId: number, format: string = 'm3u8'): string {
    if (!this.credentials) {
      throw new Error('Xtream credentials not configured');
    }
    const { username, password } = this.credentials;
    return `${this.getBaseUrl()}/live/${username}/${password}/${streamId}.${format}`;
  }

  // VOD
  async getVodCategories(): Promise<XtreamCategory[]> {
    const url = this.getApiUrl('get_vod_categories');
    return this.fetchJson<XtreamCategory[]>(url);
  }

  async getVodStreams(categoryId?: string): Promise<XtreamVodStream[]> {
    const params = categoryId ? { category_id: categoryId } : undefined;
    const url = this.getApiUrl('get_vod_streams', params);
    return this.fetchJson<XtreamVodStream[]>(url);
  }

  async getVodInfo(vodId: number): Promise<XtreamVodInfo> {
    const url = this.getApiUrl('get_vod_info', { vod_id: String(vodId) });
    return this.fetchJson<XtreamVodInfo>(url);
  }

  getVodStreamUrl(streamId: number, extension: string = 'mp4'): string {
    if (!this.credentials) {
      throw new Error('Xtream credentials not configured');
    }
    const { username, password } = this.credentials;
    return `${this.getBaseUrl()}/movie/${username}/${password}/${streamId}.${extension}`;
  }

  // Series
  async getSeriesCategories(): Promise<XtreamCategory[]> {
    const url = this.getApiUrl('get_series_categories');
    return this.fetchJson<XtreamCategory[]>(url);
  }

  async getSeries(categoryId?: string): Promise<XtreamSeries[]> {
    const params = categoryId ? { category_id: categoryId } : undefined;
    const url = this.getApiUrl('get_series', params);
    return this.fetchJson<XtreamSeries[]>(url);
  }

  async getSeriesInfo(seriesId: number): Promise<XtreamSeriesInfo> {
    const url = this.getApiUrl('get_series_info', { series_id: String(seriesId) });
    return this.fetchJson<XtreamSeriesInfo>(url);
  }

  getSeriesStreamUrl(episodeId: string, extension: string = 'mp4'): string {
    if (!this.credentials) {
      throw new Error('Xtream credentials not configured');
    }
    const { username, password } = this.credentials;
    return `${this.getBaseUrl()}/series/${username}/${password}/${episodeId}.${extension}`;
  }

  // EPG
  async getShortEpg(streamId: number, limit?: number): Promise<XtreamShortEpg> {
    const params: Record<string, string> = { stream_id: String(streamId) };
    if (limit) {
      params.limit = String(limit);
    }
    const url = this.getApiUrl('get_short_epg', params);
    return this.fetchJson<XtreamShortEpg>(url);
  }

  async getSimpleDataTable(streamId: number): Promise<XtreamShortEpg> {
    const url = this.getApiUrl('get_simple_data_table', { stream_id: String(streamId) });
    return this.fetchJson<XtreamShortEpg>(url);
  }

  /**
   * Batch EPG fetch using the server's native get_epg_batch endpoint.
   * Fetches yesterday + today to ensure current-time programmes are included.
   * Falls back to individual get_short_epg calls if batch endpoint fails.
   */
  async getEpgBatch(streamIds: number[]): Promise<Record<string, XtreamShortEpg>> {
    if (streamIds.length === 0) return {};

    // Try native batch endpoint first (m3u-editor specific)
    if (this.isM3UEditor) {
      try {
        const idsParam = streamIds.join(',');
        const result = await this._fetchTwoDays(idsParam);
        return result;
      } catch (err) {
        console.warn('[XtreamService] getEpgBatch batch failed:', err);
        // Fall through to individual fetches
      }
    }

    // Fallback: fetch individually in parallel chunks
    const result: Record<string, XtreamShortEpg> = {};
    const CHUNK_SIZE = 5;
    for (let i = 0; i < streamIds.length; i += CHUNK_SIZE) {
      const chunk = streamIds.slice(i, i + CHUNK_SIZE);
      const responses = await Promise.allSettled(
        chunk.map((id) => this.getShortEpg(id, 10)),
      );
      for (let j = 0; j < chunk.length; j++) {
        const res = responses[j];
        result[String(chunk[j])] = res.status === 'fulfilled'
          ? res.value
          : { epg_listings: [] };
      }
    }
    return result;
  }

  /**
   * Batch full EPG fetch for EPG grid.
   * Fetches yesterday + today to ensure current-time programmes are included.
   * Uses native get_epg_batch when available.
   */
  async getFullEpgBatch(streamIds: number[]): Promise<Record<string, XtreamShortEpg>> {
    if (streamIds.length === 0) return {};

    // Try native batch endpoint (returns same format as get_simple_data_table)
    if (this.isM3UEditor) {
      try {
        const idsParam = streamIds.join(',');
        const result = await this._fetchTwoDays(idsParam);
        return result;
      } catch (err) {
        console.warn('[XtreamService] getFullEpgBatch batch failed:', err);
        // Fall through to individual fetches
      }
    }

    // Fallback: fetch individually
    const result: Record<string, XtreamShortEpg> = {};
    const CHUNK_SIZE = 5;
    for (let i = 0; i < streamIds.length; i += CHUNK_SIZE) {
      const chunk = streamIds.slice(i, i + CHUNK_SIZE);
      const responses = await Promise.allSettled(
        chunk.map((id) => this.getSimpleDataTable(id)),
      );
      for (let j = 0; j < chunk.length; j++) {
        const res = responses[j];
        result[String(chunk[j])] = res.status === 'fulfilled'
          ? res.value
          : { epg_listings: [] };
      }
    }
    return result;
  }

  /**
   * Fetch EPG batch for yesterday + today and merge results.
   * Ensures the current time period is always covered regardless of
   * how the server interprets date boundaries.
   */
  private async _fetchTwoDays(idsParam: string): Promise<Record<string, XtreamShortEpg>> {
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setDate(yesterday.getDate() - 1);
    const todayStr = now.toISOString().split('T')[0];
    const yesterdayStr = yesterday.toISOString().split('T')[0];

    const urlYesterday = this.getApiUrl('get_epg_batch', { stream_ids: idsParam, date: yesterdayStr });
    const urlToday = this.getApiUrl('get_epg_batch', { stream_ids: idsParam, date: todayStr });

    const [resYesterday, resToday] = await Promise.all([
      this.fetchJson<Record<string, XtreamShortEpg>>(urlYesterday),
      this.fetchJson<Record<string, XtreamShortEpg>>(urlToday),
    ]);

    // Merge: combine epg_listings, deduplicate by start_timestamp
    const merged: Record<string, XtreamShortEpg> = {};
    const allKeys = new Set([...Object.keys(resYesterday), ...Object.keys(resToday)]);
    for (const key of allKeys) {
      const a = resYesterday[key]?.epg_listings || [];
      const b = resToday[key]?.epg_listings || [];
      const seen = new Set<string>();
      const combined: XtreamEpgListing[] = [];
      for (const listing of [...a, ...b]) {
        const ts = String(listing.start_timestamp);
        if (!seen.has(ts)) {
          seen.add(ts);
          combined.push(listing);
        }
      }
      merged[key] = { epg_listings: combined };
    }

    return merged;
  }

  // Viewers (m3u-editor specific)
  async getViewers(): Promise<PlaylistViewer[]> {
    const url = this.getApiUrl('get_viewers');
    return this.fetchJson<PlaylistViewer[]>(url);
  }

  async createViewer(name: string): Promise<PlaylistViewer> {
    const url = this.getApiUrl('create_viewer');
    return this.fetchPost<PlaylistViewer>(url, { name });
  }

  // Watch Progress (m3u-editor specific)
  async getProgress(
    viewerId: string,
    contentType: WatchContentType,
    streamId: number
  ): Promise<WatchProgress | null> {
    const url = this.getApiUrl('get_progress', {
      viewer_id: viewerId,
      content_type: contentType,
      stream_id: String(streamId),
    });
    return this.fetchJson<WatchProgress | null>(url);
  }

  async updateProgress(params: UpdateProgressParams): Promise<void> {
    const url = this.getApiUrl('update_progress');
    const body: Record<string, string> = {
      viewer_id: params.viewer_id,
      content_type: params.content_type,
      stream_id: String(params.stream_id),
    };
    if (params.position_seconds !== undefined) body.position_seconds = String(params.position_seconds);
    if (params.duration_seconds !== undefined) body.duration_seconds = String(params.duration_seconds);
    if (params.completed !== undefined) body.completed = params.completed ? '1' : '0';
    if (params.series_id !== undefined) body.series_id = String(params.series_id);
    if (params.season_number !== undefined) body.season_number = String(params.season_number);
    await this.fetchPost<unknown>(url, body);
  }

  async getSeriesProgress(viewerId: string, seriesId: number): Promise<WatchProgress[]> {
    const url = this.getApiUrl('get_series_progress', {
      viewer_id: viewerId,
      series_id: String(seriesId),
    });
    return this.fetchJson<WatchProgress[]>(url);
  }

  async getRecentlyWatched(
    viewerId: string,
    type?: WatchContentType,
    limit: number = 20
  ): Promise<WatchProgress[]> {
    const params: Record<string, string> = {
      viewer_id: viewerId,
      limit: String(limit),
    };
    if (type) params.type = type;
    const url = this.getApiUrl('get_recently_watched', params);
    return this.fetchJson<WatchProgress[]>(url);
  }

  // Helper methods to transform data for UI
  transformLiveStream(stream: XtreamLiveStream, categoryName?: string): ContentItem {
    return {
      id: stream.stream_id,
      type: 'live',
      name: stream.name,
      icon: stream.stream_icon,
      categoryId: stream.category_id,
      categoryName,
      epgChannelId: stream.epg_channel_id || undefined,
      streamUrl: this.getLiveStreamUrl(stream.stream_id),
    };
  }

  transformVodStream(stream: XtreamVodStream, categoryName?: string): ContentItem {
    return {
      id: stream.stream_id,
      type: 'vod',
      name: stream.name,
      icon: stream.stream_icon,
      categoryId: stream.category_id,
      categoryName,
      rating: stream.rating_5based,
      containerExtension: stream.container_extension,
      streamUrl: this.getVodStreamUrl(stream.stream_id, stream.container_extension),
    };
  }

  transformSeries(series: XtreamSeries, categoryName?: string): ContentItem {
    return {
      id: series.series_id,
      type: 'series',
      name: series.name,
      icon: series.cover,
      categoryId: series.category_id,
      categoryName,
      rating: series.rating_5based,
      year: series.release_date || series.releaseDate,
      plot: series.plot,
    };
  }
}

// Export singleton instance
export const xtreamService = new XtreamService();
export default xtreamService;
