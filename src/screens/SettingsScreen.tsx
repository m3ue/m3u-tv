import React, { useState } from 'react';
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
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { FocusablePressable } from '../components/FocusablePressable';
import { scaledPixels } from '../hooks/useScale';

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
  } = useXtream();

  const [server, setServer] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

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
              onSelect={() => navigation.navigate('EPG')}
            >
              {({ isFocused }) => (
                <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>EPG Guide</Text>
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

        <FocusablePressable
          preferredFocus
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
          <FocusablePressable preferredFocus style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}>
            <TextInput
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
          <FocusablePressable style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}>
            <TextInput
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
          <FocusablePressable style={({ isFocused }) => [styles.inputContainer, isFocused && styles.inputFocused]}>
            <TextInput
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
});
