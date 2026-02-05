import React, { useCallback, useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text, Image, ScrollView, Modal } from 'react-native';
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

    const formattedDuration = useMemo(() => {
      if (episode.info?.duration_secs) {
        const totalSecs = episode.info.duration_secs;
        const h = Math.floor(totalSecs / 3600);
        const m = Math.floor((totalSecs % 3600) / 60);
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
      }
      return episode.info?.duration;
    }, [episode.info]);

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
          {formattedDuration && (
            <View style={styles.durationBadge}>
              <Text style={styles.durationBadgeText}>{formattedDuration}</Text>
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
        </View>
      </View>
    );
  },
);

const EpisodeDetailModal = ({
  episode,
  onClose,
  onPlay,
  seriesName,
  seriesBackdrop
}: {
  episode: XtreamEpisode | null;
  onClose: () => void;
  onPlay: (episode: XtreamEpisode) => void;
  seriesName: string;
  seriesBackdrop: string | undefined;
}) => {
  if (!episode) return null;

  const formattedDuration = useMemo(() => {
    if (episode.info?.duration_secs) {
      const totalSecs = episode.info.duration_secs;
      const h = Math.floor(totalSecs / 3600);
      const m = Math.floor((totalSecs % 3600) / 60);
      return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    return episode.info?.duration;
  }, [episode.info]);

  const episodeBackdrop = episode.info?.movie_image || seriesBackdrop;

  return (
    <View style={styles.modalOverlay}>
      <View style={styles.modalContent}>
        {episodeBackdrop && (
          <Image
            source={{ uri: episodeBackdrop }}
            style={styles.modalImage}
            resizeMode="cover"
          />
        )}
        <PlatformLinearGradient
          colors={['transparent', 'rgba(0,0,0,0.4)', colors.background]}
          style={styles.modalGradient}
        />

        <View style={styles.modalTextContent}>
          <Text style={styles.modalEpisodeLabel}>
            Season {episode.season}, Episode {episode.episode_num}
          </Text>
          <Text style={styles.modalTitle}>{episode.title}</Text>

          <View style={styles.modalMetaRow}>
            {episode.info?.rating && (
              <Text style={styles.modalMetaText}>★ {parseFloat(String(episode.info.rating)).toFixed(1)}</Text>
            )}
            {formattedDuration && <Text style={styles.modalMetaText}>{formattedDuration}</Text>}
            {episode.info?.release_date && <Text style={styles.modalMetaText}>{episode.info.release_date}</Text>}
          </View>

          {episode.info?.plot && (
            <Text style={styles.modalPlot} numberOfLines={6}>
              {episode.info.plot}
            </Text>
          )}

          <SpatialNavigationNode orientation="horizontal">
            <View style={styles.modalActions}>
              <DefaultFocus>
                <FocusablePressable
                  text="Play Episode"
                  onSelect={() => onPlay(episode)}
                  style={styles.modalPlayButton}
                />
              </DefaultFocus>
              <FocusablePressable
                text="Close"
                onSelect={onClose}
                style={styles.modalCloseButton}
              />
            </View>
          </SpatialNavigationNode>
        </View>
      </View>
    </View>
  );
};

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
  const [selectedEpisode, setSelectedEpisode] = useState<XtreamEpisode | null>(null);
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

  const handleEpisodePlay = useCallback(
    (episode: XtreamEpisode) => {
      setSelectedEpisode(null);
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

  const seriesBackdrop = seriesInfo?.info?.backdrop_path?.[0] || cover;
  const seriesPlot = seriesInfo?.info?.plot || plot;
  const seriesRating = seriesInfo?.info?.rating_5based || rating;
  const seriesYear = seriesInfo?.info?.release_date?.substring(0, 4) || year;
  const seriesGenre = seriesInfo?.info?.genre;
  const seriesDirector = seriesInfo?.info?.director;
  const seriesCast = seriesInfo?.info?.cast;

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
      <SpatialNavigationFocusableView onSelect={() => setSelectedEpisode(item)}>
        {({ isFocused }) => <EpisodeItem episode={item} isFocused={isFocused} seriesName={name} />}
      </SpatialNavigationFocusableView>
    ),
    [name],
  );

  if (isLoading) {
    return (
      <View style={styles.container}>
        <LoadingIndicator />
      </View>
    );
  }

  return (
    <View style={styles.container}>
      {/* Full screen backdrop */}
      {seriesBackdrop && <Image source={{ uri: seriesBackdrop }} style={styles.fullscreenBackdrop} resizeMode="cover" />}
      <PlatformLinearGradient
        colors={['rgba(0,0,0,0.3)', 'rgba(0,0,0,0.7)', colors.background]}
        style={styles.fullscreenGradient}
      />

      <SpatialNavigationRoot isActive={!selectedEpisode}>
        <View style={styles.contentScrollWrapper}>
          {/* Header content */}
          <View style={styles.header}>
            <View style={styles.headerContent}>
              <Text style={styles.title}>{name}</Text>
              <View style={styles.metaRow}>
                {seriesYear && <Text style={styles.metaText}>{seriesYear}</Text>}
                {seriesGenre && <Text style={styles.metaText}>{seriesGenre}</Text>}
                {seriesRating && seriesRating > 0 && <Text style={styles.metaText}>★ {seriesRating.toFixed(1)}</Text>}
                {seriesInfo?.seasons && (
                  <Text style={styles.metaText}>
                    {seriesInfo.seasons.length} Season{seriesInfo.seasons.length > 1 ? 's' : ''}
                  </Text>
                )}
              </View>
              {seriesPlot && (
                <Text style={styles.plot} numberOfLines={3}>
                  {seriesPlot}
                </Text>
              )}

              {(seriesDirector || seriesCast) && (
                <View style={styles.extraInfo}>
                  {seriesDirector && (
                    <Text style={styles.extraInfoText}>
                      <Text style={styles.extraInfoLabel}>Director: </Text>
                      {seriesDirector}
                    </Text>
                  )}
                  {seriesCast && (
                    <Text style={styles.extraInfoText} numberOfLines={1}>
                      <Text style={styles.extraInfoLabel}>Cast: </Text>
                      {seriesCast}
                    </Text>
                  )}
                </View>
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
              <SpatialNavigationNode orientation="horizontal">
                <View style={styles.seasonsListWrapper}>
                  <SpatialNavigationVirtualizedList
                    data={seriesInfo.seasons}
                    orientation="horizontal"
                    renderItem={renderSeasonItem}
                    itemSize={scaledPixels(160)}
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
                  <SpatialNavigationNode orientation="horizontal">
                    <View style={styles.episodesListWrapper}>
                      <SpatialNavigationVirtualizedList
                        data={currentEpisodes}
                        orientation="horizontal"
                        renderItem={renderEpisodeItem}
                        itemSize={scaledPixels(320)}
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

      {/* Episode Overlay (instead of Modal) */}
      {selectedEpisode && (
        <SpatialNavigationRoot isActive={true}>
          <EpisodeDetailModal
            episode={selectedEpisode}
            onClose={() => setSelectedEpisode(null)}
            onPlay={handleEpisodePlay}
            seriesName={name}
            seriesBackdrop={seriesBackdrop}
          />
        </SpatialNavigationRoot>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  fullscreenBackdrop: {
    ...StyleSheet.absoluteFillObject,
    opacity: 0.4,
  },
  fullscreenGradient: {
    ...StyleSheet.absoluteFillObject,
  },
  contentScrollWrapper: {
    flex: 1,
  },
  modalOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.85)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 100,
  },
  header: {
    height: scaledPixels(400),
    justifyContent: 'flex-end',
    paddingBottom: scaledPixels(40),
  },
  headerContent: {
    paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
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
  durationBadge: {
    position: 'absolute',
    bottom: scaledPixels(8),
    right: scaledPixels(8),
    backgroundColor: 'rgba(0,0,0,0.7)',
    paddingHorizontal: scaledPixels(6),
    paddingVertical: scaledPixels(2),
    borderRadius: scaledPixels(4),
  },
  durationBadgeText: {
    color: colors.text,
    fontSize: scaledPixels(12),
    fontWeight: '600',
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
  extraInfo: {
    marginTop: scaledPixels(20),
    gap: scaledPixels(4),
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.1)',
    paddingTop: scaledPixels(16),
  },
  extraInfoText: {
    color: colors.text,
    fontSize: scaledPixels(18),
  },
  extraInfoLabel: {
    color: colors.textSecondary,
  },
  backButtonContainer: {
    position: 'absolute',
    top: scaledPixels(safeZones.actionSafe.vertical),
    left: scaledPixels(safeZones.actionSafe.horizontal),
    zIndex: 10,
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
  modalContainer: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.85)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  modalContent: {
    width: '70%',
    height: '70%',
    backgroundColor: colors.background,
    borderRadius: scaledPixels(24),
    overflow: 'hidden',
    position: 'relative',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  modalImage: {
    width: '100%',
    height: '100%',
    position: 'absolute',
    opacity: 0.4,
  },
  modalGradient: {
    ...StyleSheet.absoluteFillObject,
  },
  modalTextContent: {
    flex: 1,
    padding: scaledPixels(60),
    justifyContent: 'flex-end',
  },
  modalEpisodeLabel: {
    color: colors.primary,
    fontSize: scaledPixels(24),
    fontWeight: '600',
    marginBottom: scaledPixels(8),
  },
  modalTitle: {
    color: colors.text,
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    marginBottom: scaledPixels(20),
  },
  modalMetaRow: {
    flexDirection: 'row',
    gap: scaledPixels(20),
    marginBottom: scaledPixels(24),
  },
  modalMetaText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingHorizontal: scaledPixels(10),
    paddingVertical: scaledPixels(4),
    borderRadius: scaledPixels(6),
  },
  modalPlot: {
    color: colors.textSecondary,
    fontSize: scaledPixels(22),
    lineHeight: scaledPixels(32),
    marginBottom: scaledPixels(40),
  },
  modalActions: {
    gap: scaledPixels(20),
  },
  modalPlayButton: {
    minWidth: scaledPixels(200),
  },
  modalCloseButton: {
    minWidth: scaledPixels(150),
  },
});
