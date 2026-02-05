import { StyleSheet, View, Text, TextInput, Alert, Platform } from 'react-native';
import {
  SpatialNavigationRoot,
  SpatialNavigationNode,
  SpatialNavigationScrollView,
  SpatialNavigationFocusableView,
  DefaultFocus,
} from 'react-tv-space-navigation';
import { DrawerActions, useIsFocused, useNavigation } from '@react-navigation/native';
import { Direction } from '@bam.tech/lrud';
import { scaledPixels } from '../hooks/useScale';
import { colors, safeZones } from '../theme';
import FocusablePressable from '../components/FocusablePressable';
import { useCallback, useState, useEffect, useRef } from 'react';
import { useMenuContext } from '../components/MenuContext';
import { useXtream } from '../context/XtreamContext';

export default function SettingsScreen() {
  const isFocused = useIsFocused();
  const navigation = useNavigation();
  const { isOpen: isMenuOpen, toggleMenu } = useMenuContext();
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
  const [focusedInput, setFocusedInput] = useState<string | null>(null);

  // Refs for TextInputs to programmatically focus them
  const serverInputRef = useRef<TextInput>(null);
  const usernameInputRef = useRef<TextInput>(null);
  const passwordInputRef = useRef<TextInput>(null);

  // Clear error when leaving screen
  useEffect(() => {
    if (!isFocused) {
      clearError();
    }
  }, [isFocused, clearError]);

  const onDirectionHandledWithoutMovement = useCallback(
    (movement: Direction) => {
      if (movement === 'left') {
        navigation.dispatch(DrawerActions.openDrawer());
        toggleMenu(true);
      }
    },
    [toggleMenu, navigation],
  );

  const handleConnect = useCallback(async () => {
    if (!server || !username || !password) {
      if (Platform.OS === 'web') {
        alert('Please fill in all connection fields');
      } else {
        Alert.alert('Error', 'Please fill in all connection fields');
      }
      return;
    }

    const success = await connect({
      server: server.trim(),
      username: username.trim(),
      password: password.trim(),
    });

    if (success) {
      if (Platform.OS === 'web') {
        alert('Connected successfully!');
      } else {
        Alert.alert('Success', 'Connected successfully!');
      }
    }
  }, [server, username, password, connect]);

  const handleDisconnect = useCallback(async () => {
    await disconnect();
    setServer('');
    setUsername('');
    setPassword('');
  }, [disconnect]);

  const formatDate = (timestamp: string) => {
    if (!timestamp) return 'N/A';
    const date = new Date(parseInt(timestamp) * 1000);
    return date.toLocaleDateString();
  };

  return (
    <SpatialNavigationRoot
      isActive={isFocused && !isMenuOpen}
      onDirectionHandledWithoutMovement={onDirectionHandledWithoutMovement}
    >
      <View style={styles.container}>
        <View style={styles.innerContainer}>
          <Text style={styles.title}>Settings</Text>
          <SpatialNavigationScrollView style={styles.scrollView}>
            <View style={styles.scrollContent}>
              {/* About Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>About</Text>
                <View style={styles.infoContainer}>
                  <View style={styles.infoRow}>
                    <Text style={styles.infoLabel}>App</Text>
                    <Text style={styles.infoValue}>M3U TV</Text>
                  </View>
                  <View style={styles.infoRow}>
                    <Text style={styles.infoLabel}>Version</Text>
                    <Text style={styles.infoValue}>1.0.0</Text>
                  </View>
                </View>
              </View>
              {/* Connection Section */}
              <View style={styles.section}>
                <Text style={styles.sectionTitle}>Xtream Connection</Text>

                {isConfigured && authResponse ? (
                  // Connected state
                  <View style={styles.connectionInfo}>
                    <View style={styles.statusRow}>
                      <View style={styles.statusDot} />
                      <Text style={styles.statusText}>Connected</Text>
                    </View>

                    <View style={styles.infoContainer}>
                      <View style={styles.infoRow}>
                        <Text style={styles.infoLabel}>Username</Text>
                        <Text style={styles.infoValue}>{authResponse.user_info.username}</Text>
                      </View>
                      <View style={styles.infoRow}>
                        <Text style={styles.infoLabel}>Status</Text>
                        <Text style={styles.infoValue}>{authResponse.user_info.status}</Text>
                      </View>
                      <View style={styles.infoRow}>
                        <Text style={styles.infoLabel}>Expires</Text>
                        <Text style={styles.infoValue}>{formatDate(authResponse.user_info.exp_date)}</Text>
                      </View>
                      <View style={styles.infoRow}>
                        <Text style={styles.infoLabel}>Max Connections</Text>
                        <Text style={styles.infoValue}>{authResponse.user_info.max_connections}</Text>
                      </View>
                    </View>

                    <View style={styles.statsContainer}>
                      <View style={styles.statBox}>
                        <Text style={styles.statNumber}>{liveCategories.length}</Text>
                        <Text style={styles.statLabel}>Live Categories</Text>
                      </View>
                      <View style={styles.statBox}>
                        <Text style={styles.statNumber}>{vodCategories.length}</Text>
                        <Text style={styles.statLabel}>VOD Categories</Text>
                      </View>
                      <View style={styles.statBox}>
                        <Text style={styles.statNumber}>{seriesCategories.length}</Text>
                        <Text style={styles.statLabel}>Series Categories</Text>
                      </View>
                    </View>

                    <SpatialNavigationNode orientation="vertical">
                      <DefaultFocus>
                        <FocusablePressable
                          text="Disconnect"
                          onSelect={handleDisconnect}
                          style={styles.disconnectButton}
                        />
                      </DefaultFocus>
                    </SpatialNavigationNode>
                  </View>
                ) : (
                  // Not connected state
                  <View style={styles.connectionForm}>
                    {error && (
                      <View style={styles.errorContainer}>
                        <Text style={styles.errorText}>{error}</Text>
                      </View>
                    )}

                    <SpatialNavigationNode orientation="vertical">
                      <>
                      <View style={styles.inputGroup}>
                        <Text style={styles.inputLabel}>Server URL</Text>
                        <DefaultFocus>
                          <SpatialNavigationFocusableView
                            onFocus={() => setFocusedInput('server')}
                            onBlur={() => setFocusedInput(null)}
                            onSelect={() => serverInputRef.current?.focus()}
                          >
                            {({ isFocused: inputFocused }) => (
                              <TextInput
                                ref={serverInputRef}
                                style={[styles.textInput, inputFocused && styles.textInputFocused]}
                                value={server}
                                onChangeText={setServer}
                                placeholder="http://example.com:8080"
                                placeholderTextColor={colors.textSecondary}
                                autoCapitalize="none"
                                autoCorrect={false}
                              />
                            )}
                          </SpatialNavigationFocusableView>
                        </DefaultFocus>
                      </View>

                      <View style={styles.inputGroup}>
                        <Text style={styles.inputLabel}>Username</Text>
                        <SpatialNavigationFocusableView
                          onFocus={() => setFocusedInput('username')}
                          onBlur={() => setFocusedInput(null)}
                          onSelect={() => usernameInputRef.current?.focus()}
                        >
                          {({ isFocused: inputFocused }) => (
                            <TextInput
                              ref={usernameInputRef}
                              style={[styles.textInput, inputFocused && styles.textInputFocused]}
                              value={username}
                              onChangeText={setUsername}
                              placeholder="Enter username"
                              placeholderTextColor={colors.textSecondary}
                              autoCapitalize="none"
                              autoCorrect={false}
                            />
                          )}
                        </SpatialNavigationFocusableView>
                      </View>

                      <View style={styles.inputGroup}>
                        <Text style={styles.inputLabel}>Password</Text>
                        <SpatialNavigationFocusableView
                          onFocus={() => setFocusedInput('password')}
                          onBlur={() => setFocusedInput(null)}
                          onSelect={() => passwordInputRef.current?.focus()}
                        >
                          {({ isFocused: inputFocused }) => (
                            <TextInput
                              ref={passwordInputRef}
                              style={[styles.textInput, inputFocused && styles.textInputFocused]}
                              value={password}
                              onChangeText={setPassword}
                              placeholder="Enter password"
                              placeholderTextColor={colors.textSecondary}
                              secureTextEntry
                              autoCapitalize="none"
                              autoCorrect={false}
                            />
                          )}
                        </SpatialNavigationFocusableView>
                      </View>

                      <FocusablePressable
                        text={isLoading ? 'Connecting...' : 'Connect'}
                        onSelect={handleConnect}
                        style={styles.connectButton}
                      />
                      </>
                    </SpatialNavigationNode>
                  </View>
                )}
              </View>
            </View>
          </SpatialNavigationScrollView>
        </View>
      </View>
    </SpatialNavigationRoot>
  );
}

