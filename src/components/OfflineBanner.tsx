import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { Icon } from './Icon';

export function OfflineBanner() {
  const { isConfigured, isServerUnreachable } = useXtream();

  if (!isConfigured || !isServerUnreachable) {
    return null;
  }

  return (
    <View style={styles.banner} pointerEvents="none">
      <Icon name="WifiOff" size={scaledPixels(22)} color={colors.textOnPrimary} />
      <Text style={styles.text}>Server unreachable — showing cached content</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    position: 'absolute',
    bottom: scaledPixels(24),
    alignSelf: 'center',
    width: '80%',
    backgroundColor: 'rgba(236, 0, 63, 0.92)',
    borderRadius: scaledPixels(10),
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(12),
    paddingHorizontal: scaledPixels(24),
    paddingVertical: scaledPixels(14),
    zIndex: 9999,
  },
  text: {
    color: colors.textOnPrimary,
    fontSize: scaledPixels(20),
    fontWeight: '600',
  },
});
