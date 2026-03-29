import { useState, useEffect } from 'react';
import { Platform, Dimensions } from 'react-native';

export type DeviceType = 'tv' | 'desktop' | 'tablet' | 'phone';

function getDeviceType(): DeviceType {
  if (Platform.isTV) {
    return 'tv';
  }

  if (Platform.OS === 'web') {
    return 'desktop';
  }

  const { width, height } = Dimensions.get('window');
  const shortSide = Math.min(width, height);

  if (shortSide >= 600) {
    return 'tablet';
  }

  return 'phone';
}

export function useDeviceType(): DeviceType {
  const [deviceType, setDeviceType] = useState<DeviceType>(getDeviceType);

  useEffect(() => {
    const subscription = Dimensions.addEventListener('change', () => {
      setDeviceType(getDeviceType());
    });
    return () => subscription.remove();
  }, []);

  return deviceType;
}

export function useShouldUseSidebar(): boolean {
  const deviceType = useDeviceType();
  return deviceType === 'tv' || deviceType === 'desktop';
}
