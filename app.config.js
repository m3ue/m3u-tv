const IS_TV = process.env.EXPO_TV === '1';

const tvPlugins = IS_TV
  ? [
      [
        '@react-native-tvos/config-tv',
        {
          androidTVBanner: './assets/tv_icons/icon-400x240.png',
          appleTVImages: {
            icon: './assets/tv_icons/icon-1280x768.png',
            iconSmall: './assets/tv_icons/icon-400x240.png',
            iconSmall2x: './assets/tv_icons/icon-800x480.png',
            topShelf: './assets/tv_icons/icon-1920x720.png',
            topShelf2x: './assets/tv_icons/icon-3840x1440.png',
            topShelfWide: './assets/tv_icons/icon-2320x720.png',
            topShelfWide2x: './assets/tv_icons/icon-4640x1440.png',
          },
        },
      ],
    ]
  : [];

/** @type {import('expo/config').ExpoConfig} */
const config = {
  name: 'M3U TV',
  slug: 'm3u-tv',
  scheme: 'dev.sparkison.tv',
  version: '0.0.1',
  orientation: IS_TV ? 'landscape' : 'default',
  icon: './assets/icon.png',
  userInterfaceStyle: 'dark',
  newArchEnabled: true,
  splash: {
    image: './assets/splash.png',
    resizeMode: 'contain',
    backgroundColor: '#000000',
  },
  android: {
    package: 'dev.sparkison.tv',
    isTV: IS_TV,
    edgeToEdgeEnabled: true,
    adaptiveIcon: {
      foregroundImage: './assets/adaptive-icon.png',
      backgroundColor: '#000000',
    },
  },
  ios: {
    bundleIdentifier: 'dev.sparkison.tv',
    supportsTablet: true,
    infoPlist: {
      NSAppTransportSecurity: {
        NSAllowsArbitraryLoads: true,
      },
    },
  },
  web: {
    favicon: './favicon.png',
    bundler: 'metro',
  },
  plugins: [
    ...tvPlugins,
    [
      'expo-build-properties',
      {
        android: {
          minSdkVersion: 26,
          usesCleartextTraffic: true,
        },
        ios: {
          deploymentTarget: '16.0',
        },
      },
    ],
    'expo-secure-store',
    './plugins/withAndroidSigning',
    './plugins/withMpvPlayer',
  ],
};

module.exports = { expo: config };
