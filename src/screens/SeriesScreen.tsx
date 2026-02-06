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
import { XtreamCategory, XtreamSeries } from '../types/xtream';

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

  const renderSeriesItem = ({ item }: { item: XtreamSeries }) => (
    <TouchableOpacity
      style={styles.seriesCard}
      onPress={() => {
        navigation.getParent()?.navigate('Details', {
          item,
          type: 'series',
        });
      }}
    >
      <Image
        source={{ uri: item.cover || 'https://via.placeholder.com/150x225' }}
        style={styles.seriesPoster}
        resizeMode="cover"
      />
      <View style={styles.seriesInfo}>
        <Text style={styles.seriesName} numberOfLines={2}>
          {item.name}
        </Text>
        {item.rating_5based > 0 && (
          <Text style={styles.seriesRating}>★ {item.rating_5based.toFixed(1)}</Text>
        )}
        {(item.release_date || item.releaseDate) && (
          <Text style={styles.seriesYear}>
            {(item.release_date || item.releaseDate)?.substring(0, 4)}
          </Text>
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
        data={[{ category_id: '', category_name: 'All Series', parent_id: 0 }, ...seriesCategories]}
        keyExtractor={(item) => item.category_id || 'all'}
        renderItem={renderCategoryItem}
        style={styles.categoryList}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.categoryListContent}
      />

      {/* Series grid */}
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : (
        <FlatList
          data={series}
          keyExtractor={(item) => String(item.series_id)}
          renderItem={renderSeriesItem}
          numColumns={5}
          contentContainerStyle={styles.seriesGrid}
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
  seriesGrid: {
    padding: spacing.md,
  },
  seriesCard: {
    flex: 1,
    margin: spacing.xs,
    backgroundColor: colors.card,
    borderRadius: 12,
    overflow: 'hidden',
    maxWidth: '20%',
  },
  seriesPoster: {
    width: '100%',
    aspectRatio: 2 / 3,
  },
  seriesInfo: {
    padding: spacing.sm,
  },
  seriesName: {
    color: colors.text,
    fontSize: typography.fontSize.sm,
    fontWeight: typography.fontWeight.medium,
  },
  seriesRating: {
    color: colors.warning,
    fontSize: typography.fontSize.xs,
    marginTop: spacing.xs,
  },
  seriesYear: {
    color: colors.textSecondary,
    fontSize: typography.fontSize.xs,
    marginTop: 2,
  },
});
