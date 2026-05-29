import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, ActivityIndicator, ScrollView, FlatList, Image, Platform } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { useViewer } from '../context/ViewerContext';
import { useMenu } from '../context/MenuContext';
import { favoritesService } from '../services/FavoritesService';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LiveTVCard } from '../components/LiveTVCard';
import { MovieCard } from '../components/MovieCard';
import { SeriesCard } from '../components/SeriesCard';
import ResumeDialog from '../components/ResumeDialog';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamVodStream, XtreamSeries, WatchProgress } from '../types/xtream';

export function HomeScreen({ navigation }: DrawerScreenPropsType<'Home'>) {
  const { isConfigured, isLoading, isM3UEditor, loadSavedCredentials, fetchLiveStreams, fetchVodStreams, fetchSeries, vodCategories, getVodStreamUrl, getSeriesStreamUrl } = useXtream();
  const { activeViewer, getRecentlyWatched } = useViewer();
  const { isSidebarActive, setSidebarActive } = useMenu();
  const [liveStreams, setLiveStreams] = useState<XtreamLiveStream[]>([]);
  const [vodStreams, setVodStreams] = useState<XtreamVodStream[]>([]);
  const [seriesList, setSeriesList] = useState<XtreamSeries[]>([]);
  const [contentLoading, setContentLoading] = useState(false);
  const [recentlyWatched, setRecentlyWatched] = useState<WatchProgress[]>([]);
  const [favoriteStreams, setFavoriteStreams] = useState<XtreamLiveStream[]>([]);
  const [showResumeDialog, setShowResumeDialog] = useState(false);
  const [pendingWatch, setPendingWatch] = useState<{ progress: WatchProgress; vod?: XtreamVodStream; series?: XtreamSeries } | null>(null);

  useEffect(() => {
    loadSavedCredentials();
  }, [loadSavedCredentials]);

  useEffect(() => {
    if (isConfigured) {
      loadContent();
    }
  }, [isConfigured]);

  useEffect(() => {
    if (isM3UEditor && activeViewer) {
      getRecentlyWatched(undefined, 10).then(setRecentlyWatched);
    }
  }, [isM3UEditor, activeViewer, getRecentlyWatched]);

  const loadContent = async () => {
    setContentLoading(true);
    const [live, vod, series] = await Promise.all([fetchLiveStreams(), fetchVodStreams(), fetchSeries()]);
    setLiveStreams(live);
    let finalVod = vod;
    if (finalVod.length === 0 && vodCategories.length > 0) {
      const all = await Promise.all(vodCategories.map((c) => fetchVodStreams(c.category_id)));
      const seen = new Set<number>();
      finalVod = all.flat().filter((s) => {
        if (seen.has(s.stream_id)) return false;
        seen.add(s.stream_id);
        return true;
      });
    }
    setVodStreams(finalVod);
    setSeriesList(series);
    await favoritesService.load();
    const favIds = new Set(favoritesService.getAll());
    setFavoriteStreams(live.filter((s) => favIds.has(s.stream_id)));
    setContentLoading(false);
  };

  const handleContinueWatching = useCallback((item: WatchProgress) => {
    const vod = item.content_type === 'vod'
      ? vodStreams.find((v) => v.stream_id === item.stream_id)
      : undefined;
    const series = item.content_type === 'episode' && item.series_id
      ? seriesList.find((s) => s.series_id === item.series_id)
      : undefined;
    if (!vod && !series) return;

    setPendingWatch({ progress: item, vod, series });
    setShowResumeDialog(true);
  }, [vodStreams, seriesList]);

  const playContinueWatching = useCallback((startPosition?: number) => {
    if (!pendingWatch) return;
    const { progress, vod } = pendingWatch;
    if (progress.content_type === 'vod' && vod) {
      const streamUrl = getVodStreamUrl(vod.stream_id, vod.container_extension);
      navigation.navigate('Player', {
        streamUrl,
        title: vod.name,
        type: 'vod',
        streamId: vod.stream_id,
        startPosition,
      });
    } else if (progress.content_type === 'episode') {
      const streamUrl = getSeriesStreamUrl(String(progress.stream_id));
      const title = pendingWatch.series?.name
        ? `${pendingWatch.series.name} - S${progress.season_number ?? '?'}`
        : `Episode ${progress.stream_id}`;
      navigation.navigate('Player', {
        streamUrl,
        title,
        type: 'series',
        streamId: progress.stream_id,
        seriesId: progress.series_id,
        seasonNumber: progress.season_number,
        startPosition,
      });
    }
    setShowResumeDialog(false);
    setPendingWatch(null);
  }, [pendingWatch, navigation, getVodStreamUrl, getSeriesStreamUrl]);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Connecting...</Text>
      </View>
    );
  }

  if (!isConfigured) {
    return (
      <View style={styles.welcomeContainer}>
        <Text style={styles.title}>Welcome to M3U TV</Text>
        <Text style={styles.subtitle}>Connect to your Xtream service to get started</Text>
        <FocusablePressable
          preferredFocus
          style={({ isFocused }) => [styles.settingsButton, isFocused && styles.buttonFocused]}
          onSelect={() => navigation.navigate('Settings')}
        >
          {({ isFocused }) => <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>Go to Settings</Text>}
        </FocusablePressable>
      </View>
    );
  }

  if (contentLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Loading content...</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
      <ResumeDialog
        visible={showResumeDialog}
        position={pendingWatch?.progress.position_seconds ?? 0}
        duration={pendingWatch?.progress.duration_seconds}
        onResume={() => playContinueWatching(pendingWatch?.progress.position_seconds)}
        onStartOver={() => playContinueWatching(0)}
        onDismiss={() => {
          setShowResumeDialog(false);
          setPendingWatch(null);
        }}
      />
      {/* Continue Watching Row */}
      {isM3UEditor && activeViewer && (() => {
        const watchable = recentlyWatched
          .filter((w) => w.content_type !== 'live')
          .map((prog) => {
            const vod = prog.content_type === 'vod'
              ? vodStreams.find((v) => v.stream_id === prog.stream_id)
              : undefined;
            const series = prog.content_type === 'episode' && prog.series_id
              ? seriesList.find((s) => s.series_id === prog.series_id)
              : undefined;
            if (!vod && !series) return null;
            return { prog, vod, series };
          })
          .filter(Boolean) as { prog: WatchProgress; vod?: XtreamVodStream; series?: XtreamSeries }[];

        return (
          <View style={styles.rowContainer}>
            <Text style={styles.rowTitle}>Continue Watching</Text>
            {watchable.length > 0 ? (
              <View style={styles.continueWatchingList}>
                <FlatList
                  data={watchable}
                  horizontal
                  removeClippedSubviews
                  initialNumToRender={6}
                  style={styles.rowList}
                  contentContainerStyle={Platform.OS === 'web' ? styles.rowListContent : undefined}
                  showsHorizontalScrollIndicator={false}
                  keyExtractor={({ prog }) => `${prog.content_type}-${prog.stream_id}`}
                  renderItem={({ item: { prog, vod, series }, index }) => {
                    const cover = vod?.stream_icon || series?.cover || '';
                    const title = vod?.name || series?.name || `Stream ${prog.stream_id}`;
                    const pct = prog.duration_seconds && prog.duration_seconds > 0
                      ? Math.min(prog.position_seconds / prog.duration_seconds, 1)
                      : 0;
                    return (
                      <FocusablePressable
                        onSelect={() => handleContinueWatching(prog)}
                        onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
                        style={({ isFocused }) => [styles.continueCard, isFocused && styles.continueCardFocused]}
                      >
                        {() => (
                          <View style={styles.continueCardInner}>
                            <Image source={{ uri: cover }} style={styles.continueCover} resizeMode="cover" />
                            {pct > 0 && (
                              <View style={styles.continueProgressBg}>
                                <View style={[styles.continueProgressFill, { width: `${Math.round(pct * 100)}%` as any }]} />
                              </View>
                            )}
                            <Text style={styles.continueTitle} numberOfLines={2}>{title}</Text>
                          </View>
                        )}
                      </FocusablePressable>
                    );
                  }}
                />
              </View>
            ) : (
              <View style={styles.continuePlaceholder}>
                <Image
                  source={require('../../assets/images/logo.png')}
                  style={styles.continuePlaceholderLogoBg}
                  resizeMode="contain"
                />
                <View style={styles.continuePlaceholderAccent} />
                <View style={styles.continuePlaceholderContent}>
                  <Text style={styles.continuePlaceholderTitle}>Nothing here yet</Text>
                  <View style={styles.continuePlaceholderIcons}>
                    <Icon name="Tv" size={scaledPixels(28)} color={colors.textTertiary} />
                    <Icon name="Film" size={scaledPixels(28)} color={colors.textTertiary} />
                    <Icon name="Tv2" size={scaledPixels(28)} color={colors.textTertiary} />
                  </View>
                  <Text style={styles.continuePlaceholderHint}>Start watching content and it will appear here to continue watching later...</Text>
                </View>
              </View>
            )}
          </View>
        );
      })()}

      {/* Favorites Row */}
      {favoriteStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>★ Favorites</Text>
          <View style={styles.liveTvRowList}>
            <FlatList
              data={favoriteStreams}
              renderItem={({ item, index }: { item: XtreamLiveStream; index: number }) => (
                <LiveTVCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              contentContainerStyle={Platform.OS === 'web' ? styles.rowListContent : undefined}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Live TV Row */}
      {liveStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Live TV</Text>
          <View style={styles.liveTvRowList}>
            <FlatList
              data={liveStreams}
              renderItem={({ item, index }: { item: XtreamLiveStream; index: number }) => (
                <LiveTVCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              contentContainerStyle={Platform.OS === 'web' ? styles.rowListContent : undefined}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Movies Row */}
      {vodStreams.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Movies</Text>
          <View style={styles.posterRowList}>
            <FlatList
              data={vodStreams}
              renderItem={({ item, index }: { item: XtreamVodStream; index: number }) => (
                <MovieCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              contentContainerStyle={Platform.OS === 'web' ? styles.rowListContent : undefined}
              keyExtractor={(item) => String(item.stream_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}

      {/* Series Row */}
      {seriesList.length > 0 && (
        <View style={styles.rowContainer}>
          <Text style={styles.rowTitle}>Series</Text>
          <View style={styles.posterRowList}>
            <FlatList
              data={seriesList}
              renderItem={({ item, index }: { item: XtreamSeries; index: number }) => (
                <SeriesCard item={item} onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined} />
              )}
              horizontal
              removeClippedSubviews
              initialNumToRender={6}
              maxToRenderPerBatch={4}
              windowSize={3}
              style={styles.rowList}
              contentContainerStyle={Platform.OS === 'web' ? styles.rowListContent : undefined}
              keyExtractor={(item) => String(item.series_id)}
              showsHorizontalScrollIndicator={false}
            />
          </View>
        </View>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  scrollView: {
    overflow: 'visible',
  },
  scrollContent: {
    paddingVertical: scaledPixels(40),
    overflow: 'visible',
  },
  welcomeContainer: {
    flex: 1,
    backgroundColor: colors.background,
    padding: scaledPixels(40),
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    marginTop: scaledPixels(20),
  },
  title: {
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    color: colors.text,
    textAlign: 'center',
    marginBottom: scaledPixels(8),
  },
  subtitle: {
    fontSize: scaledPixels(24),
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: scaledPixels(60),
  },
  settingsButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: scaledPixels(40),
    paddingVertical: scaledPixels(20),
    borderRadius: scaledPixels(12),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  settingsButtonText: {
    color: colors.textOnPrimary,
    fontSize: scaledPixels(24),
    fontWeight: '600',
  },
  buttonFocused: {
    transform: [{ scale: 1.08 }],
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  buttonTextFocused: {
    color: colors.textOnPrimary,
  },
  rowContainer: {
    marginBottom: scaledPixels(30),
    paddingHorizontal: scaledPixels(20),
    overflow: 'visible',
  },
  rowTitle: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
    marginBottom: scaledPixels(15),
    marginLeft: scaledPixels(10),
  },
  liveTvRowList: {
    height: Platform.OS === 'web' ? scaledPixels(264) : scaledPixels(224),
    overflow: 'visible',
  },
  posterRowList: {
    height: Platform.OS === 'web' ? scaledPixels(430) : scaledPixels(390),
    overflow: 'visible',
  },
  rowList: {
    overflow: 'visible',
  },
  rowListContent: {
    paddingVertical: scaledPixels(20),
  },
  continueWatchingList: {
    height: Platform.OS === 'web' ? scaledPixels(450) : scaledPixels(410),
    overflow: 'visible',
  },
  continueCard: {
    width: scaledPixels(200),
    marginHorizontal: scaledPixels(12),
    borderRadius: scaledPixels(8),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  continueCardInner: {
    borderRadius: scaledPixels(6),
    overflow: 'hidden',
  },
  continueCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  continueCover: {
    width: '100%',
    aspectRatio: 2 / 3,
    borderRadius: scaledPixels(8),
  },
  continueProgressBg: {
    height: scaledPixels(4),
    backgroundColor: 'rgba(255,255,255,0.2)',
    marginTop: scaledPixels(4),
    borderRadius: scaledPixels(2),
    overflow: 'hidden',
  },
  continueProgressFill: {
    height: '100%',
    backgroundColor: colors.primary,
  },
  continueTitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(16),
    marginTop: scaledPixels(6),
    paddingHorizontal: scaledPixels(4),
  },
  continuePlaceholder: {
    height: scaledPixels(180),
    marginHorizontal: scaledPixels(10),
    borderRadius: scaledPixels(16),
    backgroundColor: colors.backgroundElevated,
    overflow: 'hidden',
    flexDirection: 'row',
    alignItems: 'center',
  },
  continuePlaceholderLogoBg: {
    position: 'absolute',
    width: scaledPixels(380),
    height: scaledPixels(380),
    top: -scaledPixels(70),
    right: -scaledPixels(70),
    opacity: 0.07,
  },
  continuePlaceholderAccent: {
    width: scaledPixels(4),
    alignSelf: 'stretch',
    backgroundColor: colors.primary,
    opacity: 0.8,
  },
  continuePlaceholderContent: {
    flex: 1,
    gap: scaledPixels(12),
    paddingLeft: scaledPixels(32),
    paddingRight: scaledPixels(160),
  },
  continuePlaceholderIcons: {
    flexDirection: 'row',
    gap: scaledPixels(16),
    marginBottom: scaledPixels(12),
    opacity: 0.9,
  },
  continuePlaceholderTitle: {
    color: colors.text,
    fontSize: scaledPixels(24),
    fontWeight: '600',
    marginBottom: scaledPixels(8),
  },
  continuePlaceholderHint: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: scaledPixels(17),
    lineHeight: scaledPixels(26),
  },
});
