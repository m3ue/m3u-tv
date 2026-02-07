import React from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { FocusablePressable } from './FocusablePressable';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { XtreamVodStream } from '../types/xtream';
import { RootStackParamList } from '../navigation/types';

const CARD_WIDTH = scaledPixels(200);
const CARD_MARGIN = scaledPixels(12);

interface MovieCardProps {
  item: XtreamVodStream;
}

export function MovieCard({ item }: MovieCardProps) {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();

  return (
    <FocusablePressable
      style={({ isFocused }) => [
        styles.movieCard,
        isFocused && styles.movieCardFocused,
      ]}
      onSelect={() => {
        navigation.navigate('Details', { item });
      }}
    >
      <Image
        source={{ uri: item.stream_icon || 'https://via.placeholder.com/150x225' }}
        style={styles.moviePoster}
        resizeMode="cover"
      />
      <View style={styles.movieInfo}>
        <Text style={styles.movieName} numberOfLines={1}>
          {item.name}
        </Text>
        <Text style={styles.movieRating}>★ {item.rating || 'N/A'}</Text>
      </View>
    </FocusablePressable>
  );
}

const styles = StyleSheet.create({
  movieCard: {
    width: CARD_WIDTH,
    margin: CARD_MARGIN,
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    borderWidth: 3,
    borderColor: 'transparent',
  },
  movieCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  moviePoster: {
    width: '100%',
    aspectRatio: 2 / 3,
  },
  movieInfo: {
    padding: scaledPixels(12),
  },
  movieName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    fontWeight: '500',
  },
  movieRating: {
    color: colors.warning,
    fontSize: scaledPixels(14),
    marginTop: scaledPixels(4),
  },
});