const styles = StyleSheet.create({
  container: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: colors.background,
    zIndex: 100,
  },
  innerContainer: {
    flex: 1,
    paddingTop: scaledPixels(safeZones.actionSafe.vertical),
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: scaledPixels(safeZones.titleSafe.horizontal),
    paddingTop: scaledPixels(16),
    paddingBottom: scaledPixels(safeZones.actionSafe.vertical + 60),
  },
  title: {
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    color: colors.text,
    paddingHorizontal: scaledPixels(safeZones.titleSafe.horizontal),
    marginBottom: scaledPixels(32),
  },
  section: {
    marginBottom: scaledPixels(40),
  },
  sectionTitle: {
    fontSize: scaledPixels(28),
    fontWeight: '600',
    color: colors.text,
    marginBottom: scaledPixels(20),
  },
  connectionInfo: {
    gap: scaledPixels(24),
  },
  connectionForm: {
    gap: scaledPixels(16),
  },
  statusRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(12),
  },
  statusDot: {
    width: scaledPixels(16),
    height: scaledPixels(16),
    borderRadius: scaledPixels(8),
    backgroundColor: '#22c55e',
  },
  statusText: {
    fontSize: scaledPixels(24),
    fontWeight: '600',
    color: '#22c55e',
  },
  statsContainer: {
    flexDirection: 'row',
    gap: scaledPixels(16),
  },
  statBox: {
    flex: 1,
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(20),
    alignItems: 'center',
  },
  statNumber: {
    fontSize: scaledPixels(36),
    fontWeight: 'bold',
    color: colors.primary,
  },
  statLabel: {
    fontSize: scaledPixels(16),
    color: colors.textSecondary,
    marginTop: scaledPixels(4),
  },
  infoContainer: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(24),
    gap: scaledPixels(16),
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  infoLabel: {
    fontSize: scaledPixels(24),
    color: colors.textSecondary,
    fontWeight: '500',
  },
  infoValue: {
    fontSize: scaledPixels(24),
    color: colors.text,
    fontWeight: '600',
  },
  errorContainer: {
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    borderRadius: scaledPixels(8),
    padding: scaledPixels(16),
    borderWidth: 1,
    borderColor: '#ef4444',
  },
  errorText: {
    fontSize: scaledPixels(20),
    color: '#ef4444',
  },
  inputGroup: {
    marginBottom: scaledPixels(16),
  },
  inputLabel: {
    fontSize: scaledPixels(20),
    color: colors.text,
    marginBottom: scaledPixels(8),
    fontWeight: '500',
  },
  textInput: {
    backgroundColor: colors.card,
    borderRadius: scaledPixels(8),
    padding: scaledPixels(16),
    fontSize: scaledPixels(22),
    color: colors.text,
    borderWidth: scaledPixels(2),
    borderColor: 'transparent',
  },
  textInputFocused: {
    borderColor: colors.focusBorder,
  },
  connectButton: {
    marginTop: scaledPixels(16),
    backgroundColor: colors.primary,
  },
  disconnectButton: {
    backgroundColor: '#ef4444',
  },
});
