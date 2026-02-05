import { StyleSheet, View, Image, Text } from 'react-native';
import { useNavigation, CommonActions } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import React, { useCallback, useMemo, useState, useEffect } from 'react';
import { DrawerActions, useIsFocused } from '@react-navigation/native';
import { useMenuContext } from '../components/MenuContext';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { XtreamLiveStream, XtreamVodStream, XtreamSeries } from '../types/xtream';
import {
  SpatialNavigationFocusableView,
  SpatialNavigationRoot,
  SpatialNavigationScrollView,
  SpatialNavigationNode,
  SpatialNavigationVirtualizedList,
  DefaultFocus,
} from 'react-tv-space-navigation';
import { Direction } from '@bam.tech/lrud';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList, DrawerParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import PlatformLinearGradient from '../components/PlatformLinearGradient';
import LoadingIndicator from '../components/LoadingIndicator';
import FocusablePressable from '../components/FocusablePressable';

type HomeScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

const ContentCard = React.memo(
  ({
    item,
    isFocused,
    type,
  }: {
    item: { name: string; icon?: string };
    isFocused: boolean;
    type: 'live' | 'vod' | 'series';
  }) => {
    const imageSource = useMemo(
      () => (item.icon ? { uri: item.icon } : undefined),
      [item.icon],
    );

    return (
      <View style={[styles.contentCard, isFocused && styles.contentCardFocused]}>
        {imageSource ? (
          <Image source={imageSource} style={styles.cardImage} resizeMode="cover" />
        ) : (
          <View style={styles.cardPlaceholder}>
            <Text style={styles.cardPlaceholderText}>
              {type === 'live' ? '📺' : type === 'vod' ? '🎬' : '📺'}
            </Text>
          </View>
        )}
        <View style={styles.cardOverlay}>
          <Text style={styles.cardTitle} numberOfLines={2}>
            {item.name}
          </Text>
        </View>
      </View>
    );
  },
);

