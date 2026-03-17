import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  Image,
  LayoutChangeEvent,
  ActivityIndicator,
  ViewToken,
} from 'react-native';
import { XtreamLiveStream } from '../types/xtream';
import { epgService, EpgProgramme } from '../services/EpgService';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from './FocusablePressable';
import { Icon } from './Icon';

// ── Constants ────────────────────────────────────────────────────────────────

const VISIBLE_HOURS = 3;
const VISIBLE_SECONDS = VISIBLE_HOURS * 3600;
const CHANNEL_COL_WIDTH = scaledPixels(220);
const ROW_HEIGHT = scaledPixels(68);
const TIME_HEADER_HEIGHT = scaledPixels(48);
const PROGRAM_MARGIN = scaledPixels(1);

// ── Helpers ──────────────────────────────────────────────────────────────────

const formatTime = (timestamp: number): string => {
  const d = new Date(timestamp * 1000);
  return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
};

const getDefaultWindowStart = (): number => {
  const now = Math.floor(Date.now() / 1000);
  const halfHour = 30 * 60;
  return Math.floor((now - halfHour) / halfHour) * halfHour;
};

interface ProgramBlock {
  type: 'gap' | 'program';
  widthFraction: number;
  programme?: EpgProgramme;
  title?: string;
  isLive?: boolean;
}

const getVisiblePrograms = (
  programmes: EpgProgramme[],
  windowStart: number,
  windowEnd: number,
  now: number,
): ProgramBlock[] => {
  const windowDuration = windowEnd - windowStart;
  const result: ProgramBlock[] = [];

  const visible = programmes
    .filter((p) => p.stopTimestamp > windowStart && p.startTimestamp < windowEnd)
    .sort((a, b) => a.startTimestamp - b.startTimestamp);

  let currentTime = windowStart;

  for (const programme of visible) {
    const start = Math.max(programme.startTimestamp, windowStart);
    const end = Math.min(programme.stopTimestamp, windowEnd);

    if (start > currentTime) {
      result.push({ type: 'gap', widthFraction: (start - currentTime) / windowDuration });
    }

    const isLive = programme.startTimestamp <= now && programme.stopTimestamp > now;

    result.push({
      type: 'program',
      programme,
      widthFraction: (end - start) / windowDuration,
      title: programme.title,
      isLive,
    });

    currentTime = end;
  }

  if (currentTime < windowEnd) {
    result.push({ type: 'gap', widthFraction: (windowEnd - currentTime) / windowDuration });
  }

  return result;
};

// ── Props ────────────────────────────────────────────────────────────────────

interface EPGGridProps {
  streams: XtreamLiveStream[];
  onChannelSelect: (stream: XtreamLiveStream) => void;
  isSidebarActive: boolean;
  setSidebarActive: (active: boolean) => void;
}

// ── Component ────────────────────────────────────────────────────────────────

const INITIAL_LOAD_COUNT = 20;

