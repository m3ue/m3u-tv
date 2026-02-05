import React, { useCallback, useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text, Image } from 'react-native';
import { useNavigation, DrawerActions, useIsFocused } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  SpatialNavigationRoot,
  SpatialNavigationScrollView,
  SpatialNavigationNode,
  SpatialNavigationFocusableView,
  SpatialNavigationVirtualizedList,
  DefaultFocus,
} from 'react-tv-space-navigation';
import { Direction } from '@bam.tech/lrud';
import { useMenuContext } from '../components/MenuContext';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { XtreamSeries, XtreamCategory } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';

type SeriesNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

const SeriesItem = React.memo(
  ({ item, isFocused }: { item: XtreamSeries; isFocused: boolean }) => {
    const imageSource = useMemo(
      () => (item.cover ? { uri: item.cover } : undefined),
      [item.cover],
    );

    return (
      <View style={[styles.seriesCard, isFocused && styles.seriesCardFocused]}>
        <View style={styles.seriesPoster}>
          {imageSource ? (
            <Image source={imageSource} style={styles.seriesImage} resizeMode="cover" />
          ) : (
            <View style={styles.seriesPlaceholder}>
              <Text style={styles.seriesPlaceholderText}>📺</Text>
            </View>
          )}
          {item.rating_5based > 0 && (
            <View style={styles.ratingBadge}>
              <Text style={styles.ratingText}>★ {item.rating_5based.toFixed(1)}</Text>
            </View>
          )}
        </View>
        <View style={styles.seriesInfo}>
          <Text style={styles.seriesTitle} numberOfLines={2}>
            {item.name}
          </Text>
          {(item.release_date || item.releaseDate) && (
            <Text style={styles.seriesYear}>
              {item.release_date || item.releaseDate}
            </Text>
          )}
        </View>
      </View>
    );
  },
);

const CategoryTab = React.memo(
  ({
    category,
    isSelected,
    isFocused,
  }: {
    category: XtreamCategory;
    isSelected: boolean;
    isFocused: boolean;
  }) => (
    <View
      style={[
        styles.categoryTab,
        isSelected && styles.categoryTabSelected,
        isFocused && styles.categoryTabFocused,
      ]}
    >
      <Text
        style={[styles.categoryTabText, isSelected && styles.categoryTabTextSelected]}
        numberOfLines={1}
      >
        {category.category_name}
      </Text>
    </View>
  ),
);

