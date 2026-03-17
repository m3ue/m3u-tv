import { xtreamService } from './XtreamService';
import AsyncStorage from '@react-native-async-storage/async-storage';

// ── Types ────────────────────────────────────────────────────────────────────

export interface EpgProgramme {
  title: string;
  description: string;
  startTimestamp: number;
  stopTimestamp: number;
}

export interface EpgCurrentNext {
  currentTitle: string;
  currentDescription: string;
  currentProgress: number;
  nextTitle: string | null;
}

// ── Constants ────────────────────────────────────────────────────────────────

const EPG_CACHE_KEY = 'm3ue_epg_v7';
const CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes
const BATCH_SIZE = 50; // Max streams per batch request (server allows 100)

// ── Helpers ──────────────────────────────────────────────────────────────────

function decodeBase64(str: string): string {
  try {
    const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    const s = str.replace(/[^A-Za-z0-9+/=]/g, '');
    for (let i = 0; i < s.length; ) {
      const e1 = chars.indexOf(s.charAt(i++));
      const e2 = chars.indexOf(s.charAt(i++));
      const e3 = chars.indexOf(s.charAt(i++));
      const e4 = chars.indexOf(s.charAt(i++));
      output += String.fromCharCode((e1 << 2) | (e2 >> 4));
      if (e3 !== 64) output += String.fromCharCode(((e2 & 15) << 4) | (e3 >> 2));
      if (e4 !== 64) output += String.fromCharCode(((e3 & 3) << 6) | e4);
    }
    return decodeURIComponent(escape(output));
  } catch {
    return str;
  }
}

// ── Service ──────────────────────────────────────────────────────────────────

/**
 * EPG service using Xtream API exclusively.
 *
 * Strategy (like TiviMate / IPTV Smarters):
 * - Uses `get_short_epg` for current+next per channel (list view)
 * - Uses `get_epg_batch` for batch loading (up to 100 channels at once)
 * - Uses `get_simple_data_table` / `get_epg_batch` for full grid data
 * - In-memory map keyed by stream_id with 30-min TTL
 * - AsyncStorage cache for instant restore on next launch
 * - No XMLTV download — all data via lightweight JSON API
 */
class EpgService {
  /** Map<streamId, programmes> — keyed by stream_id (number as string) */
  private data: Map<string, EpgProgramme[]> = new Map();
  /** Tracks when each stream_id was last fetched */
  private fetchTimes: Map<string, number> = new Map();
  /** Pending batch promises to deduplicate concurrent requests */
  private pendingBatches: Map<string, Promise<void>> = new Map();
  private cacheRestored = false;

  // ── Public API ──────────────────────────────────────────────────────────

  /**
   * Ensure EPG is ready. Restores cache on first call.
   * Unlike the old approach, this does NOT download anything upfront.
   */
  async ensureLoaded(): Promise<void> {
    if (!this.cacheRestored) {
      await this._restoreFromCache();
      this.cacheRestored = true;
    }
  }

  /** Check if we have any EPG data loaded */
  isLoaded(): boolean {
    return this.data.size > 0;
  }

  /**
   * Get current + next programme for a channel (async).
   * Fetches from API if not cached. Used by PlayerScreen.
   */
  async getCurrentAndNextAsync(
    _channelId: string,
    streamId?: number,
  ): Promise<EpgCurrentNext | null> {
    if (!streamId) return null;

    const key = String(streamId);

    // Try in-memory cache first
    if (this._isFresh(key)) {
      return this._lookupCurrentNext(key);
    }

    // Fetch from API
    try {
      const data = await xtreamService.getShortEpg(streamId, 4);
      this._storeListings(key, data?.epg_listings, true);
      return this._lookupCurrentNext(key);
    } catch {
      return null;
    }
  }

  /**
   * Synchronous lookup from in-memory data.
   * Used by LiveTVScreen list view for already-loaded streams.
   */
  getCurrentAndNext(streamId: string): EpgCurrentNext | null {
    return this._lookupCurrentNext(streamId);
  }

  /**
   * Batch-load current+next EPG for a list of stream IDs.
   * Uses the server's native get_epg_batch endpoint (up to 100 IDs per request).
   * Used by LiveTVScreen to load EPG for all visible channels efficiently.
   */
  async loadBatch(streamIds: number[]): Promise<void> {
    // Filter to streams that need refreshing
    const toFetch = streamIds.filter((id) => !this._isFresh(String(id)));
    if (toFetch.length === 0) return;

    // Process in chunks of BATCH_SIZE
    for (let i = 0; i < toFetch.length; i += BATCH_SIZE) {
      const chunk = toFetch.slice(i, i + BATCH_SIZE);

      // Deduplicate: if this exact batch is already being fetched, wait for it
      const batchKey = chunk.join(',');
      const existing = this.pendingBatches.get(batchKey);
      if (existing) {
        await existing;
        continue;
      }

      const promise = this._fetchBatch(chunk);
      this.pendingBatches.set(batchKey, promise);
      try {
        await promise;
      } finally {
        this.pendingBatches.delete(batchKey);
      }
    }
  }

  /**
   * Load full programme data for EPG grid.
   * Uses get_epg_batch with today's date for full-day schedule.
   */
  async loadFullProgrammes(
    streams: Array<{ streamId: number; channelId: string }>,
  ): Promise<void> {
    const toFetch = streams.filter(
      (s) => !this.data.has(String(s.streamId)) || !this._isFresh(String(s.streamId)),
    );
    if (toFetch.length === 0) return;

    const ids = toFetch.map((s) => s.streamId);

    for (let i = 0; i < ids.length; i += BATCH_SIZE) {
      const chunk = ids.slice(i, i + BATCH_SIZE);
      try {
        const result = await xtreamService.getFullEpgBatch(chunk);
        for (const id of chunk) {
          const epgData = result[String(id)];
          this._storeListings(String(id), epgData?.epg_listings, false);
        }
      } catch (err) {
        console.warn('[EpgService] Full EPG batch failed:', err);
      }
    }

    this._saveToCache();
  }

