import React, { useEffect, useMemo, useState } from 'react';
import { View, Text, StyleSheet, Dimensions, ActivityIndicator, useWindowDimensions, Pressable } from 'react-native';
import {
  useEpg,
  Epg,
  Layout,
  ProgramBox,
  ProgramContent,
  useProgram,
  ProgramItem as PlanbyProgramItem
} from '@nessprim/planby-native-pro';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamEpgListing } from '../types/xtream';
import { SpatialNavigationNode, DefaultFocus } from 'react-tv-space-navigation';
import { FocusablePressable } from '../components/FocusablePressable';
import { scaledPixels } from '../hooks/useScale';

interface Channel {
  uuid: string;
  title: string;
  logo: string;
  displayOrder?: number;
  groupTree?: boolean;
  parentChannelUuid?: string | null;
}

interface EpgProgram {
  id: string;
  channelUuid: string;
  title: string;
  description: string;
  since: string;
  till: string;
  image: string;
  status?: string;
  images?: string[];
  utc?: boolean;
  timeZone?: string;
}

const formatISO = (date: Date) => {
  const pad = (n: number) => n.toString().padStart(2, '0');
  const yyyy = date.getFullYear();
  const mm = pad(date.getMonth() + 1);
  const dd = pad(date.getDate());
  const hh = pad(date.getHours());
  const min = pad(date.getMinutes());
  const ss = pad(date.getSeconds());
  return `${yyyy}-${mm}-${dd}T${hh}:${min}:${ss}`;
};

const decodeBase64 = (str: string) => {
  try {
    // Basic Base64 decoding for React Native
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
    let output = '';
    str = str.replace(/[^A-Za-z0-9+/=]/g, '');
    for (let i = 0; i < str.length;) {
      const enc1 = chars.indexOf(str.charAt(i++));
      const enc2 = chars.indexOf(str.charAt(i++));
      const enc3 = chars.indexOf(str.charAt(i++));
      const enc4 = chars.indexOf(str.charAt(i++));
      const chr1 = (enc1 << 2) | (enc2 >> 4);
      const chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
      const chr3 = ((enc3 & 3) << 6) | enc4;
      output += String.fromCharCode(chr1);
      if (enc3 !== 64) output += String.fromCharCode(chr2);
      if (enc4 !== 64) output += String.fromCharCode(chr3);
    }
    // Simple UTF-8 decoding
    return decodeURIComponent(escape(output));
  } catch (e) {
    return str; // Return original if decoding fails
  }
};

const ProgramItem = ({ program, isVerticalMode, ...rest }: PlanbyProgramItem) => {
  const { styles, formatTime, set12HoursTimeFormat } = useProgram({
    program,
    isVerticalMode,
    ...rest,
  });

  const { data } = program;
  const { title, since, till } = data;

  return (
    <ProgramBox width={styles.width} style={styles.position}>
      <Pressable focusable style={({ focused }) => [
        {
          flex: 1,
          backgroundColor: focused ? colors.primary : colors.card,
          borderRadius: 4,
          borderWidth: 1,
          borderColor: colors.border,
          margin: 1,
          padding: 4,
          justifyContent: 'center',
        }
      ]}>
        <View>
          <Text
            numberOfLines={2}
            style={{
              color: colors.text,
              fontSize: scaledPixels(20),
              fontWeight: 'bold',
            }}
          >
            {title}
          </Text>
          <Text style={{ color: colors.textSecondary, fontSize: scaledPixels(16), marginTop: 4 }}>
            {formatTime(since, set12HoursTimeFormat()).toLowerCase()} - {formatTime(till, set12HoursTimeFormat()).toLowerCase()}
          </Text>
        </View>
      </Pressable>
    </ProgramBox>
  );
};

function EpgContent({ channels, epgData, startDate, endDate }: {
  channels: Channel[],
  epgData: EpgProgram[],
  startDate: string,
  endDate: string
}) {
  const { width, height } = useWindowDimensions();

  const { getEpgProps, getLayoutProps } = useEpg({
    channels,
    epg: epgData,
    startDate,
    endDate,
    width,
    height: height,
    isBaseTimeFormat: true,
    isCurrentTime: true,
    // sidebarWidth: scaledPixels(260),
    itemHeight: scaledPixels(80),
    itemOverscan: 20,
    fetchZone: {
      enabled: false,
      timeSlots: 3,
      channelsPerSlot: 10,
      onFetchZone: () => { },
    },
  });

  return (
    <Epg {...getEpgProps()}>
      <Layout
        {...getLayoutProps()}
        renderProgram={(props) => <ProgramItem {...props} />}
      />
    </Epg>
  );
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
        const planbyChannels: Channel[] = channelsToShow.map((stream: XtreamLiveStream, index: number) => ({
          uuid: String(stream.stream_id),
          title: stream.name || 'Unknown Channel',
          logo: stream.stream_icon || 'https://via.placeholder.com/50',
          displayOrder: index + 1,
          groupTree: false,
          parentChannelUuid: null,
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
          if (!listings || !Array.isArray(listings)) return;

          listings.forEach((listing: XtreamEpgListing) => {
            if (!listing || !listing.id || !listing.start_timestamp || !listing.stop_timestamp) return;

            const startDateObj = new Date(listing.start_timestamp * 1000);
            const endDateObj = new Date(listing.stop_timestamp * 1000);

            if (isNaN(startDateObj.getTime()) || isNaN(endDateObj.getTime())) return;

            transformedEpg.push({
              id: String(listing.id),
              channelUuid: String(streamId),
              title: decodeBase64(String(listing.title || 'No Title')),
              description: decodeBase64(String(listing.description || '')),
              since: formatISO(startDateObj),
              till: formatISO(endDateObj),
              image: 'https://via.placeholder.com/100',
              status: 'active',
              images: ['https://via.placeholder.com/100'],
              utc: false,
              timeZone: '',
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

  // Calculate start and end dates for the EPG range
  const { startDate, endDate } = useMemo(() => {
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const yyyy = now.getFullYear();
    const mm = pad(now.getMonth() + 1);
    const dd = pad(now.getDate());

    return {
      startDate: `${yyyy}-${mm}-${dd}T00:00:00`,
      endDate: `${yyyy}-${mm}-${dd}T24:00:00`
    };
  }, []);

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
        <EpgContent
          channels={channels}
          epgData={epgData}
          startDate={startDate}
          endDate={endDate}
        />
      </View>
    </SpatialNavigationNode>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'transparent',
    padding: scaledPixels(40),
    justifyContent: 'center',
    alignItems: 'center',
  },
  centerContainer: {
    flex: 1,
    backgroundColor: 'transparent',
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
    fontSize: scaledPixels(24),
    textAlign: 'center',
  },
});
