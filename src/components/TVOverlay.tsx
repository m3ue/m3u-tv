import React, { useEffect } from 'react';
import { View, StyleSheet } from 'react-native';
import { SpatialNavigationRoot, useLockSpatialNavigation } from 'react-tv-space-navigation';

interface TVOverlayProps {
  visible: boolean;
  onClose?: () => void;
  children: React.ReactNode;
}

/**
 * Locks the parent spatial navigation root while the overlay is visible,
 * so d-pad events only go to the overlay's own navigation root.
 */
function ParentLock({ visible }: { visible: boolean }) {
  const { lock, unlock } = useLockSpatialNavigation();

  useEffect(() => {
    if (visible) {
      lock();
      return () => unlock();
    }
  }, [visible, lock, unlock]);

  return null;
}

export function TVOverlay({ visible, children }: TVOverlayProps) {
  return (
    <>
      <ParentLock visible={visible} />
      {visible && (
        <SpatialNavigationRoot>
          <View style={styles.overlay}>{children}</View>
        </SpatialNavigationRoot>
      )}
    </>
  );
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
