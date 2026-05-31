import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { DvrRecording, DvrRecordingStatus } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { CategoryScroller } from '../components/CategoryScroller';
import { Icon } from '../components/Icon';
import xtreamService from '../services/XtreamService';

type StatusTab = { id: string; label: string; value: DvrRecordingStatus | undefined };

const STATUS_TABS: StatusTab[] = [
  { id: 'all', label: 'All Recordings', value: undefined },
  { id: 'scheduled', label: 'Scheduled', value: 'scheduled' },
  { id: 'recording', label: 'Recording', value: 'recording' },
  { id: 'completed', label: 'Completed', value: 'completed' },
  { id: 'failed', label: 'Failed', value: 'failed' },
];

const STATUS_COLORS: Record<DvrRecordingStatus, string> = {
  scheduled: colors.info,
  recording: colors.error,
  post_processing: colors.warning,
  completed: colors.success,
  failed: colors.error,
  cancelled: colors.textTertiary,
};

function formatDuration(seconds?: number): string {
  if (!seconds) return '';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function formatDateTime(iso?: string): string {
  if (!iso) return '';
  const d = new Date(iso);
  return (
    d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' }) +
    ' ' +
    d.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
  );
}

function formatFileSize(bytes?: number): string {
  if (!bytes) return '';
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(1)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${(bytes / 1e3).toFixed(0)} KB`;
}

type RecordingCardProps = {
  recording: DvrRecording;
  onSelect: (recording: DvrRecording) => void;
  isFirst: boolean;
};

function RecordingCard({ recording, onSelect, isFirst }: RecordingCardProps) {
  const { isSidebarActive, setSidebarActive } = useMenu();
  const statusColor = STATUS_COLORS[recording.status] ?? colors.textTertiary;
  const episodeLabel =
    recording.season != null && recording.episode != null
      ? ` S${String(recording.season).padStart(2, '0')}E${String(recording.episode).padStart(2, '0')}`
      : '';

  return (
    <FocusablePressable
      onFocus={isFirst ? () => isSidebarActive && setSidebarActive(false) : undefined}
      onSelect={() => onSelect(recording)}
      style={({ isFocused }) => [
        styles.card,
        isFocused && styles.cardFocused,
      ]}
    >
      {({ isFocused }) => (
        <>
          <View style={styles.cardStatus}>
            <View style={[styles.statusDot, { backgroundColor: statusColor }]} />
          </View>
          <View style={styles.cardBody}>
            <Text
              style={[styles.cardTitle, isFocused && styles.cardTitleFocused]}
              numberOfLines={1}
            >
              {recording.title}{episodeLabel}
            </Text>
            {!!recording.subtitle && (
              <Text style={styles.cardSubtitle} numberOfLines={1}>
                {recording.subtitle}
              </Text>
            )}
            <View style={styles.cardMeta}>
              {!!recording.channel_name && (
                <Text style={styles.metaText}>{recording.channel_name}</Text>
              )}
              {!!recording.scheduled_start && (
                <Text style={styles.metaText}>{formatDateTime(recording.scheduled_start)}</Text>
              )}
              {!!recording.duration_seconds && (
                <Text style={styles.metaText}>{formatDuration(recording.duration_seconds)}</Text>
              )}
              {!!recording.file_size_bytes && (
                <Text style={styles.metaText}>{formatFileSize(recording.file_size_bytes)}</Text>
              )}
            </View>
          </View>
          <View style={styles.cardChevron}>
            <Icon
              name="ChevronRight"
              size={scaledPixels(20)}
              color={isFocused ? colors.text : colors.textTertiary}
            />
          </View>
        </>
      )}
    </FocusablePressable>
  );
}

export function RecordingsScreen({ navigation }: DrawerScreenPropsType<'Recordings'>) {
  const isFocused = useIsFocused();
  const { isSidebarActive, setSidebarActive } = useMenu();
  const [selectedTab, setSelectedTab] = useState<DvrRecordingStatus | undefined>(undefined);
  const [recordings, setRecordings] = useState<DvrRecording[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const loadRecordings = useCallback(async () => {
    try {
      const data = await xtreamService.getRecordings(selectedTab);
      setRecordings(data);
    } catch (err) {
      console.error('[RecordingsScreen] load failed:', err);
    } finally {
      setIsLoading(false);
    }
  }, [selectedTab]);

  useEffect(() => {
    setIsLoading(true);
    loadRecordings();
  }, [loadRecordings]);

  // Auto-refresh every 30 s while on the Recording tab
  useEffect(() => {
    if (refreshTimerRef.current) {
      clearInterval(refreshTimerRef.current);
      refreshTimerRef.current = null;
    }
    if (isFocused && selectedTab === 'recording') {
      refreshTimerRef.current = setInterval(loadRecordings, 30_000);
    }
    return () => {
      if (refreshTimerRef.current) clearInterval(refreshTimerRef.current);
    };
  }, [isFocused, selectedTab, loadRecordings]);

  const handleSelectRecording = useCallback(
    (recording: DvrRecording) => {
      navigation.navigate('RecordingDetails', { recording });
    },
    [navigation],
  );

  const renderStatusTab = useCallback(
    ({ item, index }: { item: StatusTab; index: number }) => (
      <FocusablePressable
        onFocus={index === 0 ? () => isSidebarActive && setSidebarActive(false) : undefined}
        style={({ isFocused }) => [
          styles.categoryButton,
          selectedTab === item.value && styles.categoryButtonActive,
          isFocused && styles.categoryButtonFocused,
        ]}
        onSelect={() => setSelectedTab(item.value)}
      >
        {({ isFocused }) => (
          <Text
            style={[
              styles.categoryText,
              selectedTab === item.value && styles.categoryTextActive,
              isFocused && styles.categoryTextFocused,
            ]}
            numberOfLines={1}
          >
            {item.label}
          </Text>
        )}
      </FocusablePressable>
    ),
    [selectedTab, isSidebarActive, setSidebarActive],
  );

  const renderItem = useCallback(
    ({ item, index }: { item: DvrRecording; index: number }) => (
      <RecordingCard
        recording={item}
        onSelect={handleSelectRecording}
        isFirst={index === 0}
      />
    ),
    [handleSelectRecording],
  );

  const emptyLabel =
    selectedTab === 'scheduled' ? 'No scheduled recordings'
    : selectedTab === 'recording' ? 'Nothing recording right now'
    : selectedTab === 'completed' ? 'No completed recordings'
    : selectedTab === 'failed' ? 'No failed recordings'
    : 'No recordings yet';

  return (
    <View style={styles.container}>
      {/* Filter bar — outside FlatList, positioned to exactly match VOD/Series ListHeaderComponent offsets:
          paddingTop(20) + marginTop(25) and paddingHorizontal(20) + marginHorizontal(25) */}
      <View style={styles.categoryBar}>
        <View style={styles.categoryListContainer}>
          <CategoryScroller>
            {STATUS_TABS.map((tab, index) => (
              <React.Fragment key={tab.id}>
                {renderStatusTab({ item: tab, index })}
              </React.Fragment>
            ))}
          </CategoryScroller>
        </View>
      </View>

      <View style={styles.gridContent}>
        {isLoading && recordings.length > 0 && (
          <View style={styles.loadingOverlay}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        )}

        {/* Empty state rendered outside FlatList — ListEmptyComponent with flex:1 is unreliable on native TV */}
        {!isLoading && recordings.length === 0 ? (
          <View style={styles.emptyContainer}>
            <Icon name="VideoOff" size={scaledPixels(48)} color={colors.textTertiary} />
            <Text style={styles.emptyText}>{emptyLabel}</Text>
          </View>
        ) : (
          <FlatList
            data={recordings}
            keyExtractor={(r) => r.uuid}
            renderItem={renderItem}
            style={styles.list}
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
            ListEmptyComponent={
              isLoading ? (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color={colors.primary} />
                </View>
              ) : null
            }
          />
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  gridContent: {
    flex: 1,
  },
  list: {
    flex: 1,
    paddingHorizontal: scaledPixels(20),
  },
  listContent: {
    paddingBottom: scaledPixels(24),
    gap: scaledPixels(10),
  },
  // Outer wrapper gives the same padding as FlatList's `padding: scaledPixels(20)` in VOD/Series
  categoryBar: {
    paddingTop: scaledPixels(20),
    paddingHorizontal: scaledPixels(20),
  },
  // Inner container matches VOD/Series categoryListContainer exactly (no flex:1 here)
  categoryListContainer: {
    paddingVertical: scaledPixels(10),
    paddingHorizontal: scaledPixels(10),
    marginHorizontal: scaledPixels(25),
    marginTop: scaledPixels(25),
    height: scaledPixels(80),
    borderRadius: scaledPixels(50),
    backgroundColor: colors.scrimDark,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    zIndex: 5,
  },
  // Filter buttons — mirrors VOD/Series categoryButton exactly
  categoryButton: {
    paddingHorizontal: scaledPixels(25),
    paddingVertical: scaledPixels(10),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(25),
    marginHorizontal: scaledPixels(8),
    marginVertical: scaledPixels(4),
    width: scaledPixels(180),
    alignItems: 'center',
    overflow: 'visible',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: 'transparent',
  },
  categoryButtonActive: {
    backgroundColor: 'rgba(236, 0, 63, 0.2)',
    borderColor: colors.primary,
  },
  categoryButtonFocused: {
    backgroundColor: colors.primary,
    transform: [{ scale: 1.1 }],
  },
  categoryText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
  },
  categoryTextActive: {
    color: colors.text,
    fontWeight: 'bold',
  },
  categoryTextFocused: {
    color: colors.text,
    fontWeight: 'bold',
  },
  // Recording cards
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    paddingHorizontal: scaledPixels(16),
    paddingVertical: scaledPixels(14),
    borderWidth: 2,
    borderColor: 'transparent',
  },
  cardFocused: {
    borderColor: colors.primary,
    backgroundColor: colors.cardElevated,
    transform: [{ scale: 1.01 }],
  },
  cardStatus: {
    width: scaledPixels(12),
    alignItems: 'center',
    marginRight: scaledPixels(14),
  },
  statusDot: {
    width: scaledPixels(8),
    height: scaledPixels(8),
    borderRadius: scaledPixels(4),
  },
  cardBody: {
    flex: 1,
  },
  cardTitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
  },
  cardTitleFocused: {
    color: colors.text,
    fontWeight: 'bold',
  },
  cardSubtitle: {
    color: colors.textTertiary,
    fontSize: scaledPixels(15),
    marginTop: scaledPixels(2),
  },
  cardMeta: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: scaledPixels(12),
    marginTop: scaledPixels(5),
  },
  metaText: {
    color: colors.textTertiary,
    fontSize: scaledPixels(14),
  },
  cardChevron: {
    marginLeft: scaledPixels(8),
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: scaledPixels(60),
  },
  loadingOverlay: {
    position: 'absolute',
    top: scaledPixels(100),
    left: 0,
    right: 0,
    bottom: 0,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(10, 10, 15, 0.7)',
    zIndex: 10,
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: scaledPixels(60),
    gap: scaledPixels(14),
  },
  emptyText: {
    color: colors.textTertiary,
    fontSize: scaledPixels(20),
  },
});
