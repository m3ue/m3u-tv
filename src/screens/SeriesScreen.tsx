import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, FlatList, Platform, useWindowDimensions } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamCategory, XtreamSeries } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { CategoryScroller } from '../components/CategoryScroller';
import { SeriesCard } from '../components/SeriesCard';
import { useResponsiveColumns } from '../hooks/useResponsiveColumns';

import { SIDEBAR_WIDTH_COLLAPSED } from '../components/SideBar';

const CARD_CELL_WIDTH = scaledPixels(200) + scaledPixels(12) * 2;

export function SeriesScreen(_props: DrawerScreenPropsType<'Series'>) {
  const { isSidebarActive, setSidebarActive } = useMenu();
  const { isConfigured, seriesCategories, fetchSeries } = useXtream();
  const [seriesList, setSeriesList] = useState<XtreamSeries[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);
  const { width: windowWidth } = useWindowDimensions();
  const responsiveColumns = useResponsiveColumns();
  const numColumns = useMemo(() => {
    if (Platform.OS !== 'web') return responsiveColumns;
    const available = windowWidth - SIDEBAR_WIDTH_COLLAPSED - scaledPixels(40);
    return Math.max(2, Math.floor(available / CARD_CELL_WIDTH));
  }, [windowWidth, responsiveColumns]);

  useEffect(() => {
    if (isConfigured) {
      loadSeries();
    }
  }, [isConfigured, selectedCategory]);

  const loadSeries = async () => {
    setIsLoading(true);
    const result = await fetchSeries(selectedCategory);
    setSeriesList(result);
    setIsLoading(false);
  };

  const renderCategoryItem = useCallback(({ item, index }: { item: XtreamCategory; index: number }) => (
    <FocusablePressable
      onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
      style={({ isFocused }) => [
        styles.categoryButton,
        (selectedCategory ?? undefined) === (item.category_id || undefined) && styles.categoryButtonActive,
        isFocused && styles.categoryButtonFocused,
      ]}
      onSelect={() => setSelectedCategory(item.category_id || undefined)}
    >
      {({ isFocused }) => (
        <Text
          style={[
            styles.categoryText,
            (selectedCategory ?? undefined) === (item.category_id || undefined) && styles.categoryTextActive,
            isFocused && styles.categoryTextFocused,
          ]}
          numberOfLines={1}
        >
          {item.category_name}
        </Text>
      )}
    </FocusablePressable>
  ), [selectedCategory, isSidebarActive, setSidebarActive]);

  const renderSeriesItem = useCallback(({ item, index }: { item: XtreamSeries; index: number }) => (
    <SeriesCard
      item={item}
      onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
    />
  ), [isSidebarActive, setSidebarActive]);

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Series grid */}
      <View style={styles.gridContent}>
        {isLoading && seriesList.length > 0 && (
          <View style={styles.loadingOverlay}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        )}
        <FlatList
          key={`grid-${numColumns}`}
          data={seriesList}
          renderItem={renderSeriesItem}
          numColumns={numColumns}
          columnWrapperStyle={styles.columnWrapper}
          style={styles.seriesGrid}
          keyExtractor={(item) => String(item.series_id)}
          showsVerticalScrollIndicator={false}
          removeClippedSubviews
          initialNumToRender={24}
          maxToRenderPerBatch={16}
          windowSize={5}
          ListEmptyComponent={
            isLoading ? (
              <View style={styles.loadingContainer}>
                <ActivityIndicator size="large" color={colors.primary} />
              </View>
            ) : null
          }
          ListHeaderComponent={<View style={styles.categoryListContainer}>
            <CategoryScroller>
              {[{ category_id: '', category_name: 'All Series', parent_id: 0 }, ...seriesCategories].map((item, index) => (
                <React.Fragment key={item.category_id ? `cat-${item.category_id}` : `idx-${index}`}>
                  {renderCategoryItem({ item, index })}
                </React.Fragment>
              ))}
            </CategoryScroller>
          </View>}
        />
      </View>
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
  categoryListContainer: {
    paddingVertical: scaledPixels(10),
    paddingHorizontal: scaledPixels(10),
    marginHorizontal: scaledPixels(25),
    marginTop: scaledPixels(25),
    height: scaledPixels(80),
    borderRadius: scaledPixels(50),
    backgroundColor: colors.scrimDark,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    zIndex: 5,
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
  gridContent: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: scaledPixels(60),
  },
  loadingOverlay: {
    position: 'absolute',
    top: scaledPixels(100),
    left: 0,
    right: 0,
    bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(10, 10, 15, 0.7)',
    zIndex: 10,
  },
  seriesGrid: {
    padding: scaledPixels(20),
  },
  columnWrapper: {
    justifyContent: 'center',
  },
});
