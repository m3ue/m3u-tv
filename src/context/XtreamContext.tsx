import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { xtreamService } from '../services/XtreamService';
import { cacheService } from '../services/CacheService';
import {
  XtreamCredentials,
  XtreamAuthResponse,
  XtreamCategory,
  XtreamLiveStream,
  XtreamVodStream,
  XtreamSeries,
  XtreamVodInfo,
  XtreamSeriesInfo,
} from '../types/xtream';
import * as SecureStore from 'expo-secure-store';

const STORAGE_KEY = 'm3ue_tv_credentials';

interface XtreamState {
  isConfigured: boolean;
  isLoading: boolean;
  error: string | null;
  authResponse: XtreamAuthResponse | null;
  isM3UEditor: boolean;
  m3uEditorVersion: string | null;
  liveCategories: XtreamCategory[];
  vodCategories: XtreamCategory[];
  seriesCategories: XtreamCategory[];
  liveStreams: XtreamLiveStream[];
  vodStreams: XtreamVodStream[];
  series: XtreamSeries[];
}

interface XtreamContextValue extends XtreamState {
  connect: (credentials: XtreamCredentials) => Promise<boolean>;
  disconnect: () => Promise<void>;
  loadSavedCredentials: () => Promise<boolean>;
  refreshCategories: () => Promise<void>;
  fetchLiveStreams: (categoryId?: string, forceRefresh?: boolean) => Promise<XtreamLiveStream[]>;
  fetchVodStreams: (categoryId?: string, forceRefresh?: boolean) => Promise<XtreamVodStream[]>;
  fetchSeries: (categoryId?: string, forceRefresh?: boolean) => Promise<XtreamSeries[]>;
  fetchVodInfo: (vodId: number) => Promise<XtreamVodInfo>;
  fetchSeriesInfo: (seriesId: number) => Promise<XtreamSeriesInfo>;
  getLiveStreamUrl: (streamId: number, format?: string) => string;
  getVodStreamUrl: (streamId: number, extension?: string) => string;
  getSeriesStreamUrl: (episodeId: string, extension?: string) => string;
  clearError: () => void;
}

const XtreamContext = createContext<XtreamContextValue | null>(null);

