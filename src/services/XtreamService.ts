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
  ContentItem,
} from '../types/xtream';

class XtreamService {
  private credentials: XtreamCredentials | null = null;

  setCredentials(credentials: XtreamCredentials) {
    // Ensure server URL doesn't have trailing slash
    this.credentials = {
      ...credentials,
      server: credentials.server.replace(/\/+$/, ''),
    };
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

  private async fetchJson<T>(url: string): Promise<T> {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
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

  getLiveStreamUrl(streamId: number, format: string = 'ts'): string {
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
