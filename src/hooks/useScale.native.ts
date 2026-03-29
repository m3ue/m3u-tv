import { Platform } from 'react-native';
import { create } from 'react-native-pixel-perfect';

const designResolution = Platform.isTV
  ? { width: 1920, height: 1080 }
  : { width: 440, height: 960 };

export const scaledPixels = create(designResolution);