export function XtreamProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<XtreamState>({
    isConfigured: false,
    isLoading: false,
    error: null,
    authResponse: null,
    isM3UEditor: false,
    m3uEditorVersion: null,
    liveCategories: [],
    vodCategories: [],
    seriesCategories: [],
    liveStreams: [],
    vodStreams: [],
    series: [],
  });

  useEffect(() => {
    cacheService.loadSettings();
  }, []);

  const setLoading = useCallback((isLoading: boolean) => {
    setState((prev) => ({ ...prev, isLoading }));
  }, []);

  const setError = useCallback((error: string | null) => {
    setState((prev) => ({ ...prev, error, isLoading: false }));
  }, []);

  const clearError = useCallback(() => {
    setState((prev) => ({ ...prev, error: null }));
  }, []);

  const connect = useCallback(
    async (credentials: XtreamCredentials): Promise<boolean> => {
      try {
        setLoading(true);
        xtreamService.setCredentials(credentials);
        // Always send the m3u-editor client header for the initial auth request
        // so the server knows to include m3u_editor info in the response
        xtreamService.setM3UEditor(true);

        const authResponse = await xtreamService.authenticate();

        // Handle error responses (e.g. {"error":"Unauthorized"})
        if ('error' in authResponse) {
          setError(`Server error: ${(authResponse as Record<string, unknown>).error}`);
          return false;
        }

        if (!authResponse.user_info || authResponse.user_info.auth !== 1) {
          setError('Authentication failed. Please check your credentials.');
          return false;
        }

        // Check if the server advertises m3u-editor features (requires experimental v0.10.x+)
        const isM3UEditor = !!authResponse.m3u_editor;
        const m3uEditorVersion = authResponse.m3u_editor?.version ?? null;

        if (!isM3UEditor) {
          setError('This app requires an m3u-editor backend (v0.10.x or later).');
          xtreamService.setM3UEditor(false);
          xtreamService.clearCredentials();
          return false;
        }

        xtreamService.setM3UEditor(true);

        // Save credentials
        await SecureStore.setItemAsync(STORAGE_KEY, JSON.stringify(credentials));

        // Fetch initial categories
        const [liveCategories, vodCategories, seriesCategories] = await Promise.all([
          xtreamService.getLiveCategories(),
          xtreamService.getVodCategories(),
          xtreamService.getSeriesCategories(),
        ]);

        // Cache categories for instant load on next app start
        cacheService.set('categories', { liveCategories, vodCategories, seriesCategories });

        setState((prev) => ({
          ...prev,
          isConfigured: true,
          isLoading: false,
          error: null,
          authResponse,
          isM3UEditor,
          m3uEditorVersion,
          liveCategories,
          vodCategories,
          seriesCategories,
        }));

        return true;
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Failed to connect';
        setError(message);
        return false;
      }
    },
    [setLoading, setError],
  );

  const disconnect = useCallback(async () => {
    await SecureStore.deleteItemAsync(STORAGE_KEY);
    await cacheService.clear();
    xtreamService.setM3UEditor(false);
    setState({
      isConfigured: false,
      isLoading: false,
      error: null,
      authResponse: null,
      isM3UEditor: false,
      m3uEditorVersion: null,
      liveCategories: [],
      vodCategories: [],
      seriesCategories: [],
      liveStreams: [],
      vodStreams: [],
      series: [],
    });
  }, []);

  const loadSavedCredentials = useCallback(async (): Promise<boolean> => {
    try {
      const saved = await SecureStore.getItemAsync(STORAGE_KEY);
      if (!saved) return false;

      const credentials: XtreamCredentials = JSON.parse(saved);

      // Try to load cached categories immediately for instant UI
      const cached = await cacheService.get<{
        liveCategories: XtreamCategory[];
        vodCategories: XtreamCategory[];
        seriesCategories: XtreamCategory[];
      }>('categories');

      if (cached) {
        xtreamService.setCredentials(credentials);
        xtreamService.setM3UEditor(true);
        setState((prev) => ({
          ...prev,
          isConfigured: true,
          isLoading: false,
          liveCategories: cached.data.liveCategories,
          vodCategories: cached.data.vodCategories,
          seriesCategories: cached.data.seriesCategories,
        }));

        // Silently authenticate in background to refresh auth state and categories if stale
        xtreamService.authenticate()
          .then((authResponse) => {
            if (!authResponse.user_info || authResponse.user_info.auth !== 1) {
              return;
            }
            const isM3UEditor = !!authResponse.m3u_editor;
            const m3uEditorVersion = authResponse.m3u_editor?.version ?? null;
            setState((prev) => ({ ...prev, authResponse, isM3UEditor, m3uEditorVersion }));

            if (cached.isStale) {
              Promise.all([
                xtreamService.getLiveCategories(),
                xtreamService.getVodCategories(),
                xtreamService.getSeriesCategories(),
              ]).then(([liveCategories, vodCategories, seriesCategories]) => {
                cacheService.set('categories', { liveCategories, vodCategories, seriesCategories });
                setState((prev) => ({ ...prev, liveCategories, vodCategories, seriesCategories }));
              }).catch((e) => console.warn('[XtreamContext] Background category refresh failed:', e));
            }
          })
          .catch((e) => console.warn('[XtreamContext] Background auth failed:', e));

        return true;
      }

      // No cache — full connect
      return await connect(credentials);
    } catch {
      return false;
    }
  }, [connect]);

  const refreshCategories = useCallback(async () => {
    if (!xtreamService.isConfigured()) return;

    try {
      setLoading(true);
      const [liveCategories, vodCategories, seriesCategories] = await Promise.all([
        xtreamService.getLiveCategories(),
        xtreamService.getVodCategories(),
        xtreamService.getSeriesCategories(),
      ]);

      cacheService.set('categories', { liveCategories, vodCategories, seriesCategories });

      setState((prev) => ({
        ...prev,
        isLoading: false,
        liveCategories,
        vodCategories,
        seriesCategories,
      }));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to refresh';
      setError(message);
    }
  }, [setLoading, setError]);

  const fetchLiveStreams = useCallback(async (categoryId?: string, forceRefresh?: boolean): Promise<XtreamLiveStream[]> => {
    const cacheKey = categoryId ? `liveStreams_${categoryId}` as const : 'liveStreams' as const;

    try {
      if (!forceRefresh) {
        const cached = await cacheService.get<XtreamLiveStream[]>(cacheKey);
        if (cached && !cached.isStale) {
          setState((prev) => ({ ...prev, liveStreams: cached.data }));
          return cached.data;
        }

        if (cached) {
          setState((prev) => ({ ...prev, liveStreams: cached.data }));
          xtreamService.getLiveStreams(categoryId).then((streams) => {
            cacheService.set(cacheKey, streams);
            setState((prev) => ({ ...prev, liveStreams: streams }));
          }).catch((e) => console.warn('[XtreamContext] Background live streams refresh failed:', e));
          return cached.data;
        }
      }

      const streams = await xtreamService.getLiveStreams(categoryId);
      cacheService.set(cacheKey, streams);
      setState((prev) => ({ ...prev, liveStreams: streams }));
      return streams;
    } catch (error) {
      console.error('Failed to fetch live streams:', error);
      const cached = await cacheService.get<XtreamLiveStream[]>(cacheKey);
      if (cached) {
        setState((prev) => ({ ...prev, liveStreams: cached.data }));
        return cached.data;
      }
      return [];
    }
  }, []);

  const fetchVodStreams = useCallback(async (categoryId?: string, forceRefresh?: boolean): Promise<XtreamVodStream[]> => {
    const cacheKey = categoryId ? `vodStreams_${categoryId}` as const : 'vodStreams' as const;

    try {
      if (!forceRefresh) {
        const cached = await cacheService.get<XtreamVodStream[]>(cacheKey);
        if (cached && !cached.isStale) {
          setState((prev) => ({ ...prev, vodStreams: cached.data }));
          return cached.data;
        }

        if (cached) {
          setState((prev) => ({ ...prev, vodStreams: cached.data }));
          xtreamService.getVodStreams(categoryId).then((streams) => {
            cacheService.set(cacheKey, streams);
            setState((prev) => ({ ...prev, vodStreams: streams }));
          }).catch((e) => console.warn('[XtreamContext] Background VOD streams refresh failed:', e));
          return cached.data;
        }
      }

      const streams = await xtreamService.getVodStreams(categoryId);
      cacheService.set(cacheKey, streams);
      setState((prev) => ({ ...prev, vodStreams: streams }));
      return streams;
    } catch (error) {
      console.error('Failed to fetch VOD streams:', error);
      const cached = await cacheService.get<XtreamVodStream[]>(cacheKey);
      if (cached) {
        setState((prev) => ({ ...prev, vodStreams: cached.data }));
        return cached.data;
      }
      return [];
    }
  }, []);

  const fetchSeries = useCallback(async (categoryId?: string, forceRefresh?: boolean): Promise<XtreamSeries[]> => {
    const cacheKey = categoryId ? `series_${categoryId}` as const : 'series' as const;

    try {
      if (!forceRefresh) {
        const cached = await cacheService.get<XtreamSeries[]>(cacheKey);
        if (cached && !cached.isStale) {
          setState((prev) => ({ ...prev, series: cached.data }));
          return cached.data;
        }

        if (cached) {
          setState((prev) => ({ ...prev, series: cached.data }));
          xtreamService.getSeries(categoryId).then((seriesList) => {
            cacheService.set(cacheKey, seriesList);
            setState((prev) => ({ ...prev, series: seriesList }));
          }).catch((e) => console.warn('[XtreamContext] Background series refresh failed:', e));
          return cached.data;
        }
      }

      const seriesList = await xtreamService.getSeries(categoryId);
      cacheService.set(cacheKey, seriesList);
      setState((prev) => ({ ...prev, series: seriesList }));
      return seriesList;
    } catch (error) {
      console.error('Failed to fetch series:', error);
      const cached = await cacheService.get<XtreamSeries[]>(cacheKey);
      if (cached) {
        setState((prev) => ({ ...prev, series: cached.data }));
        return cached.data;
      }
      return [];
    }
  }, []);

  const fetchVodInfo = useCallback(async (vodId: number) => {
    const cacheKey = `vodInfo_${vodId}` as const;

    try {
      const cached = await cacheService.get<XtreamVodInfo>(cacheKey);
      if (cached && !cached.isStale) {
        return cached.data;
      }

      const info = await xtreamService.getVodInfo(vodId);
      cacheService.set(cacheKey, info);
      return info;
    } catch (error) {
      const cached = await cacheService.get<XtreamVodInfo>(cacheKey);
      if (cached) {
        return cached.data;
      }
      throw error;
    }
  }, []);

  const fetchSeriesInfo = useCallback(async (seriesId: number) => {
    const cacheKey = `seriesInfo_${seriesId}` as const;

    try {
      const cached = await cacheService.get<XtreamSeriesInfo>(cacheKey);
      if (cached && !cached.isStale) {
        return cached.data;
      }

      const info = await xtreamService.getSeriesInfo(seriesId);
      cacheService.set(cacheKey, info);
      return info;
    } catch (error) {
      const cached = await cacheService.get<XtreamSeriesInfo>(cacheKey);
      if (cached) {
        return cached.data;
      }
      throw error;
    }
  }, []);

  const getLiveStreamUrl = useCallback((streamId: number, format?: string) => {
    return xtreamService.getLiveStreamUrl(streamId, format);
  }, []);

  const getVodStreamUrl = useCallback((streamId: number, extension?: string) => {
    return xtreamService.getVodStreamUrl(streamId, extension);
  }, []);

  const getSeriesStreamUrl = useCallback((episodeId: string, extension?: string) => {
    return xtreamService.getSeriesStreamUrl(episodeId, extension);
  }, []);

  const value: XtreamContextValue = {
    ...state,
    connect,
    disconnect,
    loadSavedCredentials,
    refreshCategories,
    fetchLiveStreams,
    fetchVodStreams,
    fetchSeries,
    fetchVodInfo,
    fetchSeriesInfo,
    getLiveStreamUrl,
    getVodStreamUrl,
    getSeriesStreamUrl,
    clearError,
  };

  return <XtreamContext.Provider value={value}>{children}</XtreamContext.Provider>;
}

export function useXtream(): XtreamContextValue {
  const context = useContext(XtreamContext);
  if (!context) {
    throw new Error('useXtream must be used within an XtreamProvider');
  }
  return context;
}
