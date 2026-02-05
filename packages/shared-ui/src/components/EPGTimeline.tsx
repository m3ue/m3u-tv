import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { StyleSheet, View, Text, ScrollView } from 'react-native';
import {
  SpatialNavigationFocusableView,
  SpatialNavigationNode,
  SpatialNavigationScrollView,
} from 'react-tv-space-navigation';
import { xtreamService } from '../services/XtreamService';
import { XtreamEpgListing } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { colors } from '../theme';

interface EPGTimelineProps {
  streamId: number;
  channelName: string;
  onProgramSelect?: (program: XtreamEpgListing) => void;
}

const ProgramItem = React.memo(
  ({ program, isFocused, isNowPlaying }: { program: XtreamEpgListing; isFocused: boolean; isNowPlaying: boolean }) => {
    const startTime = new Date(program.start_timestamp * 1000);
    const endTime = new Date(program.stop_timestamp * 1000);

    const formatTime = (date: Date) => {
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    };

    return (
      <View
        style={[
          styles.programItem,
          isNowPlaying && styles.programItemNowPlaying,
          isFocused && styles.programItemFocused,
        ]}
      >
        <View style={styles.programTime}>
          <Text style={styles.programTimeText}>{formatTime(startTime)}</Text>
          <Text style={styles.programTimeSeparator}>-</Text>
          <Text style={styles.programTimeText}>{formatTime(endTime)}</Text>
        </View>
        <View style={styles.programInfo}>
          <Text style={styles.programTitle} numberOfLines={1}>
            {program.title}
          </Text>
          {program.description && (
            <Text style={styles.programDescription} numberOfLines={2}>
              {program.description}
            </Text>
          )}
        </View>
        {isNowPlaying && (
          <View style={styles.liveIndicator}>
            <Text style={styles.liveText}>LIVE</Text>
          </View>
        )}
      </View>
    );
  },
);

export default function EPGTimeline({ streamId, channelName, onProgramSelect }: EPGTimelineProps) {
  const [programs, setPrograms] = useState<XtreamEpgListing[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loadEpg = async () => {
      setIsLoading(true);
      setError(null);
      try {
        const epgData = await xtreamService.getSimpleDataTable(streamId);
        setPrograms(epgData.epg_listings || []);
      } catch (err) {
        console.error('Failed to load EPG:', err);
        setError('Failed to load program guide');
      } finally {
        setIsLoading(false);
      }
    };

    loadEpg();
  }, [streamId]);

  const nowTimestamp = useMemo(() => Math.floor(Date.now() / 1000), []);

  const isNowPlaying = useCallback(
    (program: XtreamEpgListing) => {
      return nowTimestamp >= program.start_timestamp && nowTimestamp < program.stop_timestamp;
    },
    [nowTimestamp],
  );

  if (isLoading) {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.headerTitle}>{channelName}</Text>
          <Text style={styles.headerSubtitle}>Program Guide</Text>
        </View>
        <View style={styles.loadingContainer}>
          <Text style={styles.loadingText}>Loading program guide...</Text>
        </View>
      </View>
    );
  }

  if (error || programs.length === 0) {
    return (
      <View style={styles.container}>
        <View style={styles.header}>
          <Text style={styles.headerTitle}>{channelName}</Text>
          <Text style={styles.headerSubtitle}>Program Guide</Text>
        </View>
        <View style={styles.emptyContainer}>
          <Text style={styles.emptyText}>{error || 'No program information available'}</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>{channelName}</Text>
        <Text style={styles.headerSubtitle}>Program Guide</Text>
      </View>

      <SpatialNavigationScrollView style={styles.programList}>
        <SpatialNavigationNode orientation="vertical">
          <>
          {programs.map((program, index) => (
            <SpatialNavigationFocusableView key={program.id || index} onSelect={() => onProgramSelect?.(program)}>
              {({ isFocused }) => (
                <ProgramItem program={program} isFocused={isFocused} isNowPlaying={isNowPlaying(program)} />
              )}
            </SpatialNavigationFocusableView>
          ))}
          </>
        </SpatialNavigationNode>
      </SpatialNavigationScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  header: {
    padding: scaledPixels(20),
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  headerTitle: {
    color: colors.text,
    fontSize: scaledPixels(28),
    fontWeight: 'bold',
  },
  headerSubtitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
    marginTop: scaledPixels(4),
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: scaledPixels(40),
  },
  emptyText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(20),
    textAlign: 'center',
  },
  programList: {
    flex: 1,
  },
  programItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: scaledPixels(16),
    marginHorizontal: scaledPixels(12),
    marginVertical: scaledPixels(4),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(8),
    borderWidth: scaledPixels(2),
    borderColor: 'transparent',
  },
  programItemNowPlaying: {
    backgroundColor: colors.cardElevated,
    borderColor: colors.primary,
  },
  programItemFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.02 }],
  },
  programTime: {
    width: scaledPixels(140),
    flexDirection: 'row',
    alignItems: 'center',
  },
  programTimeText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
    fontWeight: '500',
  },
  programTimeSeparator: {
    color: colors.textTertiary,
    fontSize: scaledPixels(18),
    marginHorizontal: scaledPixels(4),
  },
  programInfo: {
    flex: 1,
    marginLeft: scaledPixels(16),
  },
  programTitle: {
    color: colors.text,
    fontSize: scaledPixels(22),
    fontWeight: '600',
  },
  programDescription: {
    color: colors.textSecondary,
    fontSize: scaledPixels(16),
    marginTop: scaledPixels(4),
  },
  liveIndicator: {
    backgroundColor: '#ef4444',
    paddingHorizontal: scaledPixels(12),
    paddingVertical: scaledPixels(4),
    borderRadius: scaledPixels(4),
    marginLeft: scaledPixels(12),
  },
  liveText: {
    color: colors.text,
    fontSize: scaledPixels(14),
    fontWeight: 'bold',
  },
});
