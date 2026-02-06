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
import { XtreamCategory, XtreamLiveStream } from '../types/xtream';

export function LiveTVScreen({ navigation }: DrawerScreenPropsType<'LiveTV'>) {
  const { isConfigured, liveCategories, liveStreams, fetchLiveStreams } = useXtream();
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (isConfigured) {
      loadStreams();
    }
  }, [isConfigured, selectedCategory]);

  const loadStreams = async () => {
    setIsLoading(true);
    await fetchLiveStreams(selectedCategory);
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

  const renderStreamItem = ({ item }: { item: XtreamLiveStream }) => (
    <TouchableOpacity
      style={styles.channelCard}
      onPress={() => {
        // Navigate to player
        navigation.getParent()?.navigate('Player', {
          streamUrl: `live/${item.stream_id}`,
          title: item.name,
          type: 'live',
        });
      }}
    >
      <Image
        source={{ uri: item.stream_icon || 'https://via.placeholder.com/80' }}
        style={styles.channelIcon}
        resizeMode="contain"
      />
      <Text style={styles.channelName} numberOfLines={2}>
        {item.name}
      </Text>
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
        data={[{ category_id: '', category_name: 'All Channels', parent_id: 0 }, ...liveCategories]}
        keyExtractor={(item) => item.category_id || 'all'}
        renderItem={renderCategoryItem}
        style={styles.categoryList}
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.categoryListContent}
      />

      {/* Channels grid */}
      {isLoading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={colors.primary} />
        </View>
      ) : (
        <FlatList
          data={liveStreams}
          keyExtractor={(item) => String(item.stream_id)}
          renderItem={renderStreamItem}
          numColumns={4}
          contentContainerStyle={styles.channelGrid}
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
  channelGrid: {
    padding: spacing.md,
  },
  channelCard: {
    flex: 1,
    margin: spacing.xs,
    backgroundColor: colors.card,
    borderRadius: 12,
    padding: spacing.md,
    alignItems: 'center',
    maxWidth: '25%',
  },
  channelIcon: {
    width: 80,
    height: 60,
    marginBottom: spacing.sm,
    borderRadius: 4,
  },
  channelName: {
    color: colors.text,
    fontSize: typography.fontSize.sm,
    textAlign: 'center',
  },
});
