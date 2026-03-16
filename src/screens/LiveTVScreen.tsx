import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  FlatList,
  ScrollView,
  Image,
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { RootStackParamList } from '../navigation/types';
import { XtreamCategory, XtreamLiveStream, XtreamEpgListing } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';

// ── Helpers ──────────────────────────────────────────────────────────────────

interface EpgInfo {
  currentTitle: string;
  currentProgress: number;
  nextTitle: string | null;
}

const decodeBase64 = (str: string): string => {
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
};

const findCurrentAndNext = (listings: XtreamEpgListing[]): EpgInfo | null => {
  if (!listings?.length) return null;

  const now = Date.now() / 1000;
  const sorted = [...listings]
    .filter((l) => l?.start_timestamp && l?.stop_timestamp)
    .sort((a, b) => Number(a.start_timestamp) - Number(b.start_timestamp));

  let currentIdx = -1;
  for (let i = 0; i < sorted.length; i++) {
    const start = Number(sorted[i].start_timestamp);
    const stop = Number(sorted[i].stop_timestamp);
    if (start <= now && stop > now) {
      currentIdx = i;
      break;
    }
  }

  if (currentIdx === -1) return null;

  const current = sorted[currentIdx];
  const start = Number(current.start_timestamp);
  const stop = Number(current.stop_timestamp);
  const duration = stop - start;
  const elapsed = now - start;
  const progress = duration > 0 ? Math.min(elapsed / duration, 1) : 0;

  const next = currentIdx + 1 < sorted.length ? sorted[currentIdx + 1] : null;

  return {
    currentTitle: decodeBase64(String(current.title || 'Unknown')),
    currentProgress: progress,
    nextTitle: next ? decodeBase64(String(next.title || '')) : null,
  };
};

// ── EPG batch fetch size ─────────────────────────────────────────────────────
const EPG_BATCH_SIZE = 20;

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
  const fetchedEpgIds = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (isConfigured) {
      loadStreams();
    }
  }, [isConfigured, selectedCategory]);

  const loadStreams = async () => {
    setIsLoading(true);
    const streams = await fetchLiveStreams(selectedCategory);
    setLiveStreams(streams);
    setIsLoading(false);
  };

  const fetchEpgForStreams = useCallback(async (streamIds: number[]) => {
    const toFetch = streamIds.filter((id) => !fetchedEpgIds.current.has(String(id)));
    if (!toFetch.length) return;

    toFetch.forEach((id) => fetchedEpgIds.current.add(String(id)));

    try {
      const now = new Date();
      const pad = (n: number) => n.toString().padStart(2, '0');
      const dateStr = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
      const result = await xtreamService.getEpgBatch(toFetch, dateStr);

      setEpgMap((prev) => {
        const next = { ...prev };
        for (const sid of toFetch) {
          const data = result[String(sid)];
          next[String(sid)] = data?.epg_listings
            ? findCurrentAndNext(data.epg_listings)
            : null;
        }
        return next;
      });
    } catch (err) {
      console.warn('[LiveTVScreen] EPG batch fetch failed:', err);
    }
  }, []);

  const onViewableItemsChanged = useRef(({ viewableItems }: { viewableItems: Array<{ item: XtreamLiveStream }> }) => {
    const ids = viewableItems
      .map((v) => v.item.stream_id)
      .filter((id) => !fetchedEpgIds.current.has(String(id)));
    if (ids.length > 0) {
      fetchEpgForStreams(ids.slice(0, EPG_BATCH_SIZE));
    }
  }).current;

  const viewabilityConfig = useRef({ itemVisiblePercentThreshold: 30 }).current;

  const handleChannelSelect = useCallback(
    (item: XtreamLiveStream) => {
      const streamUrl = getLiveStreamUrl(item.stream_id);
      navigation.navigate('Player', {
        streamUrl,
        title: item.name,
        type: 'live',
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
        fetchedEpgIds.current.clear();
        setEpgMap({});
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
      <FlatList
        data={liveStreams}
        renderItem={renderStreamItem}
        keyExtractor={(item) => String(item.stream_id)}
        showsVerticalScrollIndicator={false}
        removeClippedSubviews
        initialNumToRender={12}
        maxToRenderPerBatch={8}
        windowSize={5}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={viewabilityConfig}
        ListEmptyComponent={
          isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          ) : null
        }
        ListHeaderComponent={
          <View style={styles.categoryListContainer}>
            <ScrollView
              horizontal
              showsHorizontalScrollIndicator={false}
              style={styles.categoryList}
              contentContainerStyle={styles.categoryListContent}
            >
              {[{ category_id: '', category_name: 'All Channels', parent_id: 0 }, ...liveCategories].map(
                (item, index) => (
                  <React.Fragment key={item.category_id || 'all'}>
                    {renderCategoryItem({ item, index })}
                  </React.Fragment>
                ),
              )}
            </ScrollView>
          </View>
        }
      />
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
  categoryListContainer: {
    paddingVertical: scaledPixels(10),
    paddingHorizontal: scaledPixels(10),
    marginHorizontal: scaledPixels(40),
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
