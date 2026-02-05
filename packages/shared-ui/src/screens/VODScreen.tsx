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
import { XtreamVodStream, XtreamCategory } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';
import PlatformLinearGradient from '../components/PlatformLinearGradient';

type VODNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

const MovieItem = React.memo(
  ({ item, isFocused }: { item: XtreamVodStream; isFocused: boolean }) => {
    const imageSource = useMemo(
      () => (item.stream_icon ? { uri: item.stream_icon } : undefined),
      [item.stream_icon],
    );

    return (
      <View style={[styles.movieCard, isFocused && styles.movieCardFocused]}>
        <View style={styles.moviePoster}>
          {imageSource ? (
            <Image source={imageSource} style={styles.movieImage} resizeMode="cover" />
          ) : (
            <View style={styles.moviePlaceholder}>
              <Text style={styles.moviePlaceholderText}>🎬</Text>
            </View>
          )}
          {item.rating_5based > 0 && (
            <View style={styles.ratingBadge}>
              <Text style={styles.ratingText}>★ {item.rating_5based.toFixed(1)}</Text>
            </View>
          )}
        </View>
        <Text style={styles.movieTitle} numberOfLines={2}>
          {item.name}
        </Text>
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
      const streamUrl = xtreamService.getVodStreamUrl(movie.stream_id, movie.container_extension);
      navigation.navigate('Player', {
        movie: streamUrl,
        headerImage: movie.stream_icon || '',
        title: movie.name,
        isLive: false,
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

  const renderMovieItem = useCallback(
    ({ item }: { item: XtreamVodStream }) => (
      <SpatialNavigationFocusableView onSelect={() => handleMovieSelect(item)}>
        {({ isFocused }) => <MovieItem item={item} isFocused={isFocused} />}
      </SpatialNavigationFocusableView>
    ),
    [handleMovieSelect],
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
          <SpatialNavigationScrollView
            offsetFromStart={scaledPixels(20)}
            style={styles.moviesContainer}
          >
            <SpatialNavigationNode>
              <View style={styles.moviesGrid}>
                <SpatialNavigationVirtualizedList
                  data={movies}
                  orientation="horizontal"
                  renderItem={renderMovieItem}
                  itemSize={scaledPixels(200)}
                  numberOfRenderedItems={10}
                  numberOfItemsVisibleOnScreen={6}
                />
              </View>
            </SpatialNavigationNode>
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
  moviesContainer: {
    flex: 1,
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  moviesGrid: {
    height: scaledPixels(380),
    paddingVertical: scaledPixels(20),
  },
  movieCard: {
    width: scaledPixels(180),
    marginRight: scaledPixels(20),
    borderRadius: scaledPixels(16),
    overflow: 'hidden',
    borderWidth: scaledPixels(2),
    borderColor: colors.border,
    backgroundColor: colors.card,
  },
  movieCardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.05 }],
    shadowColor: colors.focusGlow,
    shadowOffset: { width: 0, height: scaledPixels(4) },
    shadowOpacity: 0.3,
    shadowRadius: scaledPixels(12),
    elevation: 8,
  },
  moviePoster: {
    width: '100%',
    height: scaledPixels(260),
    backgroundColor: colors.cardElevated,
    position: 'relative',
  },
  movieImage: {
    width: '100%',
    height: '100%',
  },
  moviePlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.cardElevated,
    alignItems: 'center',
    justifyContent: 'center',
  },
  moviePlaceholderText: {
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
  movieTitle: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '500',
    padding: scaledPixels(12),
    backgroundColor: colors.card,
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
