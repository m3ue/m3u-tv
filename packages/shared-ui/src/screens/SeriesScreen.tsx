import React, { useCallback, useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text } from 'react-native';
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
import PlatformLinearGradient from '../components/PlatformLinearGradient';
import MediaCard, { MEDIA_CARD_WIDTH, MEDIA_CARD_MARGIN } from '../components/MediaCard';

type SeriesNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

// Calculate item size for virtualized list (card width + margin)
const ITEM_SIZE = MEDIA_CARD_WIDTH + MEDIA_CARD_MARGIN;

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
        {({ isFocused }) => (
          <MediaCard
            name={item.name}
            image={item.cover}
            isFocused={isFocused}
            type="series"
            rating={item.rating_5based}
            year={item.release_date || item.releaseDate}
          />
        )}
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
        <PlatformLinearGradient
          colors={colors.gradientBackground}
          style={styles.backgroundGradient}
        />
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
          <View style={styles.contentArea}>
            <SpatialNavigationScrollView
              offsetFromStart={scaledPixels(20)}
              style={styles.scrollView}
            >
              <SpatialNavigationNode>
                <View style={styles.listWrapper}>
                  <SpatialNavigationVirtualizedList
                    data={seriesList}
                    orientation="horizontal"
                    renderItem={renderSeriesItem}
                    itemSize={ITEM_SIZE}
                    numberOfRenderedItems={10}
                    numberOfItemsVisibleOnScreen={5}
                  />
                </View>
              </SpatialNavigationNode>
            </SpatialNavigationScrollView>
          </View>
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
  backgroundGradient: {
    ...StyleSheet.absoluteFillObject,
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
  contentArea: {
    flex: 1,
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  scrollView: {
    flex: 1,
  },
  listWrapper: {
    height: scaledPixels(380),
    paddingVertical: scaledPixels(10),
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
