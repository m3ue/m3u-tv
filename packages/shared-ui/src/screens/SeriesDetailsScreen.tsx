import React, { useCallback, useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text, Image, ScrollView } from 'react-native';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
  SpatialNavigationRoot,
  SpatialNavigationScrollView,
  SpatialNavigationNode,
  SpatialNavigationFocusableView,
  SpatialNavigationVirtualizedList,
  DefaultFocus,
} from 'react-tv-space-navigation';
import { xtreamService } from '../services/XtreamService';
import { XtreamSeriesInfo, XtreamEpisode, XtreamSeason } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';
import FocusablePressable from '../components/FocusablePressable';
import PlatformLinearGradient from '../components/PlatformLinearGradient';

type SeriesDetailsNavigationProp = NativeStackNavigationProp<RootStackParamList, 'SeriesDetails'>;
type SeriesDetailsRouteProp = RouteProp<RootStackParamList, 'SeriesDetails'>;

const EpisodeItem = React.memo(
  ({ episode, isFocused, seriesName }: { episode: XtreamEpisode; isFocused: boolean; seriesName: string }) => {
    const imageSource = useMemo(
      () => (episode.info?.movie_image ? { uri: episode.info.movie_image } : undefined),
      [episode.info?.movie_image],
    );

    return (
      <View style={[styles.episodeCard, isFocused && styles.episodeCardFocused]}>
        <View style={styles.episodeThumbnail}>
          {imageSource ? (
            <Image source={imageSource} style={styles.episodeImage} resizeMode="cover" />
          ) : (
            <View style={styles.episodePlaceholder}>
              <Text style={styles.episodePlaceholderText}>E{episode.episode_num}</Text>
            </View>
          )}
        </View>
        <View style={styles.episodeInfo}>
          <Text style={styles.episodeNumber}>
            S{episode.season} E{episode.episode_num}
          </Text>
          <Text style={styles.episodeTitle} numberOfLines={1}>
            {episode.title}
          </Text>
          {episode.info?.duration && <Text style={styles.episodeDuration}>{episode.info.duration}</Text>}
        </View>
      </View>
    );
  },
);

const SeasonTab = React.memo(
  ({ season, isSelected, isFocused }: { season: XtreamSeason; isSelected: boolean; isFocused: boolean }) => (
    <View style={[styles.seasonTab, isSelected && styles.seasonTabSelected, isFocused && styles.seasonTabFocused]}>
      <Text style={[styles.seasonTabText, isSelected && styles.seasonTabTextSelected]}>
        Season {season.season_number}
      </Text>
    </View>
  ),
);

