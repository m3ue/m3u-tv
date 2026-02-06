import React, { useEffect } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { SpatialNavigationNode, DefaultFocus } from 'react-tv-space-navigation';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { DrawerScreenPropsType } from '../navigation/types';

export function HomeScreen({ navigation }: DrawerScreenPropsType<'Home'>) {
  const { isConfigured, isLoading, loadSavedCredentials, liveCategories, vodCategories, seriesCategories } = useXtream();

  useEffect(() => {
    loadSavedCredentials();
  }, [loadSavedCredentials]);

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
        <Text style={styles.loadingText}>Connecting...</Text>
      </View>
    );
  }

  if (!isConfigured) {
    return (
      <View style={styles.container}>
        <Text style={styles.title}>Welcome to M3U TV</Text>
        <Text style={styles.subtitle}>Connect to your Xtream service to get started</Text>
        <SpatialNavigationNode orientation="horizontal">
          <DefaultFocus>
            <FocusablePressable
              style={({ isFocused }) => [
                styles.settingsButton,
                isFocused && styles.buttonFocused,
              ]}
              onSelect={() => navigation.navigate('Settings')}
            >
              {({ isFocused }) => (
                <Text style={[styles.settingsButtonText, isFocused && styles.buttonTextFocused]}>
                  Go to Settings
                </Text>
              )}
            </FocusablePressable>
          </DefaultFocus>
        </SpatialNavigationNode>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Welcome to M3U TV</Text>
      <Text style={styles.subtitle}>Your streaming service is connected</Text>

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

      <SpatialNavigationNode orientation="horizontal">
        <View style={styles.menuContainer}>
          <DefaultFocus>
            <FocusablePressable
              style={({ isFocused }) => [
                styles.menuButton,
                isFocused && styles.menuButtonFocused,
              ]}
              onSelect={() => navigation.navigate('LiveTV')}
            >
              {({ isFocused }) => (
                <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>
                  Live TV
                </Text>
              )}
            </FocusablePressable>
          </DefaultFocus>
          <FocusablePressable
            style={({ isFocused }) => [
              styles.menuButton,
              isFocused && styles.menuButtonFocused,
            ]}
            onSelect={() => navigation.navigate('EPG')}
          >
            {({ isFocused }) => (
              <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>
                EPG Guide
              </Text>
            )}
          </FocusablePressable>
          <FocusablePressable
            style={({ isFocused }) => [
              styles.menuButton,
              isFocused && styles.menuButtonFocused,
            ]}
            onSelect={() => navigation.navigate('VOD')}
          >
            {({ isFocused }) => (
              <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>
                Movies
              </Text>
            )}
          </FocusablePressable>
          <FocusablePressable
            style={({ isFocused }) => [
              styles.menuButton,
              isFocused && styles.menuButtonFocused,
            ]}
            onSelect={() => navigation.navigate('Series')}
          >
            {({ isFocused }) => (
              <Text style={[styles.menuButtonText, isFocused && styles.buttonTextFocused]}>
                TV Series
              </Text>
            )}
          </FocusablePressable>
        </View>
      </SpatialNavigationNode>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
    padding: scaledPixels(40),
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingContainer: {
    flex: 1,
    backgroundColor: colors.background,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: colors.textSecondary,
    fontSize: scaledPixels(24),
    marginTop: scaledPixels(20),
  },
  title: {
    fontSize: scaledPixels(48),
    fontWeight: 'bold',
    color: colors.text,
    textAlign: 'center',
    marginBottom: scaledPixels(8),
  },
  subtitle: {
    fontSize: scaledPixels(24),
    color: colors.textSecondary,
    textAlign: 'center',
    marginBottom: scaledPixels(60),
  },
  settingsButton: {
    backgroundColor: colors.primary,
    paddingHorizontal: scaledPixels(40),
    paddingVertical: scaledPixels(20),
    borderRadius: scaledPixels(12),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  settingsButtonText: {
    color: colors.textOnPrimary,
    fontSize: scaledPixels(24),
    fontWeight: '600',
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
  buttonFocused: {
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
  buttonTextFocused: {
    color: colors.textOnPrimary,
  },
});
