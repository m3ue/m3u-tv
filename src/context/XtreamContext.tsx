import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { xtreamService } from '../services/XtreamService';
import {
  XtreamCredentials,
  XtreamAuthResponse,
  XtreamCategory,
  XtreamLiveStream,
  XtreamVodStream,
  XtreamSeries,
} from '../types/xtream';

const STORAGE_KEY = '@planby_tv_credentials';

interface XtreamState {
  isConfigured: boolean;
  isLoading: boolean;
  error: string | null;
  authResponse: XtreamAuthResponse | null;
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
  fetchLiveStreams: (categoryId?: string) => Promise<XtreamLiveStream[]>;
  fetchVodStreams: (categoryId?: string) => Promise<XtreamVodStream[]>;
  fetchSeries: (categoryId?: string) => Promise<XtreamSeries[]>;
  clearError: () => void;
}

const XtreamContext = createContext<XtreamContextValue | null>(null);

export function XtreamProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<XtreamState>({
    isConfigured: false,
    isLoading: false,
    error: null,
    authResponse: null,
    liveCategories: [],
    vodCategories: [],
    seriesCategories: [],
    liveStreams: [],
    vodStreams: [],
    series: [],
  });

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

        const authResponse = await xtreamService.authenticate();

        if (authResponse.user_info.auth !== 1) {
          setError('Authentication failed. Please check your credentials.');
          return false;
        }

        // Save credentials
        await AsyncStorage.setItem(STORAGE_KEY, JSON.stringify(credentials));

        // Fetch initial categories
        const [liveCategories, vodCategories, seriesCategories] = await Promise.all([
          xtreamService.getLiveCategories(),
          xtreamService.getVodCategories(),
          xtreamService.getSeriesCategories(),
        ]);

        setState((prev) => ({
          ...prev,
          isConfigured: true,
          isLoading: false,
          error: null,
          authResponse,
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
    await AsyncStorage.removeItem(STORAGE_KEY);
    setState({
      isConfigured: false,
      isLoading: false,
      error: null,
      authResponse: null,
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
      const saved = await AsyncStorage.getItem(STORAGE_KEY);
      if (saved) {
        const credentials: XtreamCredentials = JSON.parse(saved);
        return await connect(credentials);
      }
      return false;
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

  const fetchLiveStreams = useCallback(async (categoryId?: string): Promise<XtreamLiveStream[]> => {
    try {
      const streams = await xtreamService.getLiveStreams(categoryId);
      setState((prev) => ({ ...prev, liveStreams: streams }));
      return streams;
    } catch (error) {
      console.error('Failed to fetch live streams:', error);
      return [];
    }
  }, []);

  const fetchVodStreams = useCallback(async (categoryId?: string): Promise<XtreamVodStream[]> => {
    try {
      const streams = await xtreamService.getVodStreams(categoryId);
      setState((prev) => ({ ...prev, vodStreams: streams }));
      return streams;
    } catch (error) {
      console.error('Failed to fetch VOD streams:', error);
      return [];
    }
  }, []);

  const fetchSeries = useCallback(async (categoryId?: string): Promise<XtreamSeries[]> => {
    try {
      const seriesList = await xtreamService.getSeries(categoryId);
      setState((prev) => ({ ...prev, series: seriesList }));
      return seriesList;
    } catch (error) {
      console.error('Failed to fetch series:', error);
      return [];
    }
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
