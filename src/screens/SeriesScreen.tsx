import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  Image,
  ActivityIndicator,
} from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamCategory, XtreamSeries } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { SpatialNavigationNode, SpatialNavigationVirtualizedGrid } from 'react-tv-space-navigation';

// Card dimensions for consistent sizing (same as VOD)
const CARD_WIDTH = scaledPixels(200);
const CARD_MARGIN = scaledPixels(12);

export function SeriesScreen({ navigation }: DrawerScreenPropsType<'Series'>) {
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

  const renderCategoryItem = ({ item }: { item: XtreamCategory }) => (
    <FocusablePressable
      style={({ isFocused }) => [
        styles.categoryButton,
        selectedCategory === item.category_id && styles.categoryButtonActive,
        isFocused && styles.categoryButtonFocused,
      ]}
      onSelect={() => setSelectedCategory(item.category_id)}
    >
      <Text
        style={[
          styles.categoryText,
          selectedCategory === item.category_id && styles.categoryTextActive,
        ]}
        numberOfLines={1}
      >
        {item.category_name}
      </Text>
    </FocusablePressable>
  );

  const renderSeriesItem = ({ item }: { item: XtreamSeries }) => (
    <FocusablePressable
      style={({ isFocused }) => [
        styles.seriesCard,
        isFocused && styles.seriesCardFocused,
      ]}
      onSelect={() => {
        // @ts-ignore
        navigation.navigate('SeriesDetails', { item });
      }}
    >
      <Image
        source={{ uri: item.cover || 'https://via.placeholder.com/150x225' }}
        style={styles.seriesPoster}
        resizeMode="cover"
      />
      <View style={styles.seriesInfo}>
        <Text style={styles.seriesName} numberOfLines={1}>
          {item.name}
        </Text>
        <View style={styles.seriesMeta}>
          {item.rating_5based > 0 && (
            <Text style={styles.seriesRating}>★ {item.rating_5based.toFixed(1)}</Text>
          )}
          {(item.release_date || item.releaseDate) && (
            <Text style={styles.seriesYear}>
              {(item.release_date || item.releaseDate)?.substring(0, 4)}
            </Text>
          )}
        </View>
      </View>
    </FocusablePressable>
  );

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  return (
    <SpatialNavigationNode>
      <View style={styles.container}>
        {/* Category selector */}
        <View style={styles.categoryListContainer}>
          <SpatialNavigationNode orientation="horizontal">
            <FlatList
              horizontal
              data={[
                { category_id: '', category_name: 'All Series', parent_id: 0 },
                ...seriesCategories,
              ]}
              keyExtractor={(item) => item.category_id || 'all'}
              renderItem={renderCategoryItem}
              style={styles.categoryList}
              showsHorizontalScrollIndicator={false}
              contentContainerStyle={styles.categoryListContent}
            />
          </SpatialNavigationNode>
        </View>

        {/* Series grid */}
        <View style={styles.gridContent}>
          {isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          ) : (
            <SpatialNavigationVirtualizedGrid
              data={series}
              renderItem={renderSeriesItem}
              numberOfColumns={6}
              itemHeight={scaledPixels(390)}
              style={styles.seriesGrid}
            />
          )}
        </View>
      </View>
    </SpatialNavigationNode>
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
    height: scaledPixels(80),
    backgroundColor: colors.backgroundElevated,
  },
  categoryList: {
    flex: 1,
  },
  categoryListContent: {
    paddingHorizontal: scaledPixels(20),
    alignItems: 'center',
  },
  categoryButton: {
    paddingHorizontal: scaledPixels(25),
    paddingVertical: scaledPixels(12),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(25),
    marginHorizontal: scaledPixels(8),
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
  seriesCard: {
    width: CARD_WIDTH,
    margin: CARD_MARGIN,
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    borderWidth: 3,
    borderColor: 'transparent',
  },
  seriesCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  seriesPoster: {
    width: '100%',
    aspectRatio: 2 / 3,
  },
  seriesInfo: {
    padding: scaledPixels(12),
  },
  seriesName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    fontWeight: '500',
  },
  seriesMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(8),
    marginTop: scaledPixels(4),
  },
  seriesRating: {
    color: colors.warning,
    fontSize: scaledPixels(14),
  },
  seriesYear: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
  },
});
