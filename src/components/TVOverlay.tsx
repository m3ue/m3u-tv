import React from 'react';
import { View, StyleSheet } from 'react-native';

interface TVOverlayProps {
  visible: boolean;
  onClose?: () => void;
  children: React.ReactNode;
}

export function TVOverlay({ visible, children }: TVOverlayProps) {
  if (!visible) return null;
  return <View style={styles.overlay}>{children}</View>;
}

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.85)',
    justifyContent: 'center',
    alignItems: 'center',
    zIndex: 100,
  },
});