export default function SeriesScreen() {
  const navigation = useNavigation<SeriesNavigationProp>();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();
  const { isConfigured, seriesCategories } = useXtream();
  const isFocused = useIsFocused();
  const isActive = isFocused && !isMenuOpen;

  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [seriesList, setSeriesList] = useState<XtreamSeries[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  // Add "All" category at the beginning
  const allCategories = useMemo(() => {
    const allCategory: XtreamCategory = {
      category_id: 'all',
      category_name: 'All Series',
      parent_id: 0,
    };
    return [allCategory, ...seriesCategories];
  }, [seriesCategories]);

  // Load series when category changes
  useEffect(() => {
    if (!isConfigured) return;

    const loadSeries = async () => {
      setIsLoading(true);
      try {
        const categoryId = selectedCategory === 'all' ? undefined : selectedCategory || undefined;
        const series = await xtreamService.getSeries(categoryId);
        setSeriesList(series);
      } catch (error) {
        console.error('Failed to load series:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadSeries();
  }, [isConfigured, selectedCategory]);

  // Set initial category
  useEffect(() => {
    if (allCategories.length > 0 && !selectedCategory) {
      setSelectedCategory(allCategories[0].category_id);
    }
  }, [allCategories, selectedCategory]);

  const onDirectionHandledWithoutMovement = useCallback(
    (movement: Direction) => {
      if (movement === 'left') {
        navigation.dispatch(DrawerActions.openDrawer());
        toggleMenu(true);
      }
    },
    [toggleMenu, navigation],
  );

  const handleSeriesSelect = useCallback(
    (series: XtreamSeries) => {
      navigation.navigate('SeriesDetails', {
        seriesId: series.series_id,
        name: series.name,
        cover: series.cover,
        plot: series.plot,
        rating: series.rating_5based,
        year: series.release_date || series.releaseDate,
      });
    },
    [navigation],
  );

  const renderCategoryItem = useCallback(
    ({ item }: { item: XtreamCategory }) => (
      <SpatialNavigationFocusableView onSelect={() => setSelectedCategory(item.category_id)}>
        {({ isFocused }) => (
          <CategoryTab
            category={item}
            isSelected={selectedCategory === item.category_id}
            isFocused={isFocused}
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [selectedCategory],
  );

  const renderSeriesItem = useCallback(
    ({ item }: { item: XtreamSeries }) => (
      <SpatialNavigationFocusableView onSelect={() => handleSeriesSelect(item)}>
        {({ isFocused }) => <SeriesItem item={item} isFocused={isFocused} />}
      </SpatialNavigationFocusableView>
    ),
    [handleSeriesSelect],
  );

  if (!isConfigured) {
    return (
      <View style={styles.container}>
        <View style={styles.notConfigured}>
          <Text style={styles.notConfiguredTitle}>Not Connected</Text>
          <Text style={styles.notConfiguredText}>
            Please configure your Xtream connection in Settings
          </Text>
        </View>
      </View>
    );
  }

  return (
    <SpatialNavigationRoot
      isActive={isActive}
      onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}
    >
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.title}>TV Series</Text>
          <Text style={styles.subtitle}>
            {seriesList.length} series
            {selectedCategory && selectedCategory !== 'all'
              ? ` in ${allCategories.find((c) => c.category_id === selectedCategory)?.category_name}`
              : ''}
          </Text>
        </View>

        {/* Category Tabs */}
        <View style={styles.categoriesContainer}>
          <SpatialNavigationNode>
            <DefaultFocus>
              <SpatialNavigationVirtualizedList
                data={allCategories}
                orientation="horizontal"
                renderItem={renderCategoryItem}
                itemSize={scaledPixels(200)}
                numberOfRenderedItems={8}
                numberOfItemsVisibleOnScreen={6}
              />
            </DefaultFocus>
          </SpatialNavigationNode>
        </View>

        {/* Series Grid */}
        {isLoading ? (
          <LoadingIndicator />
        ) : seriesList.length > 0 ? (
          <SpatialNavigationScrollView
            offsetFromStart={scaledPixels(20)}
            style={styles.seriesContainer}
          >
            <SpatialNavigationNode>
              <View style={styles.seriesGrid}>
                <SpatialNavigationVirtualizedList
                  data={seriesList}
                  orientation="horizontal"
                  renderItem={renderSeriesItem}
                  itemSize={scaledPixels(200)}
                  numberOfRenderedItems={10}
                  numberOfItemsVisibleOnScreen={6}
                />
              </View>
            </SpatialNavigationNode>
          </SpatialNavigationScrollView>
        ) : (
          <View style={styles.emptyState}>
            <Text style={styles.emptyStateText}>No series found</Text>
          </View>
        )}
      </View>
    </SpatialNavigationRoot>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    paddingTop: scaledPixels(safeZones.actionSafe.vertical),
    paddingBottom: scaledPixels(20),
  },
  title: {
    color: colors.text,
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    marginTop: scaledPixels(8),
  },
  categoriesContainer: {
    height: scaledPixels(80),
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    marginBottom: scaledPixels(20),
  },
  categoryTab: {
    paddingHorizontal: scaledPixels(24),
    paddingVertical: scaledPixels(12),
    marginRight: scaledPixels(12),
    borderRadius: scaledPixels(8),
    backgroundColor: colors.card,
    borderWidth: scaledPixels(2),
    borderColor: 'transparent',
  },
  categoryTabSelected: {
    backgroundColor: colors.primary,
  },
  categoryTabFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.05 }],
  },
  categoryTabText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    fontWeight: '600',
  },
  categoryTabTextSelected: {
    color: colors.text,
  },
  seriesContainer: {
    flex: 1,
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  seriesGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  seriesCard: {
    width: scaledPixels(180),
    marginRight: scaledPixels(16),
    marginBottom: scaledPixels(16),
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    borderWidth: scaledPixels(3),
    borderColor: 'transparent',
    backgroundColor: colors.card,
  },
  seriesCardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.08 }],
    shadowColor: colors.focus,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: scaledPixels(15),
    elevation: 10,
  },
  seriesPoster: {
    width: '100%',
    height: scaledPixels(260),
    backgroundColor: colors.cardElevated,
    position: 'relative',
  },
  seriesImage: {
    width: '100%',
    height: '100%',
  },
  seriesPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.cardElevated,
    alignItems: 'center',
    justifyContent: 'center',
  },
  seriesPlaceholderText: {
    fontSize: scaledPixels(48),
  },
  ratingBadge: {
    position: 'absolute',
    top: scaledPixels(8),
    right: scaledPixels(8),
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: scaledPixels(8),
    paddingVertical: scaledPixels(4),
    borderRadius: scaledPixels(4),
  },
  ratingText: {
    color: '#fbbf24',
    fontSize: scaledPixels(16),
    fontWeight: 'bold',
  },
  seriesInfo: {
    padding: scaledPixels(12),
  },
  seriesTitle: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '500',
  },
  seriesYear: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
    marginTop: scaledPixels(4),
  },
  notConfigured: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notConfiguredTitle: {
    color: colors.text,
    fontSize: scaledPixels(36),
    fontWeight: 'bold',
    marginBottom: scaledPixels(16),
  },
  notConfiguredText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emptyStateText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
  },
});
