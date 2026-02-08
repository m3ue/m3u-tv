import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { SpatialNavigationNode, SpatialNavigationScrollView, SpatialNavigationVirtualizedList, DefaultFocus } from 'react-tv-space-navigation';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { LiveTVCard } from '../components/LiveTVCard';
import { MovieCard } from '../components/MovieCard';
import { SeriesCard } from '../components/SeriesCard';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamVodStream, XtreamSeries } from '../types/xtream';

export function HomeScreen({ navigation }: DrawerScreenPropsType<'Home'>) {
  const isFocused = useIsFocused();
  useEffect(() => { console.log(`[HomeScreen] isFocused: ${isFocused}`); }, [isFocused]);
  const { isConfigured, isLoading, loadSavedCredentials, fetchLiveStreams, fetchVodStreams, fetchSeries } = useXtream();
  const [liveStreams, setLiveStreams] = useState<XtreamLiveStream[]>([]);
  const [vodStreams, setVodStreams] = useState<XtreamVodStream[]>([]);
  const [seriesList, setSeriesList] = useState<XtreamSeries[]>([]);
  const [contentLoading, setContentLoading] = useState(false);

  useEffect(() => {
    loadSavedCredentials();
  }, [loadSavedCredentials]);

  useEffect(() => {
    if (isConfigured) {
      loadContent();
    }
  }, [isConfigured]);

  const loadContent = async () => {
    setContentLoading(true);
    const [live, vod, series] = await Promise.all([
      fetchLiveStreams(),
      fetchVodStreams(),
      fetchSeries(),
    ]);
    setLiveStreams(live);
    setVodStreams(vod);
    setSeriesList(series);
    setContentLoading(false);
  };

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
        <SpatialNavigationNode orientation="horizontal">
          <DefaultFocus>
            <FocusablePressable
              style={({ isFocused }) => [
                styles.settingsButton,
                isFocused && styles.buttonFocused,
              ]}
              onSelect={() => navigation.navigate('Settings')}
            >
              {({ isFocused }) => (
                <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>
                  Go to Settings
                </Text>
              )}
            </FocusablePressable>
          </DefaultFocus>
        </SpatialNavigationNode>
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

  if (!isFocused) return null;

  return (
    <SpatialNavigationNode>
      <SpatialNavigationScrollView offsetFromStart={scaledPixels(100)} contentContainerStyle={{ paddingVertical: scaledPixels(40) }}>
        {/* Live TV Row */}
        {liveStreams.length > 0 && (
          <View style={styles.rowContainer}>
            <Text style={styles.rowTitle}>Live TV</Text>
            <View style={styles.liveTvRowList}>
              <SpatialNavigationVirtualizedList
                data={liveStreams}
                renderItem={({ item }: { item: XtreamLiveStream }) => (
                  <LiveTVCard item={item} />
                )}
                itemSize={scaledPixels(224)}
                orientation="horizontal"
              />
            </View>
          </View>
        )}

        {/* Movies Row */}
        {vodStreams.length > 0 && (
          <View style={styles.rowContainer}>
            <Text style={styles.rowTitle}>Movies</Text>
            <View style={styles.posterRowList}>
              <SpatialNavigationVirtualizedList
                data={vodStreams}
                renderItem={({ item }: { item: XtreamVodStream }) => (
                  <MovieCard item={item} />
                )}
                itemSize={scaledPixels(224)}
                orientation="horizontal"
              />
            </View>
          </View>
        )}

        {/* Series Row */}
        {seriesList.length > 0 && (
          <View style={styles.rowContainer}>
            <Text style={styles.rowTitle}>Series</Text>
            <View style={styles.posterRowList}>
              <SpatialNavigationVirtualizedList
                data={seriesList}
                renderItem={({ item }: { item: XtreamSeries }) => (
                  <SeriesCard item={item} />
                )}
                itemSize={scaledPixels(224)}
                orientation="horizontal"
              />
            </View>
          </View>
        )}
      </SpatialNavigationScrollView>
    </SpatialNavigationNode>
  );
}

const styles = StyleSheet.create({
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
  },
  rowTitle: {
    color: colors.text,
    fontSize: scaledPixels(32),
    fontWeight: 'bold',
    marginBottom: scaledPixels(15),
    marginLeft: scaledPixels(10),
  },
  liveTvRowList: {
    height: scaledPixels(224),
  },
  posterRowList: {
    height: scaledPixels(390),
  },
});