export function EPGGrid({ streams, onChannelSelect, isSidebarActive, setSidebarActive }: EPGGridProps) {
  const [windowStart, setWindowStart] = useState(getDefaultWindowStart);
  const [gridWidth, setGridWidth] = useState(0);
  const [now, setNow] = useState(Math.floor(Date.now() / 1000));
  const [isLoadingEpg, setIsLoadingEpg] = useState(false);
  const loadedIdsRef = useRef<Set<number>>(new Set());
  const streamsRef = useRef(streams);
  streamsRef.current = streams;

  // Initialize epgData synchronously from EpgService cache
  const [epgData, setEpgData] = useState<Record<string, EpgProgramme[]>>(() => {
    const data: Record<string, EpgProgramme[]> = {};
    for (const stream of streams) {
      const key = String(stream.stream_id);
      const progs = epgService.getProgrammes(key);
      if (progs.length > 0) {
        data[key] = progs;
        loadedIdsRef.current.add(stream.stream_id);
      }
    }
    return data;
  });

  const windowEnd = windowStart + VISIBLE_SECONDS;

  // Update "now" every minute
  useEffect(() => {
    const timer = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 60000);
    return () => clearInterval(timer);
  }, []);

  // Measure available grid width
  const onLayout = useCallback((e: LayoutChangeEvent) => {
    const w = e.nativeEvent.layout.width - CHANNEL_COL_WIDTH;
    if (w > 0) setGridWidth(w);
  }, []);

  // Helper: load EPG for a set of stream IDs, merging results into state
  const loadEpgForIds = useCallback(async (ids: number[]) => {
    const newIds = ids.filter((id) => !loadedIdsRef.current.has(id));
    if (newIds.length === 0) return;

    newIds.forEach((id) => loadedIdsRef.current.add(id));

    const streamsToLoad = newIds.map((id) => ({
      streamId: id,
      channelId: String(id),
    }));

    try {
      await epgService.loadFullProgrammes(streamsToLoad);
    } catch (err) {
      console.warn('[EPGGrid] loadFullProgrammes failed:', err);
      return;
    }

    // Merge loaded data into state
    setEpgData((prev) => {
      const next = { ...prev };
      for (const id of newIds) {
        const key = String(id);
        next[key] = epgService.getProgrammes(key);
      }
      return next;
    });
  }, []);

  // Initial load: first batch of visible channels
  useEffect(() => {
    if (!streams.length) return;
    let cancelled = false;

    const load = async () => {
      setIsLoadingEpg(true);
      const initialIds = streams.slice(0, INITIAL_LOAD_COUNT).map((s) => s.stream_id);
      const toLoad = initialIds.filter((id) => !loadedIdsRef.current.has(id));

      if (toLoad.length > 0) {
        await loadEpgForIds(toLoad);
      }
      if (!cancelled) setIsLoadingEpg(false);
    };

    load();
    return () => { cancelled = true; };
  }, [streams, loadEpgForIds]);

  // Lazy-load EPG as the user scrolls to new channels
  const onViewableItemsChanged = useRef((
    { viewableItems }: { viewableItems: ViewToken[]; changed: ViewToken[] },
  ) => {
    const ids = viewableItems
      .map((v) => (v.item as XtreamLiveStream)?.stream_id)
      .filter((id): id is number => id != null && !loadedIdsRef.current.has(id));
    if (ids.length > 0) {
      // Load a bit beyond visible for smooth scrolling
      const allStreams = streamsRef.current;
      const lastVisibleIdx = viewableItems.reduce((max, v) => Math.max(max, v.index ?? 0), 0);
      const extraIds = allStreams
        .slice(lastVisibleIdx + 1, lastVisibleIdx + 11)
        .map((s) => s.stream_id)
        .filter((id) => !loadedIdsRef.current.has(id));
      epgService.loadFullProgrammes(
        [...ids, ...extraIds].map((id) => ({ streamId: id, channelId: String(id) })),
      ).then(() => {
        setEpgData((prev) => {
          const next = { ...prev };
          for (const id of [...ids, ...extraIds]) {
            const key = String(id);
            next[key] = epgService.getProgrammes(key);
          }
          return next;
        });
      }).catch(() => {});
    }
  }).current;

  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 10 }).current;

  // Time navigation
  const shiftWindow = useCallback((hours: number) => {
    setWindowStart((prev) => prev + hours * 3600);
  }, []);

  const goToNow = useCallback(() => {
    setWindowStart(getDefaultWindowStart());
    setNow(Math.floor(Date.now() / 1000));
  }, []);

  // Time slot labels
  const timeSlots = useMemo(() => {
    const slots: number[] = [];
    const interval = 30 * 60;
    let t = windowStart;
    while (t < windowEnd) {
      slots.push(t);
      t += interval;
    }
    return slots;
  }, [windowStart, windowEnd]);

  // Now indicator position
  const nowPosition = useMemo(() => {
    if (now < windowStart || now > windowEnd || gridWidth <= 0) return null;
    return CHANNEL_COL_WIDTH + ((now - windowStart) / VISIBLE_SECONDS) * gridWidth;
  }, [now, windowStart, windowEnd, gridWidth]);

  // Slot width for time labels
  const slotWidth = gridWidth > 0 ? gridWidth / (VISIBLE_HOURS * 2) : 0;

  // Render a channel row
  const renderRow = useCallback(
    ({ item, index }: { item: XtreamLiveStream; index: number }) => {
      const key = String(item.stream_id);
      const programmes = epgData[key] || [];
      const blocks = getVisiblePrograms(programmes, windowStart, windowEnd, now);
      const hasData = programmes.length > 0;

      return (
        <View style={styles.row}>
          {/* Channel label */}
          <FocusablePressable
            onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
            style={({ isFocused }) => [styles.channelCol, isFocused && styles.channelColFocused]}
            onSelect={() => onChannelSelect(item)}
          >
            {({ isFocused }) => (
              <View style={styles.channelColInner}>
                <Image
                  source={{ uri: item.stream_icon || undefined }}
                  style={styles.channelLogo}
                  resizeMode="contain"
                />
                <Text
                  style={[styles.channelName, isFocused && styles.channelNameFocused]}
                  numberOfLines={1}
                >
                  {item.name}
                </Text>
              </View>
            )}
          </FocusablePressable>

          {/* Program blocks */}
          <View style={styles.programRow}>
            {hasData && blocks.length > 0 ? (
              blocks.map((block, i) =>
                block.type === 'gap' ? (
                  <View
                    key={`gap-${i}`}
                    style={[styles.gapBlock, { width: block.widthFraction * gridWidth }]}
                  />
                ) : (
                  <FocusablePressable
                    key={`prog-${i}`}
                    style={({ isFocused }) => [
                      styles.programBlock,
                      block.isLive && styles.programBlockLive,
                      { width: Math.max(block.widthFraction * gridWidth - PROGRAM_MARGIN * 2, scaledPixels(4)) },
                      isFocused && styles.programBlockFocused,
                    ]}
                    onSelect={() => onChannelSelect(item)}
                  >
                    {({ isFocused }) => (
                      <View style={styles.programBlockInner}>
                        {block.isLive && <View style={styles.liveIndicator} />}
                        <Text
                          style={[styles.programTitle, isFocused && styles.programTitleFocused]}
                          numberOfLines={1}
                        >
                          {block.title}
                        </Text>
                      </View>
                    )}
                  </FocusablePressable>
                ),
              )
            ) : (
              <View style={[styles.noDataBlock, { width: gridWidth - PROGRAM_MARGIN * 2 }]}>
                <Text style={styles.noDataText}>No program info</Text>
              </View>
            )}
          </View>
        </View>
      );
    },
    [epgData, gridWidth, windowStart, windowEnd, now, isSidebarActive, setSidebarActive, onChannelSelect],
  );

  return (
    <View style={styles.container} onLayout={onLayout}>
      {/* Time navigation header */}
      <View style={styles.timeHeader}>
        {/* Channel column spacer */}
        <View style={styles.timeHeaderLeft}>
          <FocusablePressable
            style={({ isFocused }) => [styles.navButton, isFocused && styles.navButtonFocused]}
            onSelect={() => shiftWindow(-1)}
          >
            {() => <Icon name="ChevronLeft" size={scaledPixels(20)} color={colors.text} />}
          </FocusablePressable>
          <FocusablePressable
            style={({ isFocused }) => [styles.navButton, isFocused && styles.navButtonFocused]}
            onSelect={goToNow}
          >
            {({ isFocused }) => (
              <Text style={[styles.nowButtonText, isFocused && styles.nowButtonTextFocused]}>
                Now
              </Text>
            )}
          </FocusablePressable>
          <FocusablePressable
            style={({ isFocused }) => [styles.navButton, isFocused && styles.navButtonFocused]}
            onSelect={() => shiftWindow(1)}
          >
            {() => <Icon name="ChevronRight" size={scaledPixels(20)} color={colors.text} />}
          </FocusablePressable>
        </View>

        {/* Time labels */}
        <View style={styles.timeLabels}>
          {timeSlots.map((slot) => (
            <View key={slot} style={[styles.timeSlot, { width: slotWidth }]}>
              <Text style={styles.timeText}>{formatTime(slot)}</Text>
              <View style={styles.timeSlotDivider} />
            </View>
          ))}
        </View>
      </View>

      {/* Grid content */}
      {gridWidth > 0 ? (
        <FlatList
          data={streams}
          extraData={epgData}
          renderItem={renderRow}
          keyExtractor={(item) => String(item.stream_id)}
          showsVerticalScrollIndicator={false}
          removeClippedSubviews={false}
          initialNumToRender={14}
          maxToRenderPerBatch={10}
          windowSize={5}
          onViewableItemsChanged={onViewableItemsChanged}
          viewabilityConfig={viewabilityConfig}
          ListEmptyComponent={
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          }
        />
      ) : null}

      {/* Now indicator line */}
      {nowPosition !== null && gridWidth > 0 && (
        <View style={[styles.nowLine, { left: nowPosition }]} pointerEvents="none" />
      )}

      {/* Loading overlay */}
      {isLoadingEpg && (
        <View style={styles.loadingOverlay} pointerEvents="none">
          <ActivityIndicator size="small" color={colors.primary} />
        </View>
      )}
    </View>
  );
}

