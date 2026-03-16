import React, { useEffect, useRef, useState } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  ActivityIndicator,
  Alert,
  ScrollView,
} from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { useXtream } from '../context/XtreamContext';
import { useViewer } from '../context/ViewerContext';
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { FocusablePressable } from '../components/FocusablePressable';
import { scaledPixels } from '../hooks/useScale';
import { cacheService, CacheSettings } from '../services/CacheService';

const REFRESH_OPTIONS = [
  { label: '15 minutes', value: 15 },
  { label: '30 minutes', value: 30 },
  { label: '1 hour', value: 60 },
  { label: '3 hours', value: 180 },
  { label: '6 hours', value: 360 },
  { label: '12 hours', value: 720 },
  { label: '24 hours', value: 1440 },
] as const;

export function SettingsScreen({ navigation }: DrawerScreenPropsType<'Settings'>) {
  const isFocused = useIsFocused();
  const {
    isConfigured,
    isLoading,
    error,
    authResponse,
    connect,
    disconnect,
    clearError,
    liveCategories,
    vodCategories,
    seriesCategories,
    isM3UEditor,
    fetchLiveStreams,
    fetchVodStreams,
    fetchSeries,
    refreshCategories,
  } = useXtream();
  const { activeViewer } = useViewer();

  const serverRef = useRef<TextInput>(null);
  const usernameRef = useRef<TextInput>(null);
  const passwordRef = useRef<TextInput>(null);

  const [server, setServer] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [refreshInterval, setRefreshInterval] = useState(60);
  const [refreshingKey, setRefreshingKey] = useState<string | null>(null);

  useEffect(() => {
    cacheService.loadSettings().then((s) => setRefreshInterval(s.refreshIntervalMinutes));
  }, []);

  const handleRefreshChange = async (value: number) => {
    setRefreshInterval(value);
    await cacheService.saveSettings({ refreshIntervalMinutes: value });
  };

  const handleClearCache = async () => {
    await cacheService.clear();
    Alert.alert('Cache Cleared', 'All cached content has been removed.');
  };

  const handleManualRefresh = async (key: string, action: () => Promise<unknown>) => {
    if (refreshingKey) return;
    setRefreshingKey(key);
    try {
      await action();
      Alert.alert('Refreshed', `${key} data has been refreshed.`);
    } catch {
      Alert.alert('Error', `Failed to refresh ${key}.`);
    } finally {
      setRefreshingKey(null);
    }
  };

  const handleConnect = async () => {
    if (!server || !username || !password) {
      Alert.alert('Error', 'Please fill in all fields');
      return;
    }
    clearError();
    const success = await connect({ server, username, password });
    if (success) {
      navigation.navigate('Home');
    }
  };

  const handleDisconnect = async () => {
    Alert.alert('Disconnect', 'Are you sure you want to disconnect?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Disconnect',
        style: 'destructive',
        onPress: disconnect,
      },
    ]);
  };

  if (isConfigured && authResponse) {
    if (!isFocused) return null;
    return (
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        <View style={styles.infoContainer}>
          <Text style={styles.title}>Welcome to M3U TV</Text>
          <Text style={styles.subtitle}>Your streaming server is connected</Text>

          <View style={styles.statsContainer}>
            <View style={styles.statCard}>
              <Text style={styles.statNumber}>{liveCategories.length}</Text>
              <Text style={styles.statLabel}>Live TV Categories</Text>
            </View>
            <View style={styles.statCard}>
              <Text style={styles.statNumber}>{vodCategories.length}</Text>
              <Text style={styles.statLabel}>Movie Categories</Text>
            </View>
            <View style={styles.statCard}>
              <Text style={styles.statNumber}>{seriesCategories.length}</Text>
              <Text style={styles.statLabel}>Series Categories</Text>
            </View>
          </View>

          <View style={styles.menuContainer}>
            <FocusablePressable
              preferredFocus
              style={({ isFocused }) => [styles.menuButton, isFocused && styles.menuButtonFocused]}
              onSelect={() => navigation.navigate('LiveTV')}
            >
              {({ isFocused }) => (
                <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>Live TV</Text>
              )}
            </FocusablePressable>
            <FocusablePressable
              style={({ isFocused }) => [styles.menuButton, isFocused && styles.menuButtonFocused]}
              onSelect={() => navigation.navigate('VOD')}
            >
              {({ isFocused }) => (
                <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>Movies</Text>
              )}
            </FocusablePressable>
            <FocusablePressable
              style={({ isFocused }) => [styles.menuButton, isFocused && styles.menuButtonFocused]}
              onSelect={() => navigation.navigate('Series')}
            >
              {({ isFocused }) => (
                <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>TV Series</Text>
              )}
            </FocusablePressable>
          </View>
        </View>

        <Text style={styles.title}>Connection Status</Text>

        <View style={styles.statusCard}>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Status</Text>
            <Text style={[styles.statusValue, styles.connected]}>Connected</Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Username</Text>
            <Text style={styles.statusValue}>{authResponse.user_info.username}</Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Expires</Text>
            <Text style={styles.statusValue}>
              {new Date(parseInt(authResponse.user_info.exp_date) * 1000).toLocaleDateString()}
            </Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Max Connections</Text>
            <Text style={styles.statusValue}>{authResponse.user_info.max_connections}</Text>
          </View>
          <View style={styles.statusRow}>
            <Text style={styles.statusLabel}>Active Connections</Text>
            <Text style={styles.statusValue}>{authResponse.user_info.active_cons}</Text>
          </View>
        </View>

        {isM3UEditor && activeViewer && (
          <View style={styles.viewerSection}>
            <Text style={styles.title}>Active Viewer</Text>
            <View style={styles.viewerCard}>
              <View style={styles.viewerRow}>
                <View style={styles.viewerAvatar}>
                  <Text style={styles.viewerAvatarText}>{activeViewer.name.charAt(0).toUpperCase()}</Text>
                </View>
                <View style={styles.viewerInfo}>
                  <Text style={styles.viewerName}>{activeViewer.name}</Text>
                  {activeViewer.is_admin && <Text style={styles.viewerAdmin}>Admin</Text>}
                </View>
              </View>
              <FocusablePressable
                preferredFocus
                style={({ isFocused }) => [styles.settingsButton, isFocused && styles.settingsButtonFocused]}
                onSelect={() => navigation.navigate('ViewerSelection')}
              >
                {({ isFocused }) => (
                  <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>Switch Viewer</Text>
                )}
              </FocusablePressable>
            </View>
          </View>
        )}

        <View style={styles.cacheSection}>
          <Text style={styles.title}>Content Cache</Text>
          <Text style={styles.cacheDescription}>
            Cached content loads instantly. Data refreshes automatically in the background.
          </Text>

          <Text style={styles.label}>Refresh Interval</Text>
          <View style={styles.refreshOptions}>
            {REFRESH_OPTIONS.map((option) => (
              <FocusablePressable
                key={option.value}
                style={({ isFocused }) => [
                  styles.refreshOption,
                  refreshInterval === option.value && styles.refreshOptionActive,
                  isFocused && styles.refreshOptionFocused,
                ]}
                onSelect={() => handleRefreshChange(option.value)}
              >
                {({ isFocused }) => (
                  <Text
                    style={[
                      styles.refreshOptionText,
                      refreshInterval === option.value && styles.refreshOptionTextActive,
                      isFocused && styles.buttonTextFocused,
                    ]}
                  >
                    {option.label}
                  </Text>
                )}
              </FocusablePressable>
            ))}
          </View>

          <Text style={styles.label}>Manual Refresh</Text>
          <View style={styles.refreshActions}>
            {[
              { key: 'Categories', action: () => refreshCategories() },
              { key: 'Channels', action: () => fetchLiveStreams(undefined, true) },
              { key: 'Movies', action: () => fetchVodStreams(undefined, true) },
              { key: 'Series', action: () => fetchSeries(undefined, true) },
            ].map((item) => (
              <FocusablePressable
                key={item.key}
                style={({ isFocused }) => [
                  styles.refreshAction,
                  isFocused && styles.refreshActionFocused,
                ]}
                onSelect={() => handleManualRefresh(item.key, item.action)}
              >
                {({ isFocused }) => (
                  <Text
                    style={[
                      styles.refreshActionText,
                      isFocused && styles.buttonTextFocused,
                    ]}
                  >
                    {refreshingKey === item.key ? 'Refreshing...' : item.key}
                  </Text>
                )}
              </FocusablePressable>
            ))}
          </View>

          <FocusablePressable
            style={({ isFocused }) => [styles.settingsButton, isFocused && styles.settingsButtonFocused]}
            onSelect={handleClearCache}
          >
            {({ isFocused }) => (
              <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>Clear Cache</Text>
            )}
          </FocusablePressable>
        </View>

        <FocusablePressable
          style={({ isFocused }) => [styles.settingsButton, isFocused && styles.settingsButtonFocused]}
          onSelect={handleDisconnect}
        >
          {({ isFocused }) => (
            <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>Disconnect</Text>
          )}
        </FocusablePressable>
      </ScrollView>
    );
  }

  if (!isFocused) return null;

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={[styles.content, { paddingLeft: scaledPixels(100) }]}
    >
      <Text style={styles.title}>Connection Settings</Text>
      <Text style={styles.subtitle}>Enter your Xtream codes details</Text>

      <View style={styles.form}>
        {error ? <Text style={styles.errorText}>{error}</Text> : null}

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Server URL</Text>
          <FocusablePressable
            preferredFocus
            style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}
            onSelect={() => serverRef.current?.focus()}
          >
            <TextInput
              ref={serverRef}
              style={styles.input}
              value={server}
              onChangeText={setServer}
              placeholder="http://example.com:8080"
              placeholderTextColor={colors.textSecondary}
              autoCapitalize="none"
              autoCorrect={false}
            />
          </FocusablePressable>
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Username</Text>
          <FocusablePressable
            style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}
            onSelect={() => usernameRef.current?.focus()}
          >
            <TextInput
              ref={usernameRef}
              style={styles.input}
              value={username}
              onChangeText={setUsername}
              placeholder="Username"
              placeholderTextColor={colors.textSecondary}
              autoCapitalize="none"
              autoCorrect={false}
            />
          </FocusablePressable>
        </View>

        <View style={styles.inputGroup}>
          <Text style={styles.label}>Password</Text>
          <FocusablePressable
            style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}
            onSelect={() => passwordRef.current?.focus()}
          >
            <TextInput
              ref={passwordRef}
              style={styles.input}
              value={password}
              onChangeText={setPassword}
              placeholder="Password"
              placeholderTextColor={colors.textSecondary}
              secureTextEntry
              autoCapitalize="none"
              autoCorrect={false}
            />
          </FocusablePressable>
        </View>

        <FocusablePressable
          style={({ isFocused }) => [styles.connectButton, isFocused && styles.buttonFocused]}
          onSelect={handleConnect}
        >
          {isLoading ? <ActivityIndicator color={colors.text} /> : <Text style={styles.buttonText}>Connect</Text>}
        </FocusablePressable>
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: scaledPixels(spacing.lg),
    maxWidth: scaledPixels(1000),
    width: '100%',
    alignSelf: 'center',
  },
  infoContainer: {
    marginBottom: scaledPixels(40),
  },
  title: {
    fontSize: scaledPixels(typography.fontSize.xl),
    fontWeight: typography.fontWeight.bold,
    color: colors.text,
    marginBottom: scaledPixels(spacing.xs),
    textAlign: 'center',
  },
  subtitle: {
    fontSize: scaledPixels(typography.fontSize.md),
    color: colors.textSecondary,
    marginBottom: scaledPixels(spacing.lg),
    textAlign: 'center',
  },
  errorContainer: {
    backgroundColor: colors.error + '20',
    padding: scaledPixels(spacing.md),
    borderRadius: scaledPixels(8),
    marginBottom: scaledPixels(spacing.md),
    borderWidth: 1,
    borderColor: colors.error,
  },
  errorText: {
    color: colors.error,
    fontSize: scaledPixels(typography.fontSize.sm),
  },
  inputContainer: {
    marginBottom: scaledPixels(spacing.md),
  },
  label: {
    fontSize: scaledPixels(typography.fontSize.sm),
    color: colors.textSecondary,
    marginBottom: scaledPixels(spacing.xs),
  },
  form: {
    width: '100%',
    maxWidth: scaledPixels(500),
    alignSelf: 'center',
  },
  inputGroup: {
    marginBottom: scaledPixels(spacing.md),
  },
  inputFocused: {
    borderColor: colors.primary,
    borderRadius: scaledPixels(12),
    borderWidth: 2,
    transform: [{ scale: 1.02 }],
  },
  connectButton: {
    backgroundColor: colors.primary,
    padding: scaledPixels(spacing.md),
    borderRadius: scaledPixels(8),
    alignItems: 'center',
    marginTop: scaledPixels(spacing.lg),
  },
  buttonFocused: {
    borderColor: colors.text,
    borderWidth: 2,
    transform: [{ scale: 1.05 }],
  },
  buttonText: {
    color: colors.textOnPrimary || '#FFFFFF',
    fontSize: scaledPixels(typography.fontSize.md),
    fontWeight: typography.fontWeight.bold,
  },
  input: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(8),
    padding: scaledPixels(spacing.md),
    fontSize: scaledPixels(typography.fontSize.md),
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  settingsButton: {
    backgroundColor: colors.cardElevated,
    paddingHorizontal: scaledPixels(40),
    paddingVertical: scaledPixels(20),
    borderRadius: scaledPixels(16),
    alignItems: 'center',
    marginTop: scaledPixels(spacing.md),
    borderWidth: 3,
    borderColor: colors.border,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  settingsButtonText: {
    color: colors.text,
    fontSize: scaledPixels(24),
    fontWeight: '500',
  },
  settingsButtonFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
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
  statusCard: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(spacing.lg),
    marginBottom: scaledPixels(spacing.lg),
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: scaledPixels(spacing.sm),
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  statusLabel: {
    fontSize: scaledPixels(typography.fontSize.md),
    color: colors.textSecondary,
  },
  statusValue: {
    fontSize: scaledPixels(typography.fontSize.md),
    color: colors.text,
    fontWeight: typography.fontWeight.medium,
  },
  connected: {
    color: colors.success,
  },
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    gap: scaledPixels(20),
    marginBottom: scaledPixels(60),
    flexWrap: 'wrap',
  },
  statCard: {
    backgroundColor: colors.card,
    padding: scaledPixels(30),
    borderRadius: scaledPixels(16),
    alignItems: 'center',
    minWidth: scaledPixels(180),
  },
  statNumber: {
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    color: colors.primary,
  },
  statLabel: {
    fontSize: scaledPixels(18),
    color: colors.textSecondary,
    marginTop: scaledPixels(8),
    textAlign: 'center',
  },
  menuContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: scaledPixels(20),
  },
  menuButton: {
    backgroundColor: colors.cardElevated,
    paddingHorizontal: scaledPixels(40),
    paddingVertical: scaledPixels(30),
    borderRadius: scaledPixels(16),
    minWidth: scaledPixels(200),
    alignItems: 'center',
    borderWidth: 3,
    borderColor: colors.border,
  },
  menuButtonFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  menuButtonText: {
    color: colors.text,
    fontSize: scaledPixels(24),
    fontWeight: '500',
  },
  viewerSection: {
    marginBottom: scaledPixels(40),
  },
  viewerCard: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(spacing.lg),
    gap: scaledPixels(20),
  },
  viewerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(16),
  },
  viewerAvatar: {
    width: scaledPixels(56),
    height: scaledPixels(56),
    borderRadius: scaledPixels(28),
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  viewerAvatarText: {
    color: colors.text,
    fontSize: scaledPixels(24),
    fontWeight: 'bold',
  },
  viewerInfo: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(12),
  },
  viewerName: {
    color: colors.text,
    fontSize: scaledPixels(22),
    fontWeight: '600',
  },
  viewerAdmin: {
    color: colors.primary,
    fontSize: scaledPixels(14),
    backgroundColor: 'rgba(236,0,63,0.15)',
    paddingHorizontal: scaledPixels(8),
    paddingVertical: scaledPixels(3),
    borderRadius: scaledPixels(4),
  },
  cacheSection: {
    marginBottom: scaledPixels(40),
  },
  cacheDescription: {
    fontSize: scaledPixels(typography.fontSize.sm),
    color: colors.textSecondary,
    marginBottom: scaledPixels(spacing.md),
    textAlign: 'center',
  },
  refreshOptions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: scaledPixels(12),
    marginBottom: scaledPixels(spacing.lg),
  },
  refreshOption: {
    backgroundColor: colors.card,
    paddingHorizontal: scaledPixels(24),
    paddingVertical: scaledPixels(14),
    borderRadius: scaledPixels(12),
    borderWidth: 2,
    borderColor: colors.border,
  },
  refreshOptionActive: {
    borderColor: colors.primary,
    backgroundColor: 'rgba(236,0,63,0.15)',
  },
  refreshOptionFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
  },
  refreshOptionText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
    fontWeight: '500',
  },
  refreshOptionTextActive: {
    color: colors.primary,
    fontWeight: '600',
  },
  refreshActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'center',
    gap: scaledPixels(12),
    marginBottom: scaledPixels(spacing.lg),
  },
  refreshAction: {
    backgroundColor: colors.card,
    paddingHorizontal: scaledPixels(24),
    paddingVertical: scaledPixels(14),
    borderRadius: scaledPixels(12),
    borderWidth: 2,
    borderColor: colors.border,
  },
  refreshActionFocused: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
  },
  refreshActionText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(18),
    fontWeight: '500',
  },
});
