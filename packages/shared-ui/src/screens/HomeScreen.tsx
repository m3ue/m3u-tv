import { StyleSheet, View, Text, Image } from 'react-native';
import { useNavigation, CommonActions } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import React, { useCallback, useState, useEffect } from 'react';
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
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import PlatformLinearGradient from '../components/PlatformLinearGradient';
import LoadingIndicator from '../components/LoadingIndicator';
import FocusablePressable from '../components/FocusablePressable';
import MediaCard, {
  MEDIA_CARD_WIDTH,
  MEDIA_CARD_MARGIN,
  LIVE_CARD_WIDTH,
  LIVE_CARD_MARGIN,
} from '../components/MediaCard';

type HomeScreenNavigationProp = NativeStackNavigationProp<RootStackParamList, 'DrawerNavigator'>;

// Calculate item sizes for virtualized lists (card width + margin)
const ITEM_SIZE = MEDIA_CARD_WIDTH + MEDIA_CARD_MARGIN;
const LIVE_ITEM_SIZE = LIVE_CARD_WIDTH + LIVE_CARD_MARGIN;

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
        {({ isFocused }) => <MediaCard name={item.name} image={item.stream_icon} isFocused={isFocused} type="live" />}
      </SpatialNavigationFocusableView>
    ),
    [handleChannelSelect],
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
            rating={item.rating}
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
          <MediaCard
            name={item.name}
            image={item.cover}
            isFocused={isFocused}
            type="series"
            rating={item.rating}
            year={item.release_date || item.releaseDate}
          />
        )}
      </SpatialNavigationFocusableView>
    ),
    [handleSeriesSelect],
  );

  // Not connected state
  if (!isConfigured && !contextLoading) {
    return (
      <SpatialNavigationRoot isActive={isActive} onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}>
        <View style={styles.container}>
          <PlatformLinearGradient colors={colors.gradientBackground} style={styles.backgroundGradient} />
          <View style={styles.welcomeContainer}>
            <Image source={require('../assets/images/logo.png')} style={styles.logo} resizeMode="contain" />
            <Text style={styles.welcomeTitle}>Welcome to M3U TV</Text>
            <Text style={styles.welcomeSubtitle}>
              Connect to your Xtream service to start watching Live TV, Movies, and Series
            </Text>
            <SpatialNavigationNode>
              <DefaultFocus>
                <FocusablePressable text="Go to Settings" onSelect={navigateToSettings} style={styles.welcomeButton} />
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
    <SpatialNavigationRoot isActive={isActive} onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}>
      <View style={styles.container}>
        <PlatformLinearGradient colors={colors.gradientBackground} style={styles.backgroundGradient} />

        <SpatialNavigationScrollView offsetFromStart={scaledPixels(280)} style={styles.scrollContent}>
          <View style={styles.header}>
            <Image source={require('../assets/images/logo.png')} style={styles.logo} resizeMode="contain" />
            <Text style={styles.headerSubtitle}>Your entertainment, your way</Text>
          </View>

          {/* Live TV Section */}
          {liveChannels.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Live TV</Text>
              <View style={styles.liveListWrapper}>
                <SpatialNavigationNode direction="horizontal">
                  <DefaultFocus>
                    <SpatialNavigationVirtualizedList
                      data={liveChannels}
                      orientation="horizontal"
                      renderItem={renderLiveItem}
                      itemSize={LIVE_ITEM_SIZE}
                      numberOfRenderedItems={8}
                      numberOfItemsVisibleOnScreen={6}
                    />
                  </DefaultFocus>
                </SpatialNavigationNode>
              </View>
            </View>
          )}

          {/* Movies Section */}
          {movies.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Movies</Text>
              <View style={styles.listWrapper}>
                <SpatialNavigationNode direction="horizontal">
                  <SpatialNavigationVirtualizedList
                    data={movies}
                    orientation="horizontal"
                    renderItem={renderMovieItem}
                    itemSize={ITEM_SIZE}
                    numberOfRenderedItems={8}
                    numberOfItemsVisibleOnScreen={5}
                  />
                </SpatialNavigationNode>
              </View>
            </View>
          )}

          {/* Series Section */}
          {series.length > 0 && (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>TV Series</Text>
              <View style={styles.listWrapper}>
                <SpatialNavigationNode direction="horizontal">
                  <SpatialNavigationVirtualizedList
                    data={series}
                    orientation="horizontal"
                    renderItem={renderSeriesItem}
                    itemSize={ITEM_SIZE}
                    numberOfRenderedItems={8}
                    numberOfItemsVisibleOnScreen={5}
                  />
                </SpatialNavigationNode>
              </View>
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
    alignItems: 'center',
  },
  logo: {
    width: scaledPixels(120),
    height: scaledPixels(120),
    borderRadius: scaledPixels(16),
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
    paddingTop: scaledPixels(16),
    paddingBottom: scaledPixels(24),
  },
  sectionTitle: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
    marginBottom: scaledPixels(16),
  },
  listWrapper: {
    height: scaledPixels(380),
    paddingVertical: scaledPixels(10),
  },
  liveListWrapper: {
    height: scaledPixels(250),
    paddingVertical: scaledPixels(10),
  },
});