export default function SeriesDetailsScreen() {
  const navigation = useNavigation<SeriesDetailsNavigationProp>();
  const route = useRoute<SeriesDetailsRouteProp>();
  const { seriesId, name, cover, plot, rating, year } = route.params;

  const [seriesInfo, setSeriesInfo] = useState<XtreamSeriesInfo | null>(null);
  const [selectedSeason, setSelectedSeason] = useState<number>(1);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const loadSeriesInfo = async () => {
      setIsLoading(true);
      try {
        const info = await xtreamService.getSeriesInfo(seriesId);
        setSeriesInfo(info);
        if (info.seasons?.length > 0) {
          setSelectedSeason(info.seasons[0].season_number);
        }
      } catch (error) {
        console.error('Failed to load series info:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadSeriesInfo();
  }, [seriesId]);

  const currentEpisodes = useMemo(() => {
    if (!seriesInfo?.episodes) return [];
    return seriesInfo.episodes[String(selectedSeason)] || [];
  }, [seriesInfo, selectedSeason]);

  const handleEpisodeSelect = useCallback(
    (episode: XtreamEpisode) => {
      const streamUrl = xtreamService.getSeriesStreamUrl(episode.id, episode.container_extension);
      navigation.navigate('Player', {
        movie: streamUrl,
        headerImage: episode.info?.movie_image || cover,
        title: `${name} - S${episode.season}E${episode.episode_num}: ${episode.title}`,
        isLive: false,
      });
    },
    [navigation, name, cover],
  );

  const renderSeasonItem = useCallback(
    ({ item }: { item: XtreamSeason }) => (
      <SpatialNavigationFocusableView onSelect={() => setSelectedSeason(item.season_number)}>
        {({ isFocused }) => (
          <SeasonTab season={item} isSelected={selectedSeason === item.season_number} isFocused={isFocused} />
        )}
      </SpatialNavigationFocusableView>
    ),
    [selectedSeason],
  );

  const renderEpisodeItem = useCallback(
    ({ item }: { item: XtreamEpisode }) => (
      <SpatialNavigationFocusableView onSelect={() => handleEpisodeSelect(item)}>
        {({ isFocused }) => <EpisodeItem episode={item} isFocused={isFocused} seriesName={name} />}
      </SpatialNavigationFocusableView>
    ),
    [handleEpisodeSelect, name],
  );

  if (isLoading) {
    return (
      <View style={styles.container}>
        <LoadingIndicator />
      </View>
    );
  }

  return (
    <SpatialNavigationRoot isActive={true}>
      <View style={styles.container}>
        {/* Header with backdrop */}
        <View style={styles.header}>
          {cover && <Image source={{ uri: cover }} style={styles.backdrop} resizeMode="cover" />}
          <PlatformLinearGradient
            colors={['transparent', 'rgba(0,0,0,0.7)', colors.background]}
            style={styles.gradient}
          />
          <View style={styles.headerContent}>
            <Text style={styles.title}>{name}</Text>
            <View style={styles.metaRow}>
              {year && <Text style={styles.metaText}>{year}</Text>}
              {rating && rating > 0 && <Text style={styles.metaText}>★ {rating.toFixed(1)}</Text>}
              {seriesInfo?.seasons && (
                <Text style={styles.metaText}>
                  {seriesInfo.seasons.length} Season{seriesInfo.seasons.length > 1 ? 's' : ''}
                </Text>
              )}
            </View>
            {(plot || seriesInfo?.info?.plot) && (
              <Text style={styles.plot} numberOfLines={3}>
                {plot || seriesInfo?.info?.plot}
              </Text>
            )}
          </View>
        </View>

        {/* Back Button - at top of navigation tree */}
        <View style={styles.backButtonContainer}>
          <SpatialNavigationNode>
            <DefaultFocus>
              <FocusablePressable text="Back" onSelect={() => navigation.goBack()} style={styles.backButton} />
            </DefaultFocus>
          </SpatialNavigationNode>
        </View>

        {/* Season Tabs */}
        {seriesInfo?.seasons && seriesInfo.seasons.length > 0 && (
          <View style={styles.seasonsContainer}>
            <SpatialNavigationNode>
              <View style={styles.seasonsListWrapper}>
                <SpatialNavigationVirtualizedList
                  data={seriesInfo.seasons}
                  orientation="horizontal"
                  renderItem={renderSeasonItem}
                  itemSize={scaledPixels(160)}
                  numberOfRenderedItems={8}
                  numberOfItemsVisibleOnScreen={6}
                />
              </View>
            </SpatialNavigationNode>
          </View>
        )}

        {/* Episodes */}
        <View style={styles.episodesContainer}>
          <Text style={styles.episodesTitle}>
            {currentEpisodes.length} Episode{currentEpisodes.length !== 1 ? 's' : ''}
          </Text>
          {currentEpisodes.length > 0 ? (
            <SpatialNavigationScrollView style={styles.episodesList}>
              <View style={styles.section}>
                <SpatialNavigationNode>
                  <View style={styles.episodesListWrapper}>
                    <SpatialNavigationVirtualizedList
                      data={currentEpisodes}
                      orientation="horizontal"
                      renderItem={renderEpisodeItem}
                      itemSize={scaledPixels(320)}
                      numberOfRenderedItems={6}
                      numberOfItemsVisibleOnScreen={4}
                    />
                  </View>
                </SpatialNavigationNode>
              </View>
            </SpatialNavigationScrollView>
          ) : (
            <View style={styles.emptyState}>
              <Text style={styles.emptyStateText}>No episodes available</Text>
            </View>
          )}
        </View>
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
    height: scaledPixels(450),
    position: 'relative',
  },
  backdrop: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.5,
  },
  gradient: {
    ...StyleSheet.absoluteFillObject,
  },
  headerContent: {
    position: 'absolute',
    bottom: scaledPixels(40),
    left: scaledPixels(safeZones.actionSafe.horizontal),
    right: scaledPixels(safeZones.actionSafe.horizontal),
  },
  title: {
    color: colors.text,
    fontSize: scaledPixels(52),
    fontWeight: 'bold',
    textShadowColor: 'rgba(0, 0, 0, 0.8)',
    textShadowOffset: { width: 0, height: 2 },
    textShadowRadius: 4,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: scaledPixels(16),
    gap: scaledPixels(20),
  },
  metaText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(22),
  },
  metaBadge: {
    backgroundColor: colors.primary,
    paddingHorizontal: scaledPixels(12),
    paddingVertical: scaledPixels(6),
    borderRadius: scaledPixels(6),
  },
  metaBadgeText: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '600',
  },
  plot: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    marginTop: scaledPixels(20),
    maxWidth: '55%',
    lineHeight: scaledPixels(28),
  },
  seasonsContainer: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
    marginTop: scaledPixels(24),
  },
  seasonsListWrapper: {
    height: scaledPixels(70),
    paddingVertical: scaledPixels(8),
  },
  seasonTab: {
    paddingHorizontal: scaledPixels(28),
    paddingVertical: scaledPixels(14),
    marginRight: scaledPixels(16),
    borderRadius: scaledPixels(12),
    backgroundColor: colors.card,
    borderWidth: scaledPixels(2),
    borderColor: colors.border,
  },
  seasonTabSelected: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  seasonTabFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.05 }],
    shadowColor: colors.focusGlow,
    shadowOffset: { width: 0, height: scaledPixels(2) },
    shadowOpacity: 0.3,
    shadowRadius: scaledPixels(8),
  },
  seasonTabText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    fontWeight: '600',
  },
  seasonTabTextSelected: {
    color: colors.text,
  },
  episodesContainer: {
    flex: 1,
    marginTop: scaledPixels(28),
  },
  episodesTitle: {
    color: colors.text,
    fontSize: scaledPixels(28),
    fontWeight: 'bold',
    marginBottom: scaledPixels(20),
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  episodesList: {
    flex: 1,
  },
  section: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
  },
  episodesListWrapper: {
    height: scaledPixels(300),
    paddingVertical: scaledPixels(10),
  },
  episodeCard: {
    width: scaledPixels(300),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(16),
    marginRight: scaledPixels(20),
    overflow: 'hidden',
    borderWidth: scaledPixels(2),
    borderColor: colors.border,
  },
  episodeCardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.03 }],
    shadowColor: colors.focusGlow,
    shadowOffset: { width: 0, height: scaledPixels(4) },
    shadowOpacity: 0.3,
    shadowRadius: scaledPixels(12),
    elevation: 8,
  },
  episodeThumbnail: {
    width: '100%',
    height: scaledPixels(170),
    backgroundColor: colors.cardElevated,
  },
  episodeImage: {
    width: '100%',
    height: '100%',
  },
  episodePlaceholder: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  episodePlaceholderText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    fontWeight: 'bold',
  },
  episodeInfo: {
    padding: scaledPixels(12),
  },
  episodeNumber: {
    color: colors.primary,
    fontSize: scaledPixels(16),
    fontWeight: '600',
  },
  episodeTitle: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '500',
    marginTop: scaledPixels(4),
  },
  episodeDuration: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
    marginTop: scaledPixels(4),
  },
  backButtonContainer: {
    position: 'absolute',
    top: scaledPixels(safeZones.actionSafe.vertical),
    left: scaledPixels(safeZones.actionSafe.horizontal),
  },
  backButton: {
    // Don't set backgroundColor here - let FocusablePressable handle focus states
  },
  emptyState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: scaledPixels(40),
  },
  emptyStateText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
  },
});
