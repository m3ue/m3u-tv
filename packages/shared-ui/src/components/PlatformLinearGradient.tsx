import React, { ReactNode } from 'react';
import { ViewStyle, StyleProp } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

/**
 * Platform-agnostic gradient component
 */

interface PlatformLinearGradientProps {
  colors: readonly [string, string, ...string[]];
  style?: StyleProp<ViewStyle>;
  start?: { x: number; y: number };
  end?: { x: number; y: number };
  locations?: readonly [number, number, ...number[]];
  children?: ReactNode;
}

const PlatformLinearGradient: React.FC<PlatformLinearGradientProps> = ({
  colors,
  style,
  start,
  end,
  locations,
  children,
}) => {
  return (
    <LinearGradient
      colors={colors}
      style={style}
      start={start}
      end={end}
      locations={locations}
    >
      {children}
    </LinearGradient>
  );
};

export default PlatformLinearGradient;
