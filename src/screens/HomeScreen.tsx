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
    <SpatialNavigationNode>
      <View style={styles.container}>
      </View>
    </SpatialNavigationNode>
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
  buttonFocused: {
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
});
