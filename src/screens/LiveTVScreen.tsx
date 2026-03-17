import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  FlatList,
  ScrollView,
  Image,
  ViewToken,
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useXtream } from '../context/XtreamContext';
import { cacheService, EpgViewMode } from '../services/CacheService';
import { epgService } from '../services/EpgService';
import { EPGGrid } from '../components/EPGGrid';
import { Icon } from '../components/Icon';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { RootStackParamList } from '../navigation/types';
import { XtreamCategory, XtreamLiveStream } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';

// ── Helpers ──────────────────────────────────────────────────────────────────

interface EpgInfo {
  currentTitle: string;
  currentProgress: number;
  nextTitle: string | null;
}

// ── Main Screen ──────────────────────────────────────────────────────────────

export function LiveTVScreen(_props: DrawerScreenPropsType<'LiveTV'>) {
  const isFocused = useIsFocused();
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { isSidebarActive, setSidebarActive } = useMenu();
  const { isConfigured, liveCategories, fetchLiveStreams, getLiveStreamUrl } = useXtream();
  const [liveStreams, setLiveStreams] = useState<XtreamLiveStream[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);
  const [epgMap, setEpgMap] = useState<Record<string, EpgInfo | null>>({});
  const [epgLoaded, setEpgLoaded] = useState(false);
  const [viewMode, setViewMode] = useState<EpgViewMode>('list');
  const loadedEpgIdsRef = useRef<Set<number>>(new Set());
  const liveStreamsRef = useRef(liveStreams);
  liveStreamsRef.current = liveStreams;

  // Load persisted view mode
  useEffect(() => {
    cacheService.loadSettings().then((s) => setViewMode(s.epgViewMode));
  }, []);

  // Helper: load EPG for a set of stream IDs and merge into epgMap
  const loadEpgForIds = useCallback(async (ids: number[]) => {
    const newIds = ids.filter((id) => !loadedEpgIdsRef.current.has(id));
    if (newIds.length === 0) return;

    newIds.forEach((id) => loadedEpgIdsRef.current.add(id));
    await epgService.loadBatch(newIds);

    setEpgMap((prev) => {
      const next = { ...prev };
      for (const id of newIds) {
        const data = epgService.getCurrentAndNext(String(id));
        if (data) {
          next[String(id)] = {
            currentTitle: data.currentTitle,
            currentProgress: data.currentProgress,
            nextTitle: data.nextTitle,
          };
        }
      }
      return next;
    });
  }, []);

  // Load initial batch of EPG data when streams change
  useEffect(() => {
    if (!liveStreams.length) return;
    let cancelled = false;

    // Populate from EpgService cache synchronously first
    const cached: Record<string, EpgInfo | null> = {};
    let cachedCount = 0;
    for (const stream of liveStreams.slice(0, 20)) {
      const data = epgService.getCurrentAndNext(String(stream.stream_id));
      if (data) {
        cached[String(stream.stream_id)] = {
          currentTitle: data.currentTitle,
          currentProgress: data.currentProgress,
          nextTitle: data.nextTitle,
        };
        cachedCount++;
        loadedEpgIdsRef.current.add(stream.stream_id);
      }
    }
    if (cachedCount > 0) {
      setEpgMap(cached);
    }

    const loadInitial = async () => {
      const initialIds = liveStreams.slice(0, 20).map((s) => s.stream_id);
      await loadEpgForIds(initialIds);
      if (!cancelled) setEpgLoaded(true);
    };

    loadInitial();
    return () => { cancelled = true; };
  }, [liveStreams, loadEpgForIds]);

  // Lazy-load EPG as user scrolls through the list
  const onListViewableItemsChanged = useRef((
    { viewableItems }: { viewableItems: ViewToken[]; changed: ViewToken[] },
  ) => {
    const ids = viewableItems
      .map((v) => (v.item as XtreamLiveStream)?.stream_id)
      .filter((id): id is number => id != null && !loadedEpgIdsRef.current.has(id));
    if (ids.length > 0) {
      const allStreams = liveStreamsRef.current;
      const lastIdx = viewableItems.reduce((max, v) => Math.max(max, v.index ?? 0), 0);
      const extraIds = allStreams
        .slice(lastIdx + 1, lastIdx + 11)
        .map((s) => s.stream_id)
        .filter((id) => !loadedEpgIdsRef.current.has(id));
      const allIds = [...ids, ...extraIds];
      allIds.forEach((id) => loadedEpgIdsRef.current.add(id));
      epgService.loadBatch(allIds).then(() => {
        setEpgMap((prev) => {
          const next = { ...prev };
          for (const id of allIds) {
            const data = epgService.getCurrentAndNext(String(id));
            if (data) {
              next[String(id)] = {
                currentTitle: data.currentTitle,
                currentProgress: data.currentProgress,
                nextTitle: data.nextTitle,
              };
            }
          }
          return next;
        });
      }).catch(() => {});
    }
  }).current;

  const listViewabilityConfig = useRef({ itemVisiblePercentThreshold: 10 }).current;

  // Refresh EPG progress every 30 seconds (sync lookup from cache)
  useEffect(() => {
    if (!epgLoaded || !liveStreams.length) return;
    const interval = setInterval(() => {
      setEpgMap((prev) => {
        const next: Record<string, EpgInfo | null> = {};
        for (const key of Object.keys(prev)) {
          const data = epgService.getCurrentAndNext(key);
          if (data) {
            next[key] = {
              currentTitle: data.currentTitle,
              currentProgress: data.currentProgress,
              nextTitle: data.nextTitle,
            };
          }
        }
        return next;
      });
    }, 30000);
    return () => clearInterval(interval);
  }, [epgLoaded, liveStreams]);

  // Load streams for the selected category
  const loadStreams = useCallback(
    async (categoryId?: string) => {
      setIsLoading(true);
      try {
        const streams = await fetchLiveStreams(categoryId);
        setLiveStreams(streams);
      } finally {
        setIsLoading(false);
      }
    },
    [fetchLiveStreams],
  );

  // Fetch live streams when screen becomes focused or category changes
  useEffect(() => {
    if (!isConfigured || !isFocused) return;
    loadStreams(selectedCategory);
  }, [isConfigured, isFocused, selectedCategory, loadStreams]);

  const toggleViewMode = useCallback(async () => {
    const next = viewMode === 'list' ? 'grid' : 'list';
    setViewMode(next);
    const current = cacheService.getSettings();
    await cacheService.saveSettings({ ...current, epgViewMode: next });
  }, [viewMode]);

  const handleChannelSelect = useCallback(
    (item: XtreamLiveStream) => {
      const streamUrl = getLiveStreamUrl(item.stream_id);
      navigation.navigate('Player', {
        streamUrl,
        title: item.name,
        type: 'live',
        streamId: item.stream_id,
        epgChannelId: item.epg_channel_id || undefined,
      });
    },
    [getLiveStreamUrl, navigation],
  );

  const renderCategoryItem = ({ item, index }: { item: XtreamCategory; index: number }) => (
    <FocusablePressable
      onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
      style={({ isFocused }) => [
        styles.categoryButton,
        selectedCategory === item.category_id && styles.categoryButtonActive,
        isFocused && styles.categoryButtonFocused,
      ]}
      onSelect={() => {
        setSelectedCategory(item.category_id || undefined);
      }}
    >
      {({ isFocused }) => (
        <Text
          style={[
            styles.categoryText,
            selectedCategory === item.category_id && styles.categoryTextActive,
            isFocused && styles.categoryTextFocused,
          ]}
          numberOfLines={1}
        >
          {item.category_name}
        </Text>
      )}
    </FocusablePressable>
  );

  const renderStreamItem = useCallback(
    ({ item, index }: { item: XtreamLiveStream; index: number }) => {
      const epg = epgMap[String(item.stream_id)];
      return (
        <FocusablePressable
          onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
          style={({ isFocused }) => [
            styles.channelRow,
            isFocused && styles.channelRowFocused,
          ]}
          onSelect={() => handleChannelSelect(item)}
        >
          {({ isFocused: focused }) => (
            <View style={styles.channelRowInner}>
              <Image
                source={{ uri: item.stream_icon || undefined }}
                style={styles.channelLogo}
                resizeMode="contain"
              />
              <View style={styles.channelInfo}>
                <Text
                  style={[styles.channelName, focused && styles.channelNameFocused]}
                  numberOfLines={1}
                >
                  {item.name}
                </Text>
                {epg ? (
                  <View style={styles.epgInfo}>
                    <View style={styles.nowRow}>
                      <Text
                        style={[styles.nowLabel, focused && styles.nowLabelFocused]}
                        numberOfLines={1}
                      >
                        {epg.currentTitle}
                      </Text>
                    </View>
                    <View style={styles.progressBarBg}>
                      <View
                        style={[
                          styles.progressBarFill,
                          { width: `${Math.round(epg.currentProgress * 100)}%` },
                          focused && styles.progressBarFillFocused,
                        ]}
                      />
                    </View>
                  </View>
                ) : (
                  <Text style={styles.noEpg}>No program info</Text>
                )}
              </View>
              {epg?.nextTitle ? (
                <View style={styles.nextInfo}>
                  <Text style={styles.nextLabel}>Next</Text>
                  <Text
                    style={[styles.nextTitle, focused && styles.nextTitleFocused]}
                    numberOfLines={1}
                  >
                    {epg.nextTitle}
                  </Text>
                </View>
              ) : null}
            </View>
          )}
        </FocusablePressable>
      );
    },
    [epgMap, handleChannelSelect, isSidebarActive, setSidebarActive],
  );

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  if (!isFocused) return null;

  return (
    <View style={styles.container}>
      {/* Category bar + view mode toggle */}
      <View style={styles.categoryBar}>
        <FocusablePressable
          style={({ isFocused }) => [
            styles.viewModeButton,
            isFocused && styles.viewModeButtonFocused,
          ]}
          onSelect={toggleViewMode}
        >
          {({ isFocused }) => (
            <Icon
              name={viewMode === 'list' ? 'LayoutGrid' : 'List'}
              size={scaledPixels(22)}
              color={isFocused ? '#ffffff' : colors.textSecondary}
            />
          )}
        </FocusablePressable>
        <View style={styles.categoryListContainer}>
          <ScrollView
            horizontal
            showsHorizontalScrollIndicator={false}
            style={styles.categoryList}
            contentContainerStyle={styles.categoryListContent}
          >
            {[{ category_id: '', category_name: 'All Channels', parent_id: 0 }, ...liveCategories].map(
              (item, index) => (
                <React.Fragment key={item.category_id ? `cat-${item.category_id}` : `idx-${index}`}>
                  {renderCategoryItem({ item, index })}
                </React.Fragment>
              ),
            )}
          </ScrollView>
        </View>
      </View>

      {/* Content: list or grid */}
      {viewMode === 'list' ? (
        <FlatList
          data={liveStreams}
          extraData={epgMap}
          renderItem={renderStreamItem}
          keyExtractor={(item) => String(item.stream_id)}
          showsVerticalScrollIndicator={false}
          removeClippedSubviews
          initialNumToRender={12}
          maxToRenderPerBatch={8}
          windowSize={5}
          onViewableItemsChanged={onListViewableItemsChanged}
          viewabilityConfig={listViewabilityConfig}
          ListEmptyComponent={
            isLoading ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={colors.primary} />
              </View>
            ) : null
          }
        />
      ) : (
        <EPGGrid
          streams={liveStreams}
          onChannelSelect={handleChannelSelect}
          isSidebarActive={isSidebarActive}
          setSidebarActive={setSidebarActive}
        />
      )}
    </View>
  );
}

