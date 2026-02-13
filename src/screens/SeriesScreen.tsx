import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, FlatList } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamCategory, XtreamSeries } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { SeriesCard } from '../components/SeriesCard';

export function SeriesScreen(_props: DrawerScreenPropsType<'Series'>) {
  const isFocused = useIsFocused();
  const { sidebarFocusTag, isSidebarActive, setSidebarActive } = useMenu();
  const { isConfigured, seriesCategories, series, fetchSeries } = useXtream();
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (isConfigured) {
      loadSeries();
    }
  }, [isConfigured, selectedCategory]);

  const loadSeries = async () => {
    setIsLoading(true);
    await fetchSeries(selectedCategory);
    setIsLoading(false);
  };

  const renderCategoryItem = ({ item, index }: { item: XtreamCategory; index: number }) => (
    <FocusablePressable
      nextFocusLeft={index === 0 ? sidebarFocusTag : undefined}
      onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
      style={({ isFocused }) => [
        styles.categoryButton,
        selectedCategory === item.category_id && styles.categoryButtonActive,
        isFocused && styles.categoryButtonFocused,
      ]}
      onSelect={() => setSelectedCategory(item.category_id)}
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

  const renderSeriesItem = ({ item, index }: { item: XtreamSeries; index: number }) => (
    <SeriesCard
      item={item}
      nextFocusLeft={index === 0 ? sidebarFocusTag : undefined}
      onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
    />
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
      {/* Category selector */}
      <View style={styles.categoryListContainer}>
        <FlatList
          data={[{ category_id: '', category_name: 'All Series', parent_id: 0 }, ...seriesCategories]}
          renderItem={renderCategoryItem}
          style={styles.categoryList}
          horizontal
          keyExtractor={(item) => String(item.category_id || 'all')}
          showsHorizontalScrollIndicator={false}
        />
      </View>

      {/* Series grid */}
      <View style={styles.gridContent}>
        {isLoading ? (
          <View style={styles.loadingContainer}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        ) : (
          <FlatList
            data={series}
            renderItem={renderSeriesItem}
            numColumns={8}
            style={styles.seriesGrid}
            keyExtractor={(item) => String(item.series_id)}
            showsVerticalScrollIndicator={false}
          />
        )}
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
  categoryList: {
    flex: 1,
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
    overflow: 'hidden',
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
  },
  seriesGrid: {
    padding: scaledPixels(20),
  },
});
