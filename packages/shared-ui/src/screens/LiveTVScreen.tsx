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
import { XtreamLiveStream, XtreamCategory } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';

type LiveTVNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

const ChannelItem = React.memo(
  ({ item, isFocused }: { item: XtreamLiveStream; isFocused: boolean }) => {
    const imageSource = useMemo(
      () => (item.stream_icon ? { uri: item.stream_icon } : undefined),
      [item.stream_icon],
    );

    return (
      <View style={[styles.channelCard, isFocused && styles.channelCardFocused]}>
        <View style={styles.channelIcon}>
          {imageSource ? (
            <Image source={imageSource} style={styles.channelImage} resizeMode="contain" />
          ) : (
            <View style={styles.channelPlaceholder}>
              <Text style={styles.channelPlaceholderText}>
                {item.name.charAt(0).toUpperCase()}
              </Text>
            </View>
          )}
        </View>
        <Text style={styles.channelName} numberOfLines={2}>
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
        style={[
          styles.categoryTabText,
          isSelected && styles.categoryTabTextSelected,
        ]}
        numberOfLines={1}
      >
        {category.category_name}
      </Text>
    </View>
  ),
);

export default function LiveTVScreen() {
  const navigation = useNavigation<LiveTVNavigationProp>();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();
  const { isConfigured, liveCategories } = useXtream();
  const isFocused = useIsFocused();
  const isActive = isFocused && !isMenuOpen;

  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [channels, setChannels] = useState<XtreamLiveStream[]>([]);
  const [isLoading, setIsLoading] = useState(false);

  // Add "All" category at the beginning
  const allCategories = useMemo(() => {
    const allCategory: XtreamCategory = {
      category_id: 'all',
      category_name: 'All Channels',
      parent_id: 0,
    };
    return [allCategory, ...liveCategories];
  }, [liveCategories]);

  // Load channels when category changes
  useEffect(() => {
    if (!isConfigured) return;

    const loadChannels = async () => {
      setIsLoading(true);
      try {
        const categoryId = selectedCategory === 'all' ? undefined : selectedCategory || undefined;
        const streams = await xtreamService.getLiveStreams(categoryId);
        setChannels(streams);
      } catch (error) {
        console.error('Failed to load channels:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadChannels();
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

  const handleChannelSelect = useCallback(
    (channel: XtreamLiveStream) => {
      const streamUrl = xtreamService.getLiveStreamUrl(channel.stream_id);
      navigation.navigate('Player', {
        movie: streamUrl,
        headerImage: channel.stream_icon || '',
        title: channel.name,
        isLive: true,
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

  const renderChannelItem = useCallback(
    ({ item }: { item: XtreamLiveStream }) => (
      <SpatialNavigationFocusableView onSelect={() => handleChannelSelect(item)}>
        {({ isFocused }) => <ChannelItem item={item} isFocused={isFocused} />}
      </SpatialNavigationFocusableView>
    ),
    [handleChannelSelect],
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
          <Text style={styles.title}>Live TV</Text>
          <Text style={styles.subtitle}>
            {channels.length} channels
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

        {/* Channels Grid */}
        {isLoading ? (
          <LoadingIndicator />
        ) : channels.length > 0 ? (
          <SpatialNavigationScrollView
            offsetFromStart={scaledPixels(20)}
            style={styles.channelsContainer}
          >
            <SpatialNavigationNode>
              <View style={styles.channelsGrid}>
                <SpatialNavigationVirtualizedList
                  data={channels}
                  orientation="horizontal"
                  renderItem={renderChannelItem}
                  itemSize={scaledPixels(220)}
                  numberOfRenderedItems={10}
                  numberOfItemsVisibleOnScreen={6}
                />
              </View>
            </SpatialNavigationNode>
          </SpatialNavigationScrollView>
        ) : (
          <View style={styles.emptyState}>
            <Text style={styles.emptyStateText}>No channels found</Text>
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
  channelsContainer: {
    flex: 1,
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  channelsGrid: {
    height: scaledPixels(220),
  },
  channelCard: {
    width: scaledPixels(200),
    height: scaledPixels(180),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(16),
    marginRight: scaledPixels(16),
    marginBottom: scaledPixels(16),
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: scaledPixels(3),
    borderColor: 'transparent',
  },
  channelCardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.08 }],
    shadowColor: colors.focus,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.8,
    shadowRadius: scaledPixels(15),
    elevation: 10,
  },
  channelIcon: {
    width: scaledPixels(80),
    height: scaledPixels(80),
    marginBottom: scaledPixels(12),
    borderRadius: scaledPixels(8),
    overflow: 'hidden',
  },
  channelImage: {
    width: '100%',
    height: '100%',
  },
  channelPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: scaledPixels(8),
  },
  channelPlaceholderText: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
  },
  channelName: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '500',
    textAlign: 'center',
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