const ROW_HEIGHT = scaledPixels(90);

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  message: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: scaledPixels(60),
  },
  categoryBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingLeft: scaledPixels(20),
    gap: scaledPixels(10),
  },
  viewModeButton: {
    width: scaledPixels(52),
    height: scaledPixels(52),
    borderRadius: scaledPixels(26),
    backgroundColor: colors.card,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  viewModeButtonFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.primary,
    transform: [{ scale: 1.1 }],
  },
  categoryListContainer: {
    flex: 1,
    paddingVertical: scaledPixels(10),
    paddingHorizontal: scaledPixels(10),
    marginRight: scaledPixels(40),
    marginTop: scaledPixels(25),
    marginBottom: scaledPixels(12),
    height: scaledPixels(80),
    borderRadius: scaledPixels(50),
    backgroundColor: colors.scrimDark,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    zIndex: 5,
  },
  categoryList: {
    flex: 1,
    borderRadius: scaledPixels(50),
  },
  categoryListContent: {
    paddingHorizontal: scaledPixels(20),
    alignItems: 'center',
    justifyContent: 'center',
  },
  categoryButton: {
    paddingHorizontal: scaledPixels(25),
    paddingVertical: scaledPixels(10),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(25),
    marginHorizontal: scaledPixels(8),
    marginVertical: scaledPixels(4),
    width: scaledPixels(180),
    alignItems: 'center',
    overflow: 'visible',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  categoryButtonActive: {
    backgroundColor: 'rgba(236, 0, 63, 0.2)',
    borderColor: colors.primary,
  },
  categoryButtonFocused: {
    backgroundColor: colors.primary,
    transform: [{ scale: 1.1 }],
  },
  categoryText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
  },
  categoryTextActive: {
    color: colors.text,
    fontWeight: 'bold',
  },
  categoryTextFocused: {
    color: colors.text,
    fontWeight: 'bold',
  },

  // Channel row
  channelRow: {
    height: ROW_HEIGHT,
    marginHorizontal: scaledPixels(20),
    marginVertical: scaledPixels(4),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    borderWidth: 2,
    borderColor: 'transparent',
    overflow: 'hidden',
  },
  channelRowFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.cardElevated,
    transform: [{ scale: 1.02 }],
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.4,
    shadowRadius: 12,
    elevation: 8,
  },
  channelRowInner: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: scaledPixels(16),
    gap: scaledPixels(14),
  },
  channelLogo: {
    width: scaledPixels(52),
    height: scaledPixels(52),
    borderRadius: scaledPixels(8),
    backgroundColor: colors.backgroundElevated,
  },
  channelInfo: {
    flex: 1,
    justifyContent: 'center',
    gap: scaledPixels(4),
  },
  channelName: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '600',
  },
  channelNameFocused: {
    color: '#ffffff',
  },

  // EPG info
  epgInfo: {
    gap: scaledPixels(4),
  },
  nowRow: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  nowLabel: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
    flex: 1,
  },
  nowLabelFocused: {
    color: 'rgba(255,255,255,0.85)',
  },
  progressBarBg: {
    height: scaledPixels(3),
    borderRadius: scaledPixels(2),
    backgroundColor: colors.border,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    borderRadius: scaledPixels(2),
    backgroundColor: colors.primary,
    opacity: 0.7,
  },
  progressBarFillFocused: {
    opacity: 1,
  },
  noEpg: {
    color: colors.textTertiary,
    fontSize: scaledPixels(13),
    fontStyle: 'italic',
  },

  // Next program
  nextInfo: {
    width: scaledPixels(200),
    alignItems: 'flex-end',
    justifyContent: 'center',
    gap: scaledPixels(2),
  },
  nextLabel: {
    color: colors.textTertiary,
    fontSize: scaledPixels(11),
    textTransform: 'uppercase',
    fontWeight: '600',
    letterSpacing: 0.5,
  },
  nextTitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(13),
    textAlign: 'right',
  },
  nextTitleFocused: {
    color: 'rgba(255,255,255,0.7)',
  },
});
