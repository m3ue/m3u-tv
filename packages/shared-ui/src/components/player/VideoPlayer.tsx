import React, { useMemo } from 'react';
import Video, { VideoRef } from 'react-native-video';
import { StyleSheet, Platform, useWindowDimensions } from 'react-native';

interface VideoPlayerProps {
  movie: string;
  headerImage: string;
  paused: boolean;
  controls: boolean;
  onBuffer: (isBuffering: boolean) => void;
  onProgress: (currentTime: number) => void;
  onLoad: (duration: number) => void;
  onEnd: () => void;
}

const VideoPlayer = React.memo(
  React.forwardRef<VideoRef, VideoPlayerProps>(
    ({ movie, headerImage, paused, controls, onBuffer, onProgress, onLoad, onEnd }, ref) => {
      const { width } = useWindowDimensions();

      // Memoize source object to prevent unnecessary re-renders
      const videoSource = useMemo(() => ({ uri: movie }), [movie]);

      // Memoize poster config - just use the URI string for simplicity
      const posterConfig = useMemo(
        () => (Platform.OS === 'web' ? undefined : headerImage),
        [headerImage],
      );

      // Calculate video style based on current dimensions
      const videoStyle = useMemo(() => [videoPlayerStyles.video, { height: width * (9 / 16) }], [width]);

      return (
        <Video
          ref={ref}
          source={videoSource}
          style={videoStyle}
          controls={controls}
          paused={paused}
          onBuffer={({ isBuffering }) => onBuffer(isBuffering)}
          onProgress={({ currentTime }) => onProgress(currentTime)}
          onLoad={({ duration }) => onLoad(duration)}
          onEnd={onEnd}
          poster={posterConfig}
          resizeMode="cover"
        />
      );
    },
  ),
);

const videoPlayerStyles = StyleSheet.create({
  video: {
    width: '100%',
  },
});

export default VideoPlayer;
