import React, { useEffect, useState, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, Image, ImageBackground, ScrollView, Platform, StatusBar } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { useViewer } from '../context/ViewerContext';
import { colors } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamVodInfo, WatchProgress } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';
import ResumeDialog from '../components/ResumeDialog';

export const MovieDetailsScreen = ({ route, navigation }: RootStackScreenProps<'Details'>) => {
  const isFocused = useIsFocused();
  const { item } = route.params;
  const playButtonRef = useRef<FocusablePressableRef>(null);
  const { fetchVodInfo, getVodStreamUrl, isM3UEditor } = useXtream();
  const { activeViewer, getProgress } = useViewer();
  const [movieInfo, setMovieInfo] = useState<XtreamVodInfo | null>(null);
  const [watchProgress, setWatchProgress] = useState<WatchProgress | null>(null);
  const [showResumeDialog, setShowResumeDialog] = useState(false);

  useEffect(() => {
    if (isFocused) {
      playButtonRef.current?.focus();
    }
  }, [isFocused]);

  useEffect(() => {
    const loadInfo = async () => {
      try {
        const info = await fetchVodInfo(item.stream_id);
        setMovieInfo(info);
      } catch (error) {
        console.error('Failed to fetch movie info:', error);
      } finally {
        // Do something if needed after fetching info (e.g., hide loading state)
      }
    };
    loadInfo();
  }, [item.stream_id]);

  // Load watch progress when connected to m3u-editor
  useEffect(() => {
    if (!isM3UEditor || !activeViewer) return;
    getProgress('vod', item.stream_id).then((progress) => {
      if (progress && progress.position_seconds > 30) {
        setWatchProgress(progress);
      }
    });
  }, [isM3UEditor, activeViewer, item.stream_id, getProgress]);

  const startPlay = useCallback(
    (resumePosition?: number) => {
      const streamUrl = getVodStreamUrl(item.stream_id, item.container_extension);
      navigation.navigate('Player', {
        streamUrl,
        title: item.name,
        type: 'vod',
        streamId: item.stream_id,
        startPosition: resumePosition,
      });
    },
    [item, navigation, getVodStreamUrl],
  );

  const handlePlay = useCallback(() => {
    if (watchProgress && watchProgress.position_seconds > 30) {
      setShowResumeDialog(true);
    } else {
      startPlay();
    }
  }, [watchProgress, startPlay]);

  const info = movieInfo?.info;
  const backdrop = info?.backdrop_path?.[0];

  if (!isFocused) return null;

  return (
    <View style={styles.container}>
      <ResumeDialog
        visible={showResumeDialog}
        position={watchProgress?.position_seconds ?? 0}
        duration={watchProgress?.duration_seconds}
        onResume={() => {
          setShowResumeDialog(false);
          startPlay(watchProgress?.position_seconds);
        }}
        onStartOver={() => {
          setShowResumeDialog(false);
          startPlay(0);
        }}
        onDismiss={() => setShowResumeDialog(false)}
      />
      <ImageBackground source={{ uri: backdrop }} style={styles.backdrop}>
        <LinearGradient colors={['rgba(0,0,0,0.2)', 'rgba(0,0,0,0.8)', colors.background]} style={styles.gradient}>
          <FocusablePressable
            onSelect={() => navigation.goBack()}
            style={({ isFocused: f }) => [styles.backButton, f && styles.backButtonFocused]}
          >
            <Icon name="ArrowLeft" size={scaledPixels(22)} color={colors.text} />
          </FocusablePressable>
          <ScrollView contentContainerStyle={styles.scrollContent}>
            <View style={styles.header}>
              <Image source={{ uri: item.stream_icon }} style={styles.poster} resizeMode="cover" />
              <View style={styles.mainInfo}>
                <Text style={styles.title}>{item.name}</Text>

                <View style={styles.metaRow}>
                  {info?.release_date && <Text style={styles.metaText}>{info.release_date.split('-')[0]}</Text>}
                  {info?.duration && <Text style={styles.metaText}>{info.duration}</Text>}
                  {info?.rating && <Text style={styles.rating}>★ {info.rating}</Text>}
                </View>

                {info?.genre && <Text style={styles.genre}>{info.genre}</Text>}

                <View style={styles.buttonRow}>
                  <FocusablePressable
                    ref={playButtonRef}
                    preferredFocus
                    onSelect={handlePlay}
                    style={({ isFocused: f }) => [styles.playButton, f && styles.buttonFocused]}
                  >
                    <Icon name="Play" size={scaledPixels(24)} color={colors.text} />
                    <Text style={styles.buttonText}>
                      {watchProgress && watchProgress.position_seconds > 30 ? 'Resume' : 'Watch Now'}
                    </Text>
                  </FocusablePressable>
                </View>
              </View>
            </View>

            <View style={styles.detailsSection}>
              <Text style={styles.sectionTitle}>Plot Summary</Text>
              <Text style={styles.plot}>{info?.plot || 'No summary available.'}</Text>

              {info?.director && (
                <View style={styles.detailItem}>
                  <Text style={styles.detailLabel}>Director</Text>
                  <Text style={styles.detailValue}>{info.director}</Text>
                </View>
              )}

              {info?.actors && (
                <View style={styles.detailItem}>
                  <Text style={styles.detailLabel}>Cast</Text>
                  <Text style={styles.detailValue}>{info.actors}</Text>
                </View>
              )}
            </View>
          </ScrollView>
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
    paddingHorizontal: Platform.isTV || Platform.OS === 'web' ? scaledPixels(80) : scaledPixels(20),
    paddingTop: Platform.isTV || Platform.OS === 'web' ? scaledPixels(60) : (StatusBar.currentHeight ?? 0) + scaledPixels(10),
  },
  backButton: {
    padding: scaledPixels(10),
    borderRadius: scaledPixels(50),
    backgroundColor: 'rgba(0,0,0,0.5)',
    zIndex: 10,
    alignSelf: 'flex-start',
    marginBottom: scaledPixels(10),
  },
  backButtonFocused: {
    backgroundColor: colors.primary,
  },
  scrollContent: {
    paddingBottom: scaledPixels(100),
  },
  header: {
    flexDirection: Platform.isTV || Platform.OS === 'web' ? 'row' : 'column',
    alignItems: Platform.isTV || Platform.OS === 'web' ? 'flex-start' : 'center',
    marginBottom: scaledPixels(40),
  },
  poster: {
    width: Platform.isTV || Platform.OS === 'web' ? scaledPixels(300) : scaledPixels(200),
    height: Platform.isTV || Platform.OS === 'web' ? scaledPixels(450) : scaledPixels(300),
    borderRadius: scaledPixels(12),
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  mainInfo: {
    flex: Platform.isTV || Platform.OS === 'web' ? 1 : undefined,
    marginLeft: Platform.isTV || Platform.OS === 'web' ? scaledPixels(40) : 0,
    marginTop: Platform.isTV || Platform.OS === 'web' ? 0 : scaledPixels(20),
    justifyContent: 'center',
    alignItems: Platform.isTV || Platform.OS === 'web' ? 'flex-start' : 'center',
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
    marginBottom: scaledPixels(10),
  },
  metaText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    marginRight: scaledPixels(20),
  },
  rating: {
    color: '#ffcc00',
    fontSize: scaledPixels(20),
    fontWeight: 'bold',
  },
  genre: {
    color: colors.text,
    fontSize: scaledPixels(18),
    marginBottom: scaledPixels(30),
  },
  buttonRow: {
    flexDirection: 'row',
  },
  playButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.1)',
    paddingVertical: scaledPixels(15),
    paddingHorizontal: scaledPixels(30),
    borderRadius: scaledPixels(8),
  },
  resumeButton: {
    borderWidth: 1,
    borderColor: colors.primary,
  },
  buttonFocused: {
    backgroundColor: colors.primary,
    transform: [{ scale: 1.05 }],
  },
  buttonText: {
    color: colors.text,
    fontSize: scaledPixels(20),
    fontWeight: 'bold',
    marginLeft: scaledPixels(10),
  },
  detailsSection: {
    marginTop: scaledPixels(40),
  },
  sectionTitle: {
    fontSize: scaledPixels(28),
    color: colors.text,
    fontWeight: 'bold',
    marginBottom: scaledPixels(15),
  },
  plot: {
    fontSize: scaledPixels(20),
    color: colors.textSecondary,
    lineHeight: scaledPixels(30),
    marginBottom: scaledPixels(30),
  },
  detailItem: {
    marginBottom: scaledPixels(15),
  },
  detailLabel: {
    fontSize: scaledPixels(18),
    color: colors.textTertiary,
    marginBottom: scaledPixels(5),
  },
  detailValue: {
    fontSize: scaledPixels(20),
    color: colors.text,
  },
});
