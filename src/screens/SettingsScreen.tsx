import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  ScrollView,
  Alert,
} from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors, spacing, typography } from '../theme';
import { DrawerScreenPropsType } from '../navigation/types';
import { SpatialNavigationNode, DefaultFocus } from 'react-tv-space-navigation';
import { FocusablePressable } from '../components/FocusablePressable';
import { scaledPixels } from '../hooks/useScale';

export function SettingsScreen({ navigation }: DrawerScreenPropsType<'Settings'>) {
  const {
    isConfigured,
    isLoading,
    error,
    authResponse,
    connect,
    disconnect,
    clearError,
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
    Alert.alert(
      'Disconnect',
      'Are you sure you want to disconnect?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Disconnect',
          style: 'destructive',
          onPress: disconnect,
        },
      ],
    );
  };

  if (isConfigured && authResponse) {
    return (
      <SpatialNavigationNode>
        <ScrollView style={styles.container} contentContainerStyle={styles.content}>
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

          <SpatialNavigationNode>
            <DefaultFocus>
              <FocusablePressable
                style={({ isFocused }) => [
                  styles.disconnectButton,
                  isFocused && styles.buttonFocused,
                ]}
                onSelect={handleDisconnect}
              >
                <Text style={styles.disconnectButtonText}>Disconnect</Text>
              </FocusablePressable>
            </DefaultFocus>
          </SpatialNavigationNode>
        </ScrollView>
      </SpatialNavigationNode>
    );
  }

  return (
    <SpatialNavigationNode>
      <ScrollView style={styles.container} contentContainerStyle={styles.content}>
        <Text style={styles.title}>Xtream API Settings</Text>
        <Text style={styles.subtitle}>Enter your Xtream codes credentials to connect</Text>

        {error && (
          <View style={styles.errorContainer}>
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}

        <View style={styles.inputContainer}>
          <Text style={styles.label}>Server URL</Text>
          <TextInput
            style={styles.input}
            placeholder="http://example.com:8080"
            placeholderTextColor={colors.textTertiary}
            value={server}
            onChangeText={setServer}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>

        <View style={styles.inputContainer}>
          <Text style={styles.label}>Username</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter username"
            placeholderTextColor={colors.textTertiary}
            value={username}
            onChangeText={setUsername}
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>

        <View style={styles.inputContainer}>
          <Text style={styles.label}>Password</Text>
          <TextInput
            style={styles.input}
            placeholder="Enter password"
            placeholderTextColor={colors.textTertiary}
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            autoCorrect={false}
          />
        </View>

        <SpatialNavigationNode>
          <FocusablePressable
            style={({ isFocused }) => [
              styles.connectButton,
              isFocused && styles.buttonFocused,
              isLoading && styles.buttonDisabled,
            ]}
            onSelect={handleConnect}
          >
            {isLoading ? (
              <ActivityIndicator color={colors.textOnPrimary} />
            ) : (
              <Text style={styles.connectButtonText}>Connect</Text>
            )}
          </FocusablePressable>
        </SpatialNavigationNode>
      </ScrollView>
    </SpatialNavigationNode>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    padding: spacing.lg,
  },
  title: {
    fontSize: typography.fontSize.xl,
    fontWeight: typography.fontWeight.bold,
    color: colors.text,
    marginBottom: spacing.xs,
  },
  subtitle: {
    fontSize: typography.fontSize.md,
    color: colors.textSecondary,
    marginBottom: spacing.lg,
  },
  errorContainer: {
    backgroundColor: colors.error + '20',
    padding: spacing.md,
    borderRadius: 8,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.error,
  },
  errorText: {
    color: colors.error,
    fontSize: typography.fontSize.sm,
  },
  inputContainer: {
    marginBottom: spacing.md,
  },
  label: {
    fontSize: typography.fontSize.sm,
    color: colors.textSecondary,
    marginBottom: spacing.xs,
  },
  input: {
    backgroundColor: colors.card,
    borderRadius: 8,
    padding: spacing.md,
    fontSize: typography.fontSize.md,
    color: colors.text,
    borderWidth: 1,
    borderColor: colors.border,
  },
  connectButton: {
    backgroundColor: colors.primary,
    padding: spacing.md,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: spacing.md,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  connectButtonText: {
    color: colors.textOnPrimary,
    fontSize: typography.fontSize.md,
    fontWeight: typography.fontWeight.semibold,
  },
  buttonFocused: {
    transform: [{ scale: 1.05 }],
    borderColor: colors.primary,
    borderWidth: 2,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.5,
    shadowRadius: 10,
    elevation: 5,
  },
  statusCard: {
    backgroundColor: colors.card,
    borderRadius: 12,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  statusRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  statusLabel: {
    fontSize: typography.fontSize.md,
    color: colors.textSecondary,
  },
  statusValue: {
    fontSize: typography.fontSize.md,
    color: colors.text,
    fontWeight: typography.fontWeight.medium,
  },
  connected: {
    color: colors.success,
  },
  disconnectButton: {
    backgroundColor: colors.error,
    padding: spacing.md,
    borderRadius: 8,
    alignItems: 'center',
  },
  disconnectButtonText: {
    color: colors.textOnPrimary,
    fontSize: typography.fontSize.md,
    fontWeight: typography.fontWeight.semibold,
  },
});
