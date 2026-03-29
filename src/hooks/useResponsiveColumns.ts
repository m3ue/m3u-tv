import { useMemo } from 'react';
import { Platform, useWindowDimensions } from 'react-native';
import { scaledPixels } from './useScale';

const CARD_CELL_WIDTH = scaledPixels(200) + scaledPixels(12) * 2;

export function useResponsiveColumns(fallbackTv = 8): number {
  const { width } = useWindowDimensions();
  return useMemo(() => {
    if (Platform.isTV) return fallbackTv;
    const available = width - scaledPixels(40);
    return Math.max(2, Math.floor(available / CARD_CELL_WIDTH));
  }, [width, fallbackTv]);
}
