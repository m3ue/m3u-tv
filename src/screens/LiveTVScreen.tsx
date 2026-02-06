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
import { XtreamCategory, XtreamLiveStream } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { SpatialNavigationNode, SpatialNavigationVirtualizedGrid, SpatialNavigationVirtualizedList } from 'react-tv-space-navigation';

export function LiveTVScreen({ navigation }: DrawerScreenPropsType<'LiveTV'>) {
  const { isConfigured, liveCategories, fetchLiveStreams, getLiveStreamUrl } = useXtream();
  const [liveStreams, setLiveStreams] = useState<XtreamLiveStream[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string | undefined>(undefined);
  const [isLoading, setIsLoading] = useState(false);

  useEffect(() => {
    if (isConfigured) {
      loadStreams();
    }
  }, [isConfigured, selectedCategory]);

  const loadStreams = async () => {
    setIsLoading(true);
    const streams = await fetchLiveStreams(selectedCategory);
    setLiveStreams(streams);
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

  const renderStreamItem = ({ item }: { item: XtreamLiveStream }) => (
    <FocusablePressable
      style={({ isFocused }) => [
        styles.channelCard,
        isFocused && styles.channelCardFocused
      ]}
      onSelect={() => {
        const streamUrl = getLiveStreamUrl(item.stream_id);
        // @ts-ignore
        navigation.navigate('Player', {
          streamUrl,
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
            data={[{ category_id: '', category_name: 'All Channels', parent_id: 0 }, ...liveCategories]}
            renderItem={renderCategoryItem}
            itemSize={scaledPixels(195)}
            style={styles.categoryList}
            orientation="horizontal"
          />
        </View>

        {/* Channels grid */}
        <View style={styles.gridContainer}>
          {isLoading ? (
            <View style={styles.loadingContainer}>
              <ActivityIndicator size="large" color={colors.primary} />
            </View>
          ) : (
            <SpatialNavigationVirtualizedGrid
              data={liveStreams}
              renderItem={renderStreamItem}
              numberOfColumns={8}
              itemHeight={scaledPixels(224)}
              style={styles.channelGrid}
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
    paddingVertical: scaledPixels(12),
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
  gridContainer: {
    flex: 1,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  channelGrid: {
    padding: scaledPixels(20),
  },
  channelCard: {
    width: scaledPixels(200),
    height: scaledPixels(200),
    margin: scaledPixels(12),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(15),
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 3,
    borderColor: 'transparent',
  },
  channelCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  channelIcon: {
    width: scaledPixels(120),
    height: scaledPixels(120),
    marginBottom: scaledPixels(10),
  },
  channelName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    textAlign: 'center',
  },
});
