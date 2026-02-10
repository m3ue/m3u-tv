import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, Text, StyleSheet, useWindowDimensions, Pressable } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import {
  useEpg,
  Epg,
  Layout,
  ProgramBox,
  ProgramContent,
  ProgramFlex,
  ProgramStack,
  ProgramTitle,
  ProgramText,
  ProgramImage,
  useProgram,
  ProgramItem as PlanbyProgramItem,
} from '@nessprim/planby-native-pro';
import { useXtream } from '../context/XtreamContext';
import { xtreamService } from '../services/XtreamService';
import { colors, spacing, typography, epgTheme } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { XtreamLiveStream, XtreamEpgListing } from '../types/xtream';
import { SpatialNavigationNode, DefaultFocus, SpatialNavigationScrollView } from 'react-tv-space-navigation';
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
    for (let i = 0; i < str.length; ) {
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

const transformListingsToEpgPrograms = (streamId: string | number, listings: XtreamEpgListing[]): EpgProgram[] => {
  const programs: EpgProgram[] = [];
  if (!listings || !Array.isArray(listings)) return programs;

  listings.forEach((listing) => {
    if (!listing || !listing.id || !listing.start_timestamp || !listing.stop_timestamp) return;

    const startDateObj = new Date(Number(listing.start_timestamp) * 1000);
    const endDateObj = new Date(Number(listing.stop_timestamp) * 1000);

    if (isNaN(startDateObj.getTime()) || isNaN(endDateObj.getTime())) return;

    programs.push({
      id: `${streamId}-${listing.id}`,
      channelUuid: String(streamId),
      title: decodeBase64(String(listing.title || 'No Title')),
      description: decodeBase64(String(listing.description || '')),
      since: formatISO(startDateObj),
      till: formatISO(endDateObj),
      image: 'https://via.placeholder.com/100',
    });
  });

  return programs;
};

const getTodayDateStr = () => {
  const now = new Date();
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
};

const ProgramItem = ({ program, isVerticalMode, ...rest }: PlanbyProgramItem) => {
  const { isLive, isMinWidth, styles, formatTime, set12HoursTimeFormat } = useProgram({
    program,
    isVerticalMode,
    ...rest,
  });

  const { data } = program;
  const { image, title, since, till } = data;
  const sinceTime = formatTime(since, set12HoursTimeFormat()).toLowerCase();
  const tillTime = formatTime(till, set12HoursTimeFormat()).toLowerCase();

  return (
    <ProgramBox width={styles.width} style={styles.position}>
      <Pressable focusable>
        {({ focused }) => (
          <ProgramContent
            width={styles.width}
            isLive={isLive}
            style={{ borderWidth: focused ? 2 : 0, borderColor: focused ? '#00bc7d' : 'transparent' }}
          >
            <ProgramFlex>
              {isLive && isMinWidth && <ProgramImage src={image} alt="Preview" />}
              <ProgramStack>
                <ProgramTitle>{title}</ProgramTitle>
                <ProgramText>
                  {sinceTime} - {tillTime}
                </ProgramText>
              </ProgramStack>
            </ProgramFlex>
          </ProgramContent>
        )}
      </Pressable>
    </ProgramBox>
  );
};

function EpgContent({
  channels,
  epgData,
  startDate,
  endDate,
  isLoading,
  onFetchZone,
}: {
  channels: Channel[];
  epgData: EpgProgram[];
  startDate: string;
  endDate: string;
  isLoading: boolean;
  onFetchZone: (data: { since: string; till: string; channelsToFetchData: string[] }) => void;
}) {
  const { width, height } = useWindowDimensions();

  const { getEpgProps, getLayoutProps } = useEpg({
    channels,
    epg: epgData,
    startDate,
    endDate,
    width,
    height,
    theme: epgTheme,
    isBaseTimeFormat: true,
    isCurrentTime: true,
    isInitialScrollToNow: true,
    sidebarWidth: scaledPixels(100),
    itemHeight: scaledPixels(100),
    itemOverscan: 20,
    mode: {
      type: 'day',
      style: 'modern',
    },
    fetchZone: {
      enabled: true,
      timeSlots: 6,
      channelsPerSlot: 10,
      onFetchZone,
    },
  });

  return (
    <Epg {...getEpgProps()} isLoading={isLoading}>
      <Layout {...getLayoutProps()} renderProgram={(props) => <ProgramItem {...props} />} />
    </Epg>
  );
}

export function EPGScreen({ navigation }: DrawerScreenPropsType<'EPG'>) {
  const isFocused = useIsFocused();
  useEffect(() => {
    console.log(`[EPGScreen] isFocused: ${isFocused}`);
  }, [isFocused]);
  const { isConfigured, liveStreams, fetchLiveStreams } = useXtream();
  const [isLoading, setIsLoading] = useState(true);
  const [epgData, setEpgData] = useState<EpgProgram[]>([]);
  const [channels, setChannels] = useState<Channel[]>([]);
  const fetchedStreamIds = useRef<Set<string>>(new Set());

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

        // Transform ALL channels for Planby (EPG data loaded lazily via fetchZone)
        const transformedChannels: Channel[] = streams.map((stream: XtreamLiveStream, index: number) => ({
          uuid: String(stream.stream_id),
          title: stream.name || 'Unknown Channel',
          logo: stream.stream_icon || 'https://via.placeholder.com/50',
          displayOrder: index + 1,
          groupTree: false,
          parentChannelUuid: null,
        }));
        setChannels(transformedChannels);

        // Batch fetch EPG for the first visible channels only
        const initialBatchSize = 10;
        const initialStreamIds = streams.slice(0, initialBatchSize).map((s: XtreamLiveStream) => s.stream_id);

        // Mark as fetched BEFORE the async call to prevent fetchZone race condition
        initialStreamIds.forEach((id) => fetchedStreamIds.current.add(String(id)));

        const dateStr = getTodayDateStr();
        const batchResult = await xtreamService.getEpgBatch(initialStreamIds, dateStr);

        const transformedEpg: EpgProgram[] = [];
        Object.entries(batchResult).forEach(([streamId, data]) => {
          transformedEpg.push(...transformListingsToEpgPrograms(streamId, data.epg_listings || []));
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

  const handleFetchZone = useCallback(async (data: { since: string; till: string; channelsToFetchData: string[] }) => {
    const { channelsToFetchData } = data;
    if (!channelsToFetchData || channelsToFetchData.length === 0) return;

    // Skip channels we've already fetched
    const unfetched = channelsToFetchData.filter((uuid) => !fetchedStreamIds.current.has(uuid));
    if (unfetched.length === 0) return;

    // Mark as fetched BEFORE the async call to prevent concurrent duplicate fetches
    unfetched.forEach((uuid) => fetchedStreamIds.current.add(uuid));

    try {
      const streamIds = unfetched.map((uuid) => Number(uuid));
      const sinceDate = new Date(data.since);
      const pad = (n: number) => n.toString().padStart(2, '0');
      const dateStr = `${sinceDate.getFullYear()}-${pad(sinceDate.getMonth() + 1)}-${pad(sinceDate.getDate())}`;

      const batchResult = await xtreamService.getEpgBatch(streamIds, dateStr);

      const newPrograms: EpgProgram[] = [];
      Object.entries(batchResult).forEach(([streamId, epg]) => {
        newPrograms.push(...transformListingsToEpgPrograms(streamId, epg.epg_listings || []));
      });

      if (newPrograms.length > 0) {
        setEpgData((prev) => [...prev, ...newPrograms]);
      }
    } catch (error) {
      console.error('Failed to fetch EPG zone:', error);
    }
  }, []);

  // Calculate start and end dates for the EPG range
  const { startDate, endDate } = useMemo(() => {
    const now = new Date();
    const pad = (n: number) => n.toString().padStart(2, '0');
    const yyyy = now.getFullYear();
    const mm = pad(now.getMonth() + 1);
    const dd = pad(now.getDate());

    return {
      startDate: `${yyyy}-${mm}-${dd}T00:00:00`,
      endDate: `${yyyy}-${mm}-${dd}T24:00:00`,
    };
  }, []);

  if (!isConfigured) {
    return (
      <View style={styles.centerContainer}>
        <Text style={styles.message}>Please connect to your service in Settings</Text>
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

  if (!isFocused) return null;

  return (
    <SpatialNavigationNode>
      <SpatialNavigationScrollView
        offsetFromStart={scaledPixels(100)}
        contentContainerStyle={{ paddingVertical: scaledPixels(40) }}
      >
        <DefaultFocus>
          <EpgContent
            channels={channels}
            epgData={epgData}
            startDate={startDate}
            endDate={endDate}
            isLoading={isLoading}
            onFetchZone={handleFetchZone}
          />
        </DefaultFocus>
      </SpatialNavigationScrollView>
    </SpatialNavigationNode>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: 'transparent',
    marginLeft: scaledPixels(100),
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
