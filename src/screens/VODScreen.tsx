import React, { useEffect, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  ActivityIndicator,
} from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamCategory, XtreamVodStream } from '../types/xtream';

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
    <TouchableOpacity
      style={[
        styles.categoryButton,
        selectedCategory === item.category_id && styles.categoryButtonActive,
      ]}
      onPress={() => setSelectedCategory(item.category_id)}
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
    </TouchableOpacity>
  );

  const renderMovieItem = ({ item }: { item: XtreamVodStream }) => (
    <TouchableOpacity
      style={styles.movieCard}
      onPress={() => {
        navigation.getParent()?.navigate('Player', {
          streamUrl: `movie/${item.stream_id}.${item.container_extension}`,
          title: item.name,
          type: 'vod',
        });
      }}
    >
      <Image
        source={{ uri: item.stream_icon || 'https://via.placeholder.com/150x225' }}
        style={styles.moviePoster}
        resizeMode="cover"
      />
      <View style={styles.movieInfo}>
        <Text style={styles.movieName} numberOfLines={2}>
          {item.name}
        </Text>
        {item.rating_5based > 0 && (
          <Text style={styles.movieRating}>★ {item.rating_5based.toFixed(1)}</Text>
        )}
      </View>
    </TouchableOpacity>
  );

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Category selector */}
      <FlatList
        horizontal
        data={[{ category_id: '', category_name: 'All Movies', parent_id: 0 }, ...vodCategories]}
        keyExtractor={(item) => item.category_id || 'all'}
        renderItem={renderCategoryItem}
        style={styles.categoryList}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.categoryListContent}
      />

      {/* Movies grid */}
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : (
        <FlatList
          data={vodStreams}
          keyExtractor={(item) => String(item.stream_id)}
          renderItem={renderMovieItem}
          numColumns={5}
          contentContainerStyle={styles.movieGrid}
          showsVerticalScrollIndicator={false}
        />
      )}
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
    fontSize: typography.fontSize.lg,
  },
  categoryList: {
    maxHeight: 60,
    backgroundColor: colors.backgroundElevated,
  },
  categoryListContent: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    gap: spacing.sm,
  },
  categoryButton: {
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    backgroundColor: colors.card,
    borderRadius: 20,
    marginRight: spacing.sm,
  },
  categoryButtonActive: {
    backgroundColor: colors.primary,
  },
  categoryText: {
    color: colors.textSecondary,
    fontSize: typography.fontSize.sm,
  },
  categoryTextActive: {
    color: colors.textOnPrimary,
    fontWeight: typography.fontWeight.semibold,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  movieGrid: {
    padding: spacing.md,
  },
  movieCard: {
    flex: 1,
    margin: spacing.xs,
    backgroundColor: colors.card,
    borderRadius: 12,
    overflow: 'hidden',
    maxWidth: '20%',
  },
  moviePoster: {
    width: '100%',
    aspectRatio: 2 / 3,
  },
  movieInfo: {
    padding: spacing.sm,
  },
  movieName: {
    color: colors.text,
    fontSize: typography.fontSize.sm,
    fontWeight: typography.fontWeight.medium,
  },
  movieRating: {
    color: colors.warning,
    fontSize: typography.fontSize.xs,
    marginTop: spacing.xs,
  },
});
