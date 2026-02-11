import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Text, Animated, TVEventHandler, BackHandler } from 'react-native';
import Video, { OnLoadData, OnProgressData, OnVideoErrorData, ResizeMode, VideoRef } from 'react-native-video';
import { VLCPlayer } from 'react-native-vlc-media-player';
import { SpatialNavigationNode, SpatialNavigationNodeRef, SpatialNavigationRoot, SpatialNavigationView } from 'react-tv-space-navigation';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';

type PlayerBackend = 'native' | 'vlc';

export const PlayerScreenNew = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
  const { streamUrl, title, type } = route.params;

  return (
    <SpatialNavigationRoot>
      <SpatialNavigationView direction='horizontal' style={styles.container}>
        <Text style={{ color: "#ffffff" }}>Todo: Implement</Text>
      </SpatialNavigationView>
    </SpatialNavigationRoot>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
});
