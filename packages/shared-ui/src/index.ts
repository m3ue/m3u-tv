// Main App Navigator
export { default as AppNavigator } from './navigation/AppNavigator';
export type { AppNavigatorProps } from './navigation/AppNavigator';

// Theme
export * from './theme';

// Components
export { default as FocusablePressable } from './components/FocusablePressable';
export { default as LoadingIndicator } from './components/LoadingIndicator';
export { MenuProvider, useMenuContext } from './components/MenuContext';
export { default as CustomDrawerContent } from './components/CustomDrawerContent';

// Screens
export { default as HomeScreen } from './screens/HomeScreen';
export { default as DetailsScreen } from './screens/DetailsScreen';
export { default as PlayerScreen } from './screens/PlayerScreen';
export { default as LiveTVScreen } from './screens/LiveTVScreen';
export { default as VODScreen } from './screens/VODScreen';
export { default as SeriesScreen } from './screens/SeriesScreen';
export { default as SeriesDetailsScreen } from './screens/SeriesDetailsScreen';
export { default as MovieDetailsScreen } from './screens/MovieDetailsScreen';
export { default as SettingsScreen } from './screens/SettingsScreen';

// EPG Components
export { default as EPGTimeline } from './components/EPGTimeline';

// Utils
export { VideoHandler } from './utils/VideoHandler';

// Navigation
export { default as RootNavigator } from './navigation/RootNavigator';
export { default as DrawerNavigator } from './navigation/DrawerNavigator';
export * from './navigation/types';

// Hooks
export { scaledPixels } from './hooks/useScale';

// Context
export { XtreamProvider, useXtream } from './context/XtreamContext';

// Services
export { xtreamService } from './services/XtreamService';

// Types
export * from './types/xtream';
