import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, Dimensions, ActivityIndicator } from 'react-native';
import { useEpg, Epg, Layout } from '@nessprim/planby-native-pro';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamEpgListing } from '../types/xtream';
import { SpatialNavigationNode, DefaultFocus } from 'react-tv-space-navigation';
import { FocusablePressable } from '../components/FocusablePressable';
import { scaledPixels } from '../hooks/useScale';

const { width, height } = Dimensions.get('window');

interface Channel {
  uuid: string;
  logo: string;
}

interface EpgProgram {
  id: string;
  channelUuid: string;
  title: string;
  description: string;
  since: string;
  till: string;
  image: string;
}

export function EPGScreen({ navigation }: DrawerScreenPropsType<'EPG'>) {
  const { isConfigured, liveStreams, fetchLiveStreams } = useXtream();
  const [isLoading, setIsLoading] = useState(true);
  const [epgData, setEpgData] = useState<EpgProgram[]>([]);
  const [channels, setChannels] = useState<Channel[]>([]);

  useEffect(() => {
    const loadEPG = async () => {
      if (!isConfigured) return;

      setIsLoading(true);
      try {
        // Fetch live streams if not already loaded
        let streams = liveStreams;
        if (streams.length === 0) {
          streams = await fetchLiveStreams();
        }

        // Take first 20 channels for EPG display
        const channelsToShow = streams.slice(0, 20);

        // Transform channels for Planby
        const planbyChannels: Channel[] = channelsToShow.map((stream: XtreamLiveStream) => ({
          uuid: String(stream.stream_id),
          logo: stream.stream_icon || 'https://via.placeholder.com/50',
        }));
        setChannels(planbyChannels);

        // Fetch EPG data for each channel
        const epgPromises = channelsToShow.map(async (stream: XtreamLiveStream) => {
          try {
            const epg = await xtreamService.getSimpleDataTable(stream.stream_id);
            return { streamId: stream.stream_id, listings: epg.epg_listings || [] };
          } catch {
            return { streamId: stream.stream_id, listings: [] };
          }
        });

        const epgResults = await Promise.all(epgPromises);

        // Transform EPG data for Planby
        const transformedEpg: EpgProgram[] = [];
        epgResults.forEach(({ streamId, listings }) => {
          listings.forEach((listing: XtreamEpgListing) => {
            const startDate = new Date(listing.start_timestamp * 1000);
            const endDate = new Date(listing.stop_timestamp * 1000);

            transformedEpg.push({
              id: listing.id,
              channelUuid: String(streamId),
              title: listing.title,
              description: listing.description || '',
              since: startDate.toISOString(),
              till: endDate.toISOString(),
              image: 'https://via.placeholder.com/100',
            });
          });
        });

        setEpgData(transformedEpg);
      } catch (error) {
        console.error('Failed to load EPG:', error);
      } finally {
        setIsLoading(false);
      }
    };

    loadEPG();
  }, [isConfigured, fetchLiveStreams, liveStreams]);

  const memoizedChannels = useMemo(() => channels, [channels]);
  const memoizedEpg = useMemo(() => epgData, [epgData]);

  // Calculate start and end dates for today
  const today = new Date();
  const startDate = new Date(today);
  startDate.setHours(0, 0, 0, 0);
  const endDate = new Date(today);
  endDate.setHours(23, 59, 59, 999);

  const { getEpgProps, getLayoutProps } = useEpg({
    channels: memoizedChannels,
    epg: memoizedEpg,
    startDate: startDate.toISOString(),
    endDate: endDate.toISOString(),
    width: width,
    height: height - scaledPixels(120),
  });

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
      </View>
    );
  }

  if (isLoading) {
    return (
      <View style={styles.centerContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Loading EPG data...</Text>
      </View>
    );
  }

  if (channels.length === 0) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>No channels available</Text>
      </View>
    );
  }

  return (
    <SpatialNavigationNode>
      <View style={styles.container}>
        <Epg {...getEpgProps()}>
          <Layout {...getLayoutProps()} />
        </Epg>
      </View>
    </SpatialNavigationNode>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  centerContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
    padding: scaledPixels(spacing.lg),
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(typography.fontSize.md),
    marginTop: scaledPixels(spacing.md),
  },
  message: {
    color: colors.textSecondary,
    fontSize: scaledPixels(typography.fontSize.lg),
    textAlign: 'center',
  },
});