export default function HomeScreen() {
  const navigation = useNavigation<HomeScreenNavigationProp>();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();
  const { isConfigured, isLoading: contextLoading, loadSavedCredentials } = useXtream();
  const isFocused = useIsFocused();
  const isActive = isFocused && !isMenuOpen;

  const [liveChannels, setLiveChannels] = useState<XtreamLiveStream[]>([]);
  const [movies, setMovies] = useState<XtreamVodStream[]>([]);
  const [series, setSeries] = useState<XtreamSeries[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  // Try to load saved credentials on mount
  useEffect(() => {
    loadSavedCredentials();
  }, [loadSavedCredentials]);

  // Load content when configured
  useEffect(() => {
    if (!isConfigured) {
      setIsLoading(false);
      return;
    }

    const loadContent = async () => {
      setIsLoading(true);
      try {
        const [liveData, vodData, seriesData] = await Promise.all([
          xtreamService.getLiveStreams().then((data) => data.slice(0, 20)),
          xtreamService.getVodStreams().then((data) => data.slice(0, 20)),
          xtreamService.getSeries().then((data) => data.slice(0, 20)),
        ]);
        setLiveChannels(liveData);
        setMovies(vodData);
        setSeries(seriesData);
      } catch (error) {
        console.error('Failed to load content:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadContent();
  }, [isConfigured]);

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

  const handleSeriesSelect = useCallback(
    (item: XtreamSeries) => {
      navigation.navigate('SeriesDetails', {
        seriesId: item.series_id,
        name: item.name,
        cover: item.cover,
        plot: item.plot,
        rating: item.rating_5based,
        year: item.release_date || item.releaseDate,
      });
    },
    [navigation],
  );

  const navigateToSettings = useCallback(() => {
    // Navigate to Settings tab
    navigation.dispatch(
      CommonActions.reset({
        index: 0,
        routes: [
          {
            name: 'DrawerNavigator',
            state: {
              routes: [{ name: 'Settings' }],
            },
          },
        ],
      }),
    );
  }, [navigation]);

  const renderLiveItem = useCallback(
    ({ item }: { item: XtreamLiveStream }) => (
      <SpatialNavigationFocusableView onSelect={() => handleChannelSelect(item)}>
        {({ isFocused }) => (
          <ContentCard
            item={{ name: item.name, icon: item.stream_icon }}
            isFocused={isFocused}
            type="live"
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [handleChannelSelect],
  );

  const renderMovieItem = useCallback(
    ({ item }: { item: XtreamVodStream }) => (
      <SpatialNavigationFocusableView onSelect={() => handleMovieSelect(item)}>
        {({ isFocused }) => (
          <ContentCard
            item={{ name: item.name, icon: item.stream_icon }}
            isFocused={isFocused}
            type="vod"
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [handleMovieSelect],
  );

  const renderSeriesItem = useCallback(
    ({ item }: { item: XtreamSeries }) => (
      <SpatialNavigationFocusableView onSelect={() => handleSeriesSelect(item)}>
        {({ isFocused }) => (
          <ContentCard
            item={{ name: item.name, icon: item.cover }}
            isFocused={isFocused}
            type="series"
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [handleSeriesSelect],
  );

  // Not connected state
  if (!isConfigured && !contextLoading) {
    return (
      <SpatialNavigationRoot
        isActive={isActive}
        onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}
      >
        <View style={styles.container}>
          <PlatformLinearGradient
            colors={['#1e1b4b', '#312e81', '#1e1b4b']}
            style={styles.welcomeGradient}
          />
          <View style={styles.welcomeContainer}>
            <Text style={styles.welcomeTitle}>Welcome to M3U TV</Text>
            <Text style={styles.welcomeSubtitle}>
              Connect to your Xtream service to start watching Live TV, Movies, and Series
            </Text>
            <SpatialNavigationNode>
              <DefaultFocus>
                <FocusablePressable
                  text="Go to Settings"
                  onSelect={navigateToSettings}
                  style={styles.welcomeButton}
                />
              </DefaultFocus>
            </SpatialNavigationNode>
          </View>
        </View>
      </SpatialNavigationRoot>
    );
  }

  // Loading state
  if (isLoading) {
    return (
      <View style={styles.container}>
        <LoadingIndicator />
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
          <Text style={styles.headerTitle}>M3U TV</Text>
          <Text style={styles.headerSubtitle}>Your entertainment, anywhere</Text>
        </View>

        <SpatialNavigationScrollView
          offsetFromStart={scaledPixels(60)}
          style={styles.scrollContent}
        >
          {/* Live TV Section */}
          {liveChannels.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Live TV</Text>
              <SpatialNavigationNode>
                <DefaultFocus>
                  <SpatialNavigationVirtualizedList
                    data={liveChannels}
                    orientation="horizontal"
                    renderItem={renderLiveItem}
                    itemSize={scaledPixels(240)}
                    numberOfRenderedItems={8}
                    numberOfItemsVisibleOnScreen={5}
                  />
                </DefaultFocus>
              </SpatialNavigationNode>
            </View>
          )}

          {/* Movies Section */}
          {movies.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Movies</Text>
              <SpatialNavigationNode>
                <SpatialNavigationVirtualizedList
                  data={movies}
                  orientation="horizontal"
                  renderItem={renderMovieItem}
                  itemSize={scaledPixels(200)}
                  numberOfRenderedItems={8}
                  numberOfItemsVisibleOnScreen={6}
                />
              </SpatialNavigationNode>
            </View>
          )}

          {/* Series Section */}
          {series.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>TV Series</Text>
              <SpatialNavigationNode>
                <SpatialNavigationVirtualizedList
                  data={series}
                  orientation="horizontal"
                  renderItem={renderSeriesItem}
                  itemSize={scaledPixels(200)}
                  numberOfRenderedItems={8}
                  numberOfItemsVisibleOnScreen={6}
                />
              </SpatialNavigationNode>
            </View>
          )}
        </SpatialNavigationScrollView>
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
  welcomeGradient: {
    ...StyleSheet.absoluteFillObject,
  },
  welcomeContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: scaledPixels(60),
  },
  welcomeTitle: {
    color: colors.text,
    fontSize: scaledPixels(64),
    fontWeight: 'bold',
    marginBottom: scaledPixels(24),
    textAlign: 'center',
  },
  welcomeSubtitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(28),
    textAlign: 'center',
    marginBottom: scaledPixels(48),
    maxWidth: scaledPixels(800),
  },
  welcomeButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: scaledPixels(48),
    paddingVertical: scaledPixels(20),
  },
  header: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    paddingTop: scaledPixels(safeZones.actionSafe.vertical),
    paddingBottom: scaledPixels(20),
  },
  headerTitle: {
    color: colors.text,
    fontSize: scaledPixels(56),
    fontWeight: 'bold',
  },
  headerSubtitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    marginTop: scaledPixels(8),
  },
  scrollContent: {
    flex: 1,
    marginBottom: scaledPixels(safeZones.actionSafe.vertical),
  },
  section: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    paddingVertical: scaledPixels(24),
    height: scaledPixels(400),
  },
  sectionTitle: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
    marginBottom: scaledPixels(16),
  },
  contentCard: {
    width: scaledPixels(220),
    height: scaledPixels(280),
    marginRight: scaledPixels(16),
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    backgroundColor: colors.card,
    borderWidth: scaledPixels(3),
    borderColor: 'transparent',
  },
  contentCardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.05 }],
    shadowColor: colors.focusGlow,
    shadowOffset: { width: 0, height: scaledPixels(4) },
    shadowOpacity: 0.3,
    shadowRadius: scaledPixels(12),
    elevation: 8,
  },
  cardImage: {
    width: '100%',
    height: '100%',
  },
  cardPlaceholder: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.cardElevated,
  },
  cardPlaceholderText: {
    fontSize: scaledPixels(48),
  },
  cardOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    backgroundColor: colors.scrimDark,
    padding: scaledPixels(12),
  },
  cardTitle: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '600',
  },
});
