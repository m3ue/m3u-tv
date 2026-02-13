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
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamSeriesInfo, XtreamEpisode } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';

export const SeriesDetailsScreen = ({ route, navigation }: RootStackScreenProps<'SeriesDetails'>) => {
  const isFocused = useIsFocused();
  const { item } = route.params;
  const seasonListRef = useRef<FocusablePressableRef>(null);
  const { fetchSeriesInfo, getSeriesStreamUrl } = useXtream();
  const [seriesInfo, setSeriesInfo] = useState<XtreamSeriesInfo | null>(null);
  const [selectedSeason, setSelectedSeason] = useState<string | null>(null);

  const { width } = useWindowDimensions();

  useEffect(() => {
    if (isFocused && seriesInfo?.seasons && seriesInfo.seasons.length > 0) {
      seasonListRef.current?.focus();
    }
  }, [isFocused, seriesInfo]);

  useEffect(() => {
    const loadInfo = async () => {
      try {
        const info = await fetchSeriesInfo(item.series_id);
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

  const episodes = seriesInfo?.episodes[selectedSeason || ''] || [];

  const handlePlayEpisode = useCallback(
    (episode: XtreamEpisode) => {
      const streamUrl = getSeriesStreamUrl(episode.id, episode.container_extension);
      navigation.navigate('Player', {
        streamUrl,
        title: episode.title,
        type: 'series',
      });
    },
    [navigation, getSeriesStreamUrl],
  );

  if (!isFocused) return null;

  return (
    <View style={styles.container}>
      <ImageBackground source={{ uri: item.cover }} style={styles.backdrop} blurRadius={5}>
        <LinearGradient colors={['rgba(0,0,0,0.2)', 'rgba(0,0,0,0.8)', colors.background]} style={styles.gradient}>
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
              <View style={styles.seasonsColumn}>
                <Text style={styles.sectionTitle}>Seasons</Text>
                <ScrollView>
                  {seriesInfo?.seasons.map((season, index) => (
                    <FocusablePressable
                      key={season.season_number}
                      ref={index === 0 ? seasonListRef : undefined}
                      preferredFocus={index === 0}
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
              </View>

              <View style={styles.episodesColumn}>
                <Text style={styles.sectionTitle}>Episodes</Text>
                <FlatList
                  data={episodes}
                  keyExtractor={(ep) => String(ep.id)}
                  renderItem={({ item: ep }) => (
                    <FocusablePressable
                      onSelect={() => handlePlayEpisode(ep)}
                      style={({ isFocused }) => [
                        styles.episodeItem,
                        isFocused && styles.itemFocused,
                        { width: width - scaledPixels(450) },
                      ]}
                    >
                      <View style={styles.episodeMain}>
                        <Text style={styles.episodeNumber}>{ep.episode_num}</Text>
                        <Image
                          source={{ uri: ep.info?.movie_image || item.cover }}
                          style={styles.episodeImage}
                          resizeMode="cover"
                        />
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
              </View>
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
  episodeImage: {
    width: scaledPixels(200),
    aspectRatio: 3 / 2,
    borderRadius: scaledPixels(8),
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
