import React, { useState, useCallback, useRef, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TextInput,
  ActivityIndicator,
} from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamVodStream, XtreamSeries } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { LiveTVCard } from '../components/LiveTVCard';
import { MovieCard } from '../components/MovieCard';
import { SeriesCard } from '../components/SeriesCard';
import { Icon } from '../components/Icon';
import { useResponsiveColumns } from '../hooks/useResponsiveColumns';

type ContentType = 'all' | 'live' | 'vod' | 'series';

interface FilterTab {
  id: ContentType;
  label: string;
}

const FILTER_TABS: FilterTab[] = [
  { id: 'all', label: 'All' },
  { id: 'live', label: 'Live TV' },
  { id: 'vod', label: 'Movies' },
  { id: 'series', label: 'Series' },
];

type SearchResult =
  | { type: 'live'; item: XtreamLiveStream }
  | { type: 'vod'; item: XtreamVodStream }
  | { type: 'series'; item: XtreamSeries };

export function SearchScreen(_props: DrawerScreenPropsType<'Search'>) {
  const { isSidebarActive, setSidebarActive } = useMenu();
  const numColumns = useResponsiveColumns();
  const {
    isConfigured,
    fetchLiveStreams,
    fetchVodStreams,
    fetchSeries,
  } = useXtream();

  const [query, setQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<ContentType>('all');
  const [isLoading, setIsLoading] = useState(false);
  const [results, setResults] = useState<SearchResult[]>([]);
  const [hasSearched, setHasSearched] = useState(false);

  const inputRef = useRef<TextInput>(null);
  const searchButtonRef = useRef<FocusablePressableRef>(null);
  const [searchButtonTag, setSearchButtonTag] = useState<number>();

  useEffect(() => {
    const id = setTimeout(() => {
      const tag = searchButtonRef.current?.getNodeHandle();
      if (typeof tag === 'number') setSearchButtonTag(tag);
    }, 0);
    return () => clearTimeout(id);
  }, []);

  const performSearch = useCallback(async () => {
    const trimmed = query.trim();
    if (!trimmed) return;

    setIsLoading(true);
    setHasSearched(true);

    const lowerQuery = trimmed.toLowerCase();
    const combined: SearchResult[] = [];

    try {
      const shouldSearchLive = activeFilter === 'all' || activeFilter === 'live';
      const shouldSearchVod = activeFilter === 'all' || activeFilter === 'vod';
      const shouldSearchSeries = activeFilter === 'all' || activeFilter === 'series';

      const [liveStreams, vodStreams, seriesList] = await Promise.all([
        shouldSearchLive ? fetchLiveStreams() : Promise.resolve([]),
        shouldSearchVod ? fetchVodStreams() : Promise.resolve([]),
        shouldSearchSeries ? fetchSeries() : Promise.resolve([]),
      ]);

      if (shouldSearchLive) {
        for (const item of liveStreams) {
          if (item.name.toLowerCase().includes(lowerQuery)) {
            combined.push({ type: 'live', item });
          }
        }
      }

      if (shouldSearchVod) {
        for (const item of vodStreams) {
          if (item.name.toLowerCase().includes(lowerQuery)) {
            combined.push({ type: 'vod', item });
          }
        }
      }

      if (shouldSearchSeries) {
        for (const item of seriesList) {
          if (item.name.toLowerCase().includes(lowerQuery)) {
            combined.push({ type: 'series', item });
          }
        }
      }
    } catch (error) {
      console.error('Search failed:', error);
    }

    setResults(combined);
    setIsLoading(false);
  }, [query, activeFilter, fetchLiveStreams, fetchVodStreams, fetchSeries]);

  const renderResult = ({ item, index }: { item: SearchResult; index: number }) => {
    const dismissSidebar = index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined;

    switch (item.type) {
      case 'live':
        return <LiveTVCard item={item.item} onFocus={dismissSidebar} />;
      case 'vod':
        return <MovieCard item={item.item} onFocus={dismissSidebar} />;
      case 'series':
        return <SeriesCard item={item.item} onFocus={dismissSidebar} />;
    }
  };

  const getResultKey = (item: SearchResult): string => {
    switch (item.type) {
      case 'live':
        return `live-${item.item.stream_id}`;
      case 'vod':
        return `vod-${item.item.stream_id}`;
      case 'series':
        return `series-${item.item.series_id}`;
    }
  };

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={results}
        renderItem={renderResult}
        keyExtractor={getResultKey}
        numColumns={numColumns}
        key={`search-${numColumns}`}
        style={styles.resultGrid}
        showsVerticalScrollIndicator={false}
        removeClippedSubviews
        initialNumToRender={24}
        maxToRenderPerBatch={16}
        windowSize={5}
        ListHeaderComponent={
          <View>
            {/* Search input row */}
            <View style={styles.searchRow}>
              <View style={styles.inputContainer}>
                <Icon name="Search" size={scaledPixels(28)} color={colors.textSecondary} />
                <TextInput
                  ref={inputRef}
                  style={styles.textInput}
                  placeholder="Search channels, movies, series..."
                  placeholderTextColor={colors.textTertiary}
                  value={query}
                  onChangeText={setQuery}
                  onSubmitEditing={performSearch}
                  returnKeyType="search"
                  autoCorrect={false}
                  autoCapitalize="none"
                />
              </View>
              <FocusablePressable
                ref={searchButtonRef}
                style={({ isFocused }) => [
                  styles.searchButton,
                  isFocused && styles.searchButtonFocused,
                ]}
                onSelect={performSearch}
                onFocus={() => isSidebarActive && setSidebarActive(false)}
              >
                {({ isFocused }) => (
                  <Text style={[styles.searchButtonText, isFocused && styles.searchButtonTextFocused]}>
                    Search
                  </Text>
                )}
              </FocusablePressable>
            </View>

            {/* Filter tabs */}
            <View style={styles.filterRow}>
              {FILTER_TABS.map((tab) => (
                <FocusablePressable
                  key={tab.id}
                  nextFocusUp={searchButtonTag}
                  style={({ isFocused }) => [
                    styles.filterTab,
                    activeFilter === tab.id && styles.filterTabActive,
                    isFocused && styles.filterTabFocused,
                  ]}
                  onSelect={() => {
                    setActiveFilter(tab.id);
                    if (hasSearched) {
                      // Re-search with new filter after state update
                      setTimeout(performSearch, 0);
                    }
                  }}
                >
                  {({ isFocused }) => (
                    <Text
                      style={[
                        styles.filterTabText,
                        activeFilter === tab.id && styles.filterTabTextActive,
                        isFocused && styles.filterTabTextFocused,
                      ]}
                    >
                      {tab.label}
                    </Text>
                  )}
                </FocusablePressable>
              ))}

              {hasSearched && !isLoading && (
                <Text style={styles.resultCount}>
                  {results.length} {results.length === 1 ? 'result' : 'results'}
                </Text>
              )}
            </View>
          </View>
        }
        ListEmptyComponent={
          isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          ) : hasSearched ? (
            <View style={styles.emptyContainer}>
              <Icon name="SearchX" size={scaledPixels(64)} color={colors.textSecondary} />
              <Text style={styles.emptyText}>No results found</Text>
              <Text style={styles.emptySubtext}>Try different keywords or filters</Text>
            </View>
          ) : (
            <View style={styles.emptyContainer}>
              <Icon name="Search" size={scaledPixels(64)} color={colors.textSecondary} />
              <Text style={styles.emptyText}>Search your content</Text>
              <Text style={styles.emptySubtext}>
                Find channels, movies, and series
              </Text>
            </View>
          )
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  message: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
  },
  searchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: scaledPixels(30),
    paddingTop: scaledPixels(30),
    paddingBottom: scaledPixels(15),
    gap: scaledPixels(15),
  },
  inputContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    paddingHorizontal: scaledPixels(20),
    height: scaledPixels(65),
    borderWidth: 2,
    borderColor: colors.border,
    gap: scaledPixels(12),
  },
  textInput: {
    flex: 1,
    color: colors.text,
    fontSize: scaledPixels(22),
    padding: 0,
  },
  searchButton: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    paddingHorizontal: scaledPixels(35),
    height: scaledPixels(65),
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: colors.border,
  },
  searchButtonFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    transform: [{ scale: 1.05 }],
  },
  searchButtonText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(22),
    fontWeight: '600',
  },
  searchButtonTextFocused: {
    color: colors.text,
  },
  filterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: scaledPixels(30),
    paddingBottom: scaledPixels(15),
    gap: scaledPixels(10),
  },
  filterTab: {
    paddingHorizontal: scaledPixels(25),
    paddingVertical: scaledPixels(10),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(25),
    borderWidth: 2,
    borderColor: 'transparent',
  },
  filterTabActive: {
    backgroundColor: 'rgba(236, 0, 63, 0.2)',
    borderColor: colors.primary,
  },
  filterTabFocused: {
    backgroundColor: colors.primary,
    transform: [{ scale: 1.1 }],
  },
  filterTabText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
  },
  filterTabTextActive: {
    color: colors.text,
    fontWeight: 'bold',
  },
  filterTabTextFocused: {
    color: colors.text,
    fontWeight: 'bold',
  },
  resultCount: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
    marginLeft: 'auto',
  },
  resultGrid: {
    padding: scaledPixels(20),
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: scaledPixels(100),
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingTop: scaledPixels(100),
    gap: scaledPixels(15),
  },
  emptyText: {
    color: colors.text,
    fontSize: scaledPixels(28),
    fontWeight: '600',
  },
  emptySubtext: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
  },
});
