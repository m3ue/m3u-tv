import React, { useEffect, useState, useCallback, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Image,
  ImageBackground,
  useWindowDimensions,
  ScrollView,
  FlatList,
  Platform,
} from 'react-native';
import { FocusGuide } from '../components/FocusGuide';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { useViewer } from '../context/ViewerContext';
import { colors } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamSeriesInfo, XtreamEpisode, WatchProgress } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';
import ResumeDialog from '../components/ResumeDialog';

export const SeriesDetailsScreen = ({ route, navigation }: RootStackScreenProps<'SeriesDetails'>) => {
  const isFocused = useIsFocused();
  const { item } = route.params;
  const seasonListRef = useRef<FocusablePressableRef>(null);
  const firstEpisodeRef = useRef<FocusablePressableRef>(null);
  const { fetchSeriesInfo, getSeriesStreamUrl, isM3UEditor } = useXtream();
  const { activeViewer, getSeriesProgress } = useViewer();
  const [seriesInfo, setSeriesInfo] = useState<XtreamSeriesInfo | null>(null);
  const [selectedSeason, setSelectedSeason] = useState<string | null>(null);
  const [firstSeasonTag, setFirstSeasonTag] = useState<number>();
  const [firstEpisodeTag, setFirstEpisodeTag] = useState<number>();
  const episodes = seriesInfo?.episodes[selectedSeason || ''] || [];

  // Keyed by episode id (stream_id)
  const [episodeProgress, setEpisodeProgress] = useState<Record<number, WatchProgress>>({});
  const [pendingEpisode, setPendingEpisode] = useState<XtreamEpisode | null>(null);
  const [showResumeDialog, setShowResumeDialog] = useState(false);

  const { width } = useWindowDimensions();

  useEffect(() => {
    if (isFocused && seriesInfo?.seasons && seriesInfo.seasons.length > 0) {
      seasonListRef.current?.focus();
    }
  }, [isFocused, seriesInfo]);

  useEffect(() => {
    const id = setTimeout(() => {
      const seasonTag = seasonListRef.current?.getNodeHandle() ?? null;
      const episodeTag = firstEpisodeRef.current?.getNodeHandle() ?? null;

      if (typeof seasonTag === 'number') setFirstSeasonTag(seasonTag);
      if (typeof episodeTag === 'number') setFirstEpisodeTag(episodeTag);
    }, 0);

    return () => clearTimeout(id);
  }, [isFocused, selectedSeason, episodes.length]);

  useEffect(() => {
    const loadInfo = async () => {
      try {
        const info = await fetchSeriesInfo(item.series_id);
        if ((!info.seasons || info.seasons.length === 0) && info.episodes) {
          const keys = Object.keys(info.episodes).sort((a, b) => Number(a) - Number(b));
          info.seasons = keys.map((k) => ({
            air_date: '',
            episode_count: info.episodes[k].length,
            id: Number(k),
            name: `Season ${k}`,
            overview: '',
            season_number: Number(k),
          }));
        }
        setSeriesInfo(info);
        if (info.seasons && info.seasons.length > 0) {
          setSelectedSeason(String(info.seasons[0].season_number));
        }
      } catch (error) {
        console.error('Failed to fetch series info:', error);
      }
    };
    loadInfo();
  }, [item.series_id]);

  // Load episode progress for this series
  useEffect(() => {
    if (!isM3UEditor || !activeViewer) return;
    getSeriesProgress(item.series_id).then((progressList) => {
      const map: Record<number, WatchProgress> = {};
      progressList.forEach((p) => { map[p.stream_id] = p; });
      setEpisodeProgress(map);
    });
  }, [isM3UEditor, activeViewer, item.series_id, getSeriesProgress]);

  const startPlayEpisode = useCallback(
    (episode: XtreamEpisode, startPosition?: number) => {
      const streamUrl = getSeriesStreamUrl(episode.id, episode.container_extension);
      navigation.navigate('Player', {
        streamUrl,
        title: episode.title,
        type: 'series',
        streamId: Number(episode.id),
        seriesId: item.series_id,
        seasonNumber: episode.season,
        startPosition,
      });
    },
    [navigation, getSeriesStreamUrl, item.series_id],
  );

  const handlePlayEpisode = useCallback(
    (episode: XtreamEpisode) => {
      const progress = episodeProgress[Number(episode.id)];
      if (progress && progress.position_seconds > 30 && !progress.completed) {
        setPendingEpisode(episode);
        setShowResumeDialog(true);
      } else {
        startPlayEpisode(episode);
      }
    },
    [episodeProgress, startPlayEpisode],
  );

  if (!isFocused) return null;

  return (
    <View style={styles.container}>
      <ResumeDialog
        visible={showResumeDialog}
        position={pendingEpisode ? (episodeProgress[Number(pendingEpisode.id)]?.position_seconds ?? 0) : 0}
        duration={pendingEpisode ? (episodeProgress[Number(pendingEpisode.id)]?.duration_seconds ?? undefined) : undefined}
        onResume={() => {
          setShowResumeDialog(false);
          if (pendingEpisode) {
            startPlayEpisode(pendingEpisode, episodeProgress[Number(pendingEpisode.id)]?.position_seconds);
            setPendingEpisode(null);
          }
        }}
        onStartOver={() => {
          setShowResumeDialog(false);
          if (pendingEpisode) {
            startPlayEpisode(pendingEpisode, 0);
            setPendingEpisode(null);
          }
        }}
        onDismiss={() => {
          setShowResumeDialog(false);
          setPendingEpisode(null);
        }}
      />
      <ImageBackground source={{ uri: item.cover }} style={styles.backdrop} blurRadius={5}>
        <LinearGradient colors={['rgba(0,0,0,0.2)', 'rgba(0,0,0,0.8)', colors.background]} style={styles.gradient}>
          {Platform.OS === 'web' && (
            <FocusablePressable
              onSelect={() => navigation.goBack()}
              style={({ isFocused: f }) => [styles.backButton, f && styles.backButtonFocused]}
            >
              <Icon name="ArrowLeft" size={scaledPixels(22)} color={colors.text} />
            </FocusablePressable>
          )}
          <View style={styles.content}>
            <View style={styles.header}>
              <View style={styles.mainInfo}>
                <Text style={styles.title}>{item.name}</Text>
                <View style={styles.metaRow}>
                  {item.release_date && <Text style={styles.metaText}>{item.release_date.split('-')[0]}</Text>}
                  <Text style={styles.rating}>★ {item.rating}</Text>
                </View>
                <Text style={styles.plot} numberOfLines={3}>
                  {item.plot}
                </Text>
              </View>
            </View>

            <View style={styles.navigationSection}>
              <FocusGuide style={styles.seasonsColumn} autoFocus>
                <Text style={styles.sectionTitle}>Seasons</Text>
                <ScrollView>
                  {seriesInfo?.seasons.map((season, index) => (
                    <FocusablePressable
                      key={season.season_number}
                      ref={index === 0 ? seasonListRef : undefined}
                      preferredFocus={index === 0}
                      nextFocusRight={firstEpisodeTag}
                      onSelect={() => setSelectedSeason(String(season.season_number))}
                      style={({ isFocused }) => [
                        styles.seasonItem,
                        selectedSeason === String(season.season_number) && styles.seasonItemActive,
                        isFocused && styles.itemFocused,
                      ]}
                    >
                      {({ isFocused }) => (
                        <Text
                          style={[
                            styles.seasonText,
                            selectedSeason === String(season.season_number) && styles.seasonTextActive,
                            isFocused && styles.seasonTextActive,
                          ]}
                        >
                          Season {season.season_number}
                        </Text>
                      )}
                    </FocusablePressable>
                  ))}
                </ScrollView>
              </FocusGuide>

              <FocusGuide style={styles.episodesColumn} autoFocus>
                <Text style={styles.sectionTitle}>Episodes</Text>
                <FlatList
                  data={episodes}
                  keyExtractor={(ep) => String(ep.id)}
                  renderItem={({ item: ep, index }) => (
                    <FocusablePressable
                      ref={index === 0 ? firstEpisodeRef : undefined}
                      nextFocusLeft={firstSeasonTag}
                      onSelect={() => handlePlayEpisode(ep)}
                      style={({ isFocused }) => [
                        styles.episodeItem,
                        isFocused && styles.itemFocused,
                        { width: width - scaledPixels(450) },
                      ]}
                    >
                      <View style={styles.episodeMain}>
                        <Text style={styles.episodeNumber}>{ep.episode_num}</Text>
                        <View style={styles.episodeImageWrapper}>
                          <Image
                            source={{ uri: ep.info?.movie_image || item.cover }}
                            style={styles.episodeImage}
                            resizeMode="cover"
                          />
                          {(() => {
                            const prog = episodeProgress[Number(ep.id)];
                            if (!prog || !prog.duration_seconds) return null;
                            const pct = Math.min(prog.position_seconds / prog.duration_seconds, 1);
                            return (
                              <View style={styles.progressBarBg}>
                                <View style={[styles.progressBarFill, { width: `${Math.round(pct * 100)}%` as any }]} />
                              </View>
                            );
                          })()}
                        </View>
                        <View style={styles.episodeInfo}>
                          <Text style={styles.episodeTitle} numberOfLines={1}>
                            {ep.title}
                          </Text>
                          <View style={styles.metaRow}>
                            {ep.info?.rating && (
                              <Text style={styles.metaRating}>{`★ ${ep.info.rating}`}</Text>
                            )}
                            {ep.info?.release_date && (
                              <Text style={styles.metaText}>{ep.info.release_date.split('-')[0]}</Text>
                            )}
                            {ep.info?.duration && <Text style={styles.metaText}>{ep.info.duration}</Text>}
                          </View>
                          <Text style={styles.episodePlot} numberOfLines={3}>
                            {ep.info?.plot || 'No description available for this episode.'}
                          </Text>
                        </View>
                        <Icon name="ChevronRight" size={scaledPixels(24)} color={colors.text} />
                      </View>
                    </FocusablePressable>
                  )}
                />
              </FocusGuide>
            </View>
          </View>
        </LinearGradient>
      </ImageBackground>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  backdrop: {
    flex: 1,
  },
  gradient: {
    flex: 1,
    paddingHorizontal: scaledPixels(80),
    paddingTop: scaledPixels(40),
  },
  backButton: {
    position: 'absolute',
    top: scaledPixels(20),
    left: scaledPixels(20),
    padding: scaledPixels(10),
    borderRadius: scaledPixels(50),
    backgroundColor: 'rgba(0,0,0,0.5)',
    zIndex: 10,
  },
  backButtonFocused: {
    backgroundColor: colors.primary,
  },
  content: {
    flex: 1,
  },
  header: {
    marginBottom: scaledPixels(40),
  },
  mainInfo: {
    maxWidth: '70%',
  },
  title: {
    fontSize: scaledPixels(48),
    color: colors.text,
    fontWeight: 'bold',
    marginBottom: scaledPixels(10),
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: scaledPixels(15),
    gap: scaledPixels(20),
  },
  metaText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
  },
  metaRating: {
    color: '#ffcc00',
    fontSize: scaledPixels(18),
    fontWeight: 'bold',
  },
  rating: {
    color: '#ffcc00',
    fontSize: scaledPixels(20),
    fontWeight: 'bold',
  },
  plot: {
    fontSize: scaledPixels(20),
    color: colors.textSecondary,
    lineHeight: scaledPixels(30),
  },
  navigationSection: {
    flex: 1,
    flexDirection: 'row',
    marginTop: scaledPixels(20),
  },
  seasonsColumn: {
    width: scaledPixels(250),
    marginRight: scaledPixels(40),
  },
  episodesColumn: {
    flex: 1,
    overflow: 'hidden',
  },
  sectionTitle: {
    fontSize: scaledPixels(24),
    color: colors.text,
    fontWeight: 'bold',
    marginBottom: scaledPixels(20),
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  seasonItem: {
    paddingVertical: scaledPixels(15),
    paddingHorizontal: scaledPixels(20),
    borderRadius: scaledPixels(8),
    marginBottom: scaledPixels(10),
    backgroundColor: 'rgba(255,255,255,0.05)',
    overflow: 'hidden',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  seasonItemActive: {
    backgroundColor: 'rgba(236, 0, 63, 0.2)',
    borderLeftWidth: 4,
    borderLeftColor: colors.primary,
  },
  seasonText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
  },
  seasonTextActive: {
    color: colors.text,
    fontWeight: 'bold',
  },
  episodeItem: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: scaledPixels(8),
    marginBottom: scaledPixels(10),
    padding: scaledPixels(20),
    borderWidth: 2,
    borderColor: 'transparent',
  },
  itemFocused: {
    borderColor: colors.primary,
  },
  episodeMain: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(20),
    height: scaledPixels(150),
  },
  episodeNumber: {
    fontSize: scaledPixels(24),
    color: colors.text,
    width: scaledPixels(50),
    fontWeight: 'bold',
  },
  episodeInfo: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    flex: 1,
  },
  episodeTitle: {
    fontSize: scaledPixels(24),
    color: colors.textSecondary,
  },
  episodeImageWrapper: {
    position: 'relative',
    width: scaledPixels(200),
    aspectRatio: 3 / 2,
  },
  episodeImage: {
    width: '100%',
    height: '100%',
    borderRadius: scaledPixels(8),
  },
  progressBarBg: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: scaledPixels(4),
    backgroundColor: 'rgba(255,255,255,0.2)',
    borderBottomLeftRadius: scaledPixels(8),
    borderBottomRightRadius: scaledPixels(8),
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: colors.primary,
  },
  episodePlot: {
    fontSize: scaledPixels(20),
    color: colors.text,
  },
  buttonFocused: {
    borderWidth: 2,
    borderColor: colors.text,
    transform: [{ scale: 1.05 }],
  },
  buttonText: {
    color: colors.text,
    fontSize: scaledPixels(20),
    fontWeight: 'bold',
    marginLeft: scaledPixels(10),
  },
});
