import React from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { FocusablePressable } from './FocusablePressable';
import { useXtream } from '../context/XtreamContext';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { XtreamLiveStream } from '../types/xtream';
import { RootStackParamList } from '../navigation/types';

interface LiveTVCardProps {
  item: XtreamLiveStream;
}

export function LiveTVCard({ item }: LiveTVCardProps) {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const { getLiveStreamUrl } = useXtream();

  return (
    <FocusablePressable
      style={({ isFocused }) => [styles.channelCard, isFocused && styles.channelCardFocused]}
      onSelect={() => {
        console.log(`[LiveTVCard] Selected: ${item.name} (${item.stream_id})`);
        const streamUrl = getLiveStreamUrl(item.stream_id);
        navigation.navigate('Player', {
          streamUrl,
          title: item.name,
          type: 'live',
        });
      }}
    >
      <Image
        source={{ uri: item.stream_icon || 'https://via.placeholder.com/80' }}
        style={styles.channelIcon}
        resizeMode="contain"
      />
      <Text style={styles.channelName} numberOfLines={2}>
        {item.name}
      </Text>
    </FocusablePressable>
  );
}

const styles = StyleSheet.create({
  channelCard: {
    width: scaledPixels(200),
    height: scaledPixels(200),
    margin: scaledPixels(12),
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    padding: scaledPixels(15),
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 3,
    borderColor: 'transparent',
  },
  channelCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  channelIcon: {
    width: scaledPixels(120),
    height: scaledPixels(120),
    marginBottom: scaledPixels(10),
  },
  channelName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    textAlign: 'center',
  },
});
