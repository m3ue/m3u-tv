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
import { XtreamVodStream, XtreamCategory } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';
import PlatformLinearGradient from '../components/PlatformLinearGradient';
import MediaCard, { MEDIA_CARD_WIDTH, MEDIA_CARD_MARGIN } from '../components/MediaCard';

type VODNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

// Calculate item size for virtualized list (card width + margin)
const ITEM_SIZE = MEDIA_CARD_WIDTH + MEDIA_CARD_MARGIN;

const CategoryTab = React.memo(
  ({ category, isSelected, isFocused }: { category: XtreamCategory; isSelected: boolean; isFocused: boolean }) => (
    <View
      style={[styles.categoryTab, isSelected && styles.categoryTabSelected, isFocused && styles.categoryTabFocused]}
    >
      <Text style={[styles.categoryTabText, isSelected && styles.categoryTabTextSelected]} numberOfLines={1}>
        {category.category_name}
      </Text>
    </View>
  ),
);

export default function VODScreen() {
  const navigation = useNavigation<VODNavigationProp>();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();
  const { isConfigured, vodCategories } = useXtream();
  const isFocused = useIsFocused();
  const isActive = isFocused && !isMenuOpen;

  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [movies, setMovies] = useState<XtreamVodStream[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  // Add "All" category at the beginning
  const allCategories = useMemo(() => {
    const allCategory: XtreamCategory = {
      category_id: 'all',
      category_name: 'All Movies',
      parent_id: 0,
    };
    return [allCategory, ...vodCategories];
  }, [vodCategories]);

  // Load movies when category changes
  useEffect(() => {
    if (!isConfigured) return;

    const loadMovies = async () => {
      setIsLoading(true);
      try {
        const categoryId = selectedCategory === 'all' ? undefined : selectedCategory || undefined;
        const streams = await xtreamService.getVodStreams(categoryId);
        setMovies(streams);
      } catch (error) {
        console.error('Failed to load movies:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadMovies();
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

  const handleMovieSelect = useCallback(
    (movie: XtreamVodStream) => {
      navigation.navigate('VodDetails', {
        streamId: movie.stream_id,
        name: movie.name,
        icon: movie.stream_icon,
        extension: movie.container_extension,
        rating: movie.rating_5based,
      });
    },
    [navigation],
  );

  const renderCategoryItem = useCallback(
    ({ item }: { item: XtreamCategory }) => (
      <SpatialNavigationFocusableView onSelect={() => setSelectedCategory(item.category_id)}>
        {({ isFocused }) => (
          <CategoryTab category={item} isSelected={selectedCategory === item.category_id} isFocused={isFocused} />
        )}
      </SpatialNavigationFocusableView>
    ),
    [selectedCategory],
  );

  const renderMovieItem = useCallback(
    ({ item }: { item: XtreamVodStream }) => (
      <SpatialNavigationFocusableView onSelect={() => handleMovieSelect(item)}>
        {({ isFocused }) => (
          <MediaCard
            name={item.name}
            image={item.stream_icon}
            isFocused={isFocused}
            type="vod"
            rating={item.rating_5based}
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [handleMovieSelect],
  );

  if (!isConfigured) {
    return (
      <View style={styles.container}>
        <View style={styles.notConfigured}>
          <Text style={styles.notConfiguredTitle}>Not Connected</Text>
          <Text style={styles.notConfiguredText}>Please configure your Xtream connection in Settings</Text>
        </View>
      </View>
    );
  }

  return (
    <SpatialNavigationRoot isActive={isActive} onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}>
      <View style={styles.container}>
        <PlatformLinearGradient colors={colors.gradientBackground} style={styles.backgroundGradient} />
        <View style={styles.header}>
          <Text style={styles.title}>Movies</Text>
          <Text style={styles.subtitle}>
            {movies.length} movies
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

        {/* Movies Grid */}
        {isLoading ? (
          <LoadingIndicator />
        ) : movies.length > 0 ? (
          <SpatialNavigationScrollView offsetFromStart={scaledPixels(20)} style={styles.scrollView}>
            <View style={styles.section}>
              <SpatialNavigationNode>
                <View style={styles.listWrapper}>
                  <SpatialNavigationVirtualizedList
                    data={movies}
                    orientation="horizontal"
                    renderItem={renderMovieItem}
                    itemSize={ITEM_SIZE}
                    numberOfRenderedItems={10}
                    numberOfItemsVisibleOnScreen={5}
                  />
                </View>
              </SpatialNavigationNode>
            </View>
          </SpatialNavigationScrollView>
        ) : (
          <View style={styles.emptyState}>
            <Text style={styles.emptyStateText}>No movies found</Text>
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
  scrollView: {
    flex: 1,
  },
  section: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
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
