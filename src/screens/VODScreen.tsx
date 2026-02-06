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
import { XtreamCategory, XtreamVodStream } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { SpatialNavigationNode, SpatialNavigationVirtualizedGrid, SpatialNavigationVirtualizedList } from 'react-tv-space-navigation';

// Card dimensions for consistent sizing
const CARD_WIDTH = scaledPixels(200);
const CARD_MARGIN = scaledPixels(12);

export function VODScreen({ navigation }: DrawerScreenPropsType<'VOD'>) {
  const { isConfigured, vodCategories, vodStreams, fetchVodStreams } = useXtream();
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (isConfigured) {
      loadStreams();
    }
  }, [isConfigured, selectedCategory]);

  const loadStreams = async () => {
    setIsLoading(true);
    await fetchVodStreams(selectedCategory);
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

  const renderMovieItem = ({ item }: { item: XtreamVodStream }) => (
    <FocusablePressable
      style={({ isFocused }) => [
        styles.movieCard,
        isFocused && styles.movieCardFocused,
      ]}
      onSelect={() => {
        // @ts-ignore
        navigation.navigate('Details', { item });
      }}
    >
      <Image
        source={{ uri: item.stream_icon || 'https://via.placeholder.com/150x225' }}
        style={styles.moviePoster}
        resizeMode="cover"
      />
      <View style={styles.movieInfo}>
        <Text style={styles.movieName} numberOfLines={1}>
          {item.name}
        </Text>
        <Text style={styles.movieRating}>★ {item.rating || 'N/A'}</Text>
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
          <SpatialNavigationVirtualizedList
            data={[
              { category_id: '', category_name: 'All Movies', parent_id: 0 },
              ...vodCategories,
            ]}
            renderItem={renderCategoryItem}
            itemSize={scaledPixels(195)}
            style={styles.categoryList}
            orientation="horizontal"
          />
        </View>

        {/* Movies grid */}
        <View style={styles.gridContent}>
          {isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          ) : (
            <SpatialNavigationVirtualizedGrid
              data={vodStreams}
              renderItem={renderMovieItem}
              numberOfColumns={8}
              itemHeight={scaledPixels(390)}
              style={styles.movieGrid}
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
    paddingVertical: scaledPixels(10),
    paddingHorizontal: scaledPixels(10),
    marginHorizontal: scaledPixels(25),
    marginTop: scaledPixels(25),
    height: scaledPixels(80),
    borderRadius: scaledPixels(50),
    backgroundColor: colors.backgroundElevated,
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
  movieGrid: {
    padding: scaledPixels(20),
  },
  movieCard: {
    width: CARD_WIDTH,
    margin: CARD_MARGIN,
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    borderWidth: 3,
    borderColor: 'transparent',
  },
  movieCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  moviePoster: {
    width: '100%',
    aspectRatio: 2 / 3,
  },
  movieInfo: {
    padding: scaledPixels(12),
  },
  movieName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    fontWeight: '500',
  },
  movieRating: {
    color: colors.warning,
    fontSize: scaledPixels(14),
    marginTop: scaledPixels(4),
  },
});