// ── Styles ───────────────────────────────────────────────────────────────────

const styles = StyleSheet.create({
  container: {
    flex: 1,
    position: 'relative',
  },

  // Time header
  timeHeader: {
    flexDirection: 'row',
    height: TIME_HEADER_HEIGHT,
    backgroundColor: colors.backgroundElevated,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  timeHeaderLeft: {
    width: CHANNEL_COL_WIDTH,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: scaledPixels(4),
    paddingHorizontal: scaledPixels(8),
  },
  navButton: {
    paddingHorizontal: scaledPixels(10),
    paddingVertical: scaledPixels(6),
    borderRadius: scaledPixels(8),
    backgroundColor: colors.card,
    borderWidth: 2,
    borderColor: 'transparent',
    alignItems: 'center',
    justifyContent: 'center',
  },
  navButtonFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.primary,
    transform: [{ scale: 1.1 }],
  },
  nowButtonText: {
    color: colors.text,
    fontSize: scaledPixels(14),
    fontWeight: '600',
  },
  nowButtonTextFocused: {
    color: '#ffffff',
  },
  timeLabels: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'flex-end',
  },
  timeSlot: {
    justifyContent: 'flex-end',
    paddingBottom: scaledPixels(4),
    paddingLeft: scaledPixels(6),
    position: 'relative',
  },
  timeSlotDivider: {
    position: 'absolute',
    left: 0,
    top: scaledPixels(8),
    bottom: 0,
    width: 1,
    backgroundColor: colors.border,
    opacity: 0.5,
  },
  timeText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(13),
    fontWeight: '500',
  },

  // Channel rows
  row: {
    flexDirection: 'row',
    height: ROW_HEIGHT,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  channelCol: {
    width: CHANNEL_COL_WIDTH,
    justifyContent: 'center',
    paddingHorizontal: scaledPixels(8),
    backgroundColor: colors.backgroundElevated,
    borderRightWidth: 1,
    borderRightColor: colors.border,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  channelColFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.cardElevated,
    zIndex: 10,
  },
  channelColInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(8),
  },
  channelLogo: {
    width: scaledPixels(36),
    height: scaledPixels(36),
    borderRadius: scaledPixels(6),
    backgroundColor: colors.card,
  },
  channelName: {
    flex: 1,
    color: colors.text,
    fontSize: scaledPixels(14),
    fontWeight: '500',
  },
  channelNameFocused: {
    color: '#ffffff',
  },

  // Program blocks
  programRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'stretch',
  },
  gapBlock: {
    backgroundColor: 'transparent',
    marginHorizontal: PROGRAM_MARGIN,
  },
  programBlock: {
    justifyContent: 'center',
    paddingHorizontal: scaledPixels(8),
    marginHorizontal: PROGRAM_MARGIN,
    backgroundColor: colors.card,
    borderWidth: 2,
    borderColor: 'transparent',
    borderRadius: scaledPixels(4),
    overflow: 'hidden',
  },
  programBlockLive: {
    backgroundColor: 'rgba(236, 0, 63, 0.1)',
  },
  programBlockFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.cardElevated,
    zIndex: 10,
    transform: [{ scaleY: 1.1 }],
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.4,
    shadowRadius: 8,
    elevation: 6,
  },
  programBlockInner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(6),
  },
  liveIndicator: {
    width: scaledPixels(6),
    height: scaledPixels(6),
    borderRadius: scaledPixels(3),
    backgroundColor: colors.primary,
  },
  programTitle: {
    flex: 1,
    color: colors.textSecondary,
    fontSize: scaledPixels(13),
  },
  programTitleFocused: {
    color: '#ffffff',
    fontWeight: '600',
  },
  noDataBlock: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    marginHorizontal: PROGRAM_MARGIN,
  },
  noDataText: {
    color: colors.textTertiary,
    fontSize: scaledPixels(12),
    fontStyle: 'italic',
  },

  // Now indicator
  nowLine: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: scaledPixels(2),
    backgroundColor: colors.primary,
    opacity: 0.8,
    zIndex: 20,
  },

  // Loading
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: scaledPixels(60),
  },
  loadingOverlay: {
    position: 'absolute',
    top: scaledPixels(8),
    right: scaledPixels(8),
  },
});
