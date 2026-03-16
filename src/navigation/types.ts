import { NativeStackScreenProps } from '@react-navigation/native-stack';
import { DrawerScreenProps } from '@react-navigation/drawer';
import { CompositeScreenProps, NavigatorScreenParams } from '@react-navigation/native';
import { XtreamVodStream, XtreamSeries } from '../types/xtream';

// Root Stack Navigator
export type RootStackParamList = {
  Main: NavigatorScreenParams<DrawerParamList>;
  Player: {
    streamUrl: string;
    title: string;
    type: 'live' | 'vod' | 'series';
    // Optional progress-tracking params (m3u-editor specific)
    streamId?: number;
    seriesId?: number;
    seasonNumber?: number;
    startPosition?: number; // seconds to seek to on start
  };
  Details: {
    item: XtreamVodStream;
  };
  SeriesDetails: {
    item: XtreamSeries;
  };
  ViewerSelection: undefined;
};

// Drawer Navigator
export type DrawerParamList = {
  Home: undefined;
  Search: undefined;
  LiveTV: undefined;
  VOD: undefined;
  Series: undefined;
  Settings: undefined;
};

// Screen Props
export type RootStackScreenProps<T extends keyof RootStackParamList> = NativeStackScreenProps<RootStackParamList, T>;

export type DrawerScreenPropsType<T extends keyof DrawerParamList> = CompositeScreenProps<
  DrawerScreenProps<DrawerParamList, T>,
  NativeStackScreenProps<RootStackParamList>
>;
