import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useMenu } from '../context/MenuContext';
import { colors } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { DvrRecording } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import xtreamService from '../services/XtreamService';

const STATUS_LABELS: Record<string, string> = {
  scheduled: 'Scheduled',
  recording: 'Recording',
  post_processing: 'Processing',
  completed: 'Completed',
  failed: 'Failed',
  cancelled: 'Cancelled',
};

const STATUS_COLORS: Record<string, string> = {
  scheduled: colors.info,
  recording: colors.error,
  post_processing: colors.warning,
  completed: colors.success,
  failed: colors.error,
  cancelled: colors.textTertiary,
};

function formatDuration(seconds?: number): string {
  if (!seconds) return '—';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function formatDateTime(iso?: string): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString(undefined, {
    month: 'short', day: 'numeric', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function formatFileSize(bytes?: number): string {
  if (!bytes) return '—';
  if (bytes >= 1e9) return `${(bytes / 1e9).toFixed(2)} GB`;
  if (bytes >= 1e6) return `${(bytes / 1e6).toFixed(0)} MB`;
  return `${(bytes / 1e3).toFixed(0)} KB`;
}

type MetaRowProps = { label: string; value: string };

function MetaRow({ label, value }: MetaRowProps) {
  return (
    <View style={styles.metaRow}>
      <Text style={styles.metaLabel}>{label}</Text>
      <Text style={styles.metaValue}>{value}</Text>
    </View>
  );
}

export function RecordingDetailsScreen({ route, navigation }: RootStackScreenProps<'RecordingDetails'>) {
  const isFocused = useIsFocused();
  const { setSidebarActive } = useMenu();
  const playButtonRef = useRef<FocusablePressableRef>(null);
  const [recording, setRecording] = useState<DvrRecording>(route.params.recording);
  const [isActing, setIsActing] = useState(false);

  useEffect(() => {
    if (isFocused) {
      setSidebarActive(false);
      playButtonRef.current?.focus();
    }
  }, [isFocused, setSidebarActive]);

  const refresh = useCallback(async () => {
    try {
      const fresh = await xtreamService.getRecording(recording.uuid);
      setRecording(fresh);
    } catch (err) {
      console.error('[RecordingDetailsScreen] refresh failed:', err);
    }
  }, [recording.uuid]);

  const handlePlay = useCallback(() => {
    const url = recording.status === 'recording' ? recording.live_url : recording.stream_url;
    if (!url) return;
    navigation.navigate('Player', {
      streamUrl: url,
      title: recording.title,
      type: 'dvr',
      streamId: undefined,
    });
  }, [recording, navigation]);

  const handleCancel = useCallback(async () => {
    if (isActing) return;
    setIsActing(true);
    try {
      await xtreamService.cancelRecording(recording.uuid);
      await refresh();
    } catch (err) {
      console.error('[RecordingDetailsScreen] cancel failed:', err);
    } finally {
      setIsActing(false);
    }
  }, [recording.uuid, isActing, refresh]);

  const handleDelete = useCallback(async () => {
    if (isActing) return;
    setIsActing(true);
    try {
      await xtreamService.deleteRecording(recording.uuid);
      navigation.goBack();
    } catch (err) {
      console.error('[RecordingDetailsScreen] delete failed:', err);
      setIsActing(false);
    }
  }, [recording.uuid, isActing, navigation]);

  const canPlay =
    (recording.status === 'completed' && !!recording.stream_url) ||
    (recording.status === 'recording' && !!recording.live_url);

  const canCancel =
    recording.status === 'scheduled' || recording.status === 'recording';

  const canDelete =
    recording.status === 'completed' ||
    recording.status === 'failed' ||
    recording.status === 'cancelled';

  const episodeLabel =
    recording.season != null && recording.episode != null
      ? `S${String(recording.season).padStart(2, '0')}E${String(recording.episode).padStart(2, '0')}`
      : undefined;

  const statusColor = STATUS_COLORS[recording.status] ?? colors.textTertiary;

  return (
    <View style={styles.container}>
      {/* Back button */}
      <FocusablePressable
        onPress={() => navigation.goBack()}
        style={({ isFocused }) => [styles.backButton, isFocused && styles.backButtonFocused]}
      >
        <Icon name="ArrowLeft" size={scaledPixels(18)} color={colors.text} />
        <Text style={styles.backLabel}>Recordings</Text>
      </FocusablePressable>

      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        {/* Header */}
        <View style={styles.header}>
          <View style={styles.titleRow}>
            <Text style={styles.title}>{recording.title}</Text>
            <View style={[styles.statusBadge, { backgroundColor: statusColor + '33', borderColor: statusColor }]}>
              <Text style={[styles.statusText, { color: statusColor }]}>
                {STATUS_LABELS[recording.status] ?? recording.status}
              </Text>
            </View>
          </View>
          {!!episodeLabel && <Text style={styles.episodeLabel}>{episodeLabel}</Text>}
          {!!recording.subtitle && <Text style={styles.subtitle}>{recording.subtitle}</Text>}
        </View>

        {/* Action buttons */}
        <View style={styles.actions}>
          {canPlay && (
            <FocusablePressable
              ref={playButtonRef}
              onPress={handlePlay}
              style={({ isFocused }) => [styles.actionBtn, styles.actionBtnPrimary, isFocused && styles.actionBtnFocused]}
            >
              <Icon name={recording.status === 'recording' ? 'Radio' : 'Play'} size={scaledPixels(16)} color={colors.textOnPrimary} />
              <Text style={[styles.actionBtnText, styles.actionBtnTextPrimary]}>
                {recording.status === 'recording' ? 'Watch Live' : 'Play'}
              </Text>
            </FocusablePressable>
          )}
          {canCancel && (
            <FocusablePressable
              onPress={handleCancel}
              style={({ isFocused }) => [styles.actionBtn, isFocused && styles.actionBtnFocused]}
            >
              <Icon name="XCircle" size={scaledPixels(16)} color={colors.warning} />
              <Text style={[styles.actionBtnText, { color: colors.warning }]}>Cancel</Text>
            </FocusablePressable>
          )}
          {canDelete && (
            <FocusablePressable
              onPress={handleDelete}
              style={({ isFocused }) => [styles.actionBtn, isFocused && styles.actionBtnFocused]}
            >
              <Icon name="Trash2" size={scaledPixels(16)} color={colors.error} />
              <Text style={[styles.actionBtnText, { color: colors.error }]}>Delete</Text>
            </FocusablePressable>
          )}
        </View>

        {/* Metadata */}
        <View style={styles.metaSection}>
          {!!recording.channel_name && (
            <MetaRow label="Channel" value={recording.channel_name} />
          )}
          <MetaRow label="Scheduled" value={`${formatDateTime(recording.scheduled_start)} → ${formatDateTime(recording.scheduled_end)}`} />
          {!!recording.actual_start && (
            <MetaRow label="Recorded" value={`${formatDateTime(recording.actual_start)}${recording.actual_end ? ' → ' + formatDateTime(recording.actual_end) : ''}`} />
          )}
          <MetaRow label="Duration" value={formatDuration(recording.duration_seconds)} />
          {!!recording.file_size_bytes && (
            <MetaRow label="File size" value={formatFileSize(recording.file_size_bytes)} />
          )}
          {!!recording.error_message && (
            <MetaRow label="Error" value={recording.error_message} />
          )}
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  backButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: scaledPixels(24),
    paddingHorizontal: scaledPixels(24),
    paddingBottom: scaledPixels(8),
    gap: scaledPixels(6),
    alignSelf: 'flex-start',
  },
  backButtonFocused: {
    opacity: 0.7,
  },
  backLabel: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
  },
  content: {
    paddingHorizontal: scaledPixels(24),
    paddingBottom: scaledPixels(40),
  },
  header: {
    marginBottom: scaledPixels(20),
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: scaledPixels(10),
    marginBottom: scaledPixels(4),
  },
  title: {
    fontSize: scaledPixels(22),
    fontWeight: '700',
    color: colors.text,
    flexShrink: 1,
  },
  statusBadge: {
    paddingHorizontal: scaledPixels(10),
    paddingVertical: scaledPixels(3),
    borderRadius: scaledPixels(12),
    borderWidth: 1,
  },
  statusText: {
    fontSize: scaledPixels(12),
    fontWeight: '600',
  },
  episodeLabel: {
    color: colors.primary,
    fontSize: scaledPixels(14),
    fontWeight: '600',
    marginBottom: scaledPixels(2),
  },
  subtitle: {
    color: colors.textSecondary,
    fontSize: scaledPixels(15),
    marginTop: scaledPixels(2),
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: scaledPixels(10),
    marginBottom: scaledPixels(24),
  },
  actionBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(6),
    paddingHorizontal: scaledPixels(18),
    paddingVertical: scaledPixels(10),
    borderRadius: scaledPixels(8),
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.border,
  },
  actionBtnPrimary: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  actionBtnFocused: {
    borderColor: colors.focusBorder,
  },
  actionBtnText: {
    fontSize: scaledPixels(14),
    fontWeight: '600',
    color: colors.textSecondary,
  },
  actionBtnTextPrimary: {
    color: colors.textOnPrimary,
  },
  metaSection: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(10),
    borderWidth: 1,
    borderColor: colors.border,
    overflow: 'hidden',
  },
  metaRow: {
    flexDirection: 'row',
    paddingHorizontal: scaledPixels(16),
    paddingVertical: scaledPixels(12),
    borderBottomWidth: 1,
    borderBottomColor: colors.divider,
  },
  metaLabel: {
    color: colors.textTertiary,
    fontSize: scaledPixels(13),
    width: scaledPixels(90),
    flexShrink: 0,
  },
  metaValue: {
    color: colors.text,
    fontSize: scaledPixels(13),
    flex: 1,
  },
});
