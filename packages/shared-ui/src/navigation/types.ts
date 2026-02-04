export type RootStackParamList = {
  DrawerNavigator: undefined;
  Details: {
    title: string;
    description: string;
    headerImage: string;
    movie: string;
    category?: string;
    genres?: string[];
    releaseYear?: number;
    rating?: number;
    ratingCount?: number;
    contentRating?: string;
    duration?: number;
  };
  Player: {
    movie: string;
    headerImage: string;
    title?: string;
    isLive?: boolean;
  };
  ChannelDetails: {
    streamId: number;
    name: string;
    icon: string;
    epgChannelId?: string;
  };
  VodDetails: {
    streamId: number;
    name: string;
    icon: string;
    extension: string;
  };
  SeriesDetails: {
    seriesId: number;
    name: string;
    cover: string;
    plot?: string;
    rating?: number;
    year?: string;
  };
  EpisodePlayer: {
    episodeId: string;
    title: string;
    extension: string;
    seriesName: string;
    seasonNumber: number;
    episodeNumber: number;
  };
};

export type DrawerParamList = {
  Home: undefined;
  LiveTV: undefined;
  VOD: undefined;
  Series: undefined;
  Settings: undefined;
};