  /** Get all programmes for a stream (used by EPG grid) */
  getProgrammes(streamId: string): EpgProgramme[] {
    return this.data.get(streamId) || [];
  }

  /** Clear all cached data */
  clear(): void {
    this.data.clear();
    this.fetchTimes.clear();
    this.cacheRestored = false;
    AsyncStorage.removeItem(EPG_CACHE_KEY).catch(() => {});
  }

  // ── Private ─────────────────────────────────────────────────────────────

  private _isFresh(key: string): boolean {
    const t = this.fetchTimes.get(key);
    return !!t && Date.now() - t < CACHE_TTL_MS;
  }

  private _lookupCurrentNext(key: string): EpgCurrentNext | null {
    const programmes = this.data.get(key);
    if (!programmes?.length) return null;

    const now = Date.now() / 1000;
    let currentIdx = -1;
    for (let i = 0; i < programmes.length; i++) {
      if (programmes[i].startTimestamp <= now && programmes[i].stopTimestamp > now) {
        currentIdx = i;
        break;
      }
    }
    if (currentIdx === -1) {
      return null;
    }

    const current = programmes[currentIdx];
    const duration = current.stopTimestamp - current.startTimestamp;
    const elapsed = now - current.startTimestamp;
    const progress = duration > 0 ? Math.min(elapsed / duration, 1) : 0;
    const next = currentIdx + 1 < programmes.length ? programmes[currentIdx + 1] : null;

    return {
      currentTitle: current.title,
      currentDescription: current.description,
      currentProgress: progress,
      nextTitle: next ? next.title : null,
    };
  }

  /**
   * Store EPG listings into the in-memory map.
   * get_short_epg returns plain text on m3u-editor;
   * get_simple_data_table / get_epg_batch returns base64.
   */
  private _storeListings(
    key: string,
    listings: Array<Record<string, any>> | undefined,
    isPlainText: boolean,
  ): void {
    if (!listings?.length) {
      this.fetchTimes.set(key, Date.now());
      return;
    }

    const isM3UE = xtreamService.getIsM3UEditor();
    const decode = (s: string): string => {
      if (isPlainText && isM3UE) return s;
      return decodeBase64(s);
    };

    const programmes: EpgProgramme[] = listings
      .filter((l) => l?.start_timestamp && l?.stop_timestamp)
      .map((l) => ({
        title: decode(String(l.title || '')),
        description: decode(String(l.description || '')),
        startTimestamp: Number(l.start_timestamp),
        stopTimestamp: Number(l.stop_timestamp),
      }))
      .sort((a, b) => a.startTimestamp - b.startTimestamp);

    this.data.set(key, programmes);
    this.fetchTimes.set(key, Date.now());
  }

  private async _fetchBatch(streamIds: number[]): Promise<void> {
    try {
      const result = await xtreamService.getEpgBatch(streamIds);

      for (const id of streamIds) {
        const epgData = result[String(id)];
        this._storeListings(String(id), epgData?.epg_listings, false);
      }

      this._saveToCache();
    } catch (err) {
      console.warn('[EpgService] Batch EPG fetch failed:', err);
      // Mark all as fetched (with empty data) to prevent retry storms
      for (const id of streamIds) {
        this.fetchTimes.set(String(id), Date.now());
      }
    }
  }

  /** Save to AsyncStorage — compact format, only title + timestamps */
  private _saveToCache(): void {
    try {
      const obj: Record<string, Array<{ t: string; s: number; e: number }>> = {};
      for (const [key, value] of this.data) {
        if (value.length > 0) {
          obj[key] = value.map((p) => ({ t: p.title, s: p.startTimestamp, e: p.stopTimestamp }));
        }
      }
      const payload = JSON.stringify({ ts: Date.now(), d: obj });
      AsyncStorage.setItem(EPG_CACHE_KEY, payload).catch(() => {});
    } catch {
      // ignore
    }
  }

  /** Restore from AsyncStorage cache */
  private async _restoreFromCache(): Promise<void> {
    try {
      // Clean up old cache keys from previous versions
      AsyncStorage.removeItem('m3ue_epg_cache').catch(() => {});
      AsyncStorage.removeItem('m3ue_epg_v3').catch(() => {});
      AsyncStorage.removeItem('m3ue_epg_v4').catch(() => {});
      AsyncStorage.removeItem('m3ue_epg_v5').catch(() => {});
      AsyncStorage.removeItem('m3ue_epg_v6').catch(() => {});

      const raw = await AsyncStorage.getItem(EPG_CACHE_KEY);
      if (!raw) return;

      const parsed = JSON.parse(raw) as {
        ts: number;
        d: Record<string, Array<{ t: string; s: number; e: number }>>;
      };

      // Only use cache if less than 1 hour old
      if (Date.now() - parsed.ts > 3600 * 1000) return;

      let count = 0;
      for (const [key, value] of Object.entries(parsed.d)) {
        this.data.set(
          key,
          value.map((p) => ({
            title: p.t,
            description: '',
            startTimestamp: p.s,
            stopTimestamp: p.e,
          })),
        );
        this.fetchTimes.set(key, parsed.ts);
        count++;
      }
    } catch {
      // Corrupted cache, ignore
    }
  }
}

export const epgService = new EpgService();
