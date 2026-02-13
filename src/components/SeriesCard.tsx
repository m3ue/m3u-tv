import React from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { FocusablePressable } from './FocusablePressable';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { XtreamSeries } from '../types/xtream';
import { RootStackParamList } from '../navigation/types';

const CARD_WIDTH = scaledPixels(200);
const CARD_MARGIN = scaledPixels(12);

interface SeriesCardProps {
  item: XtreamSeries;
  nextFocusLeft?: number;
}

export function SeriesCard({ item, nextFocusLeft }: SeriesCardProps) {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();

  return (
    <FocusablePressable
      nextFocusLeft={nextFocusLeft}
      style={({ isFocused }) => [styles.seriesCard, isFocused && styles.seriesCardFocused]}
      onSelect={() => {
        navigation.navigate('SeriesDetails', { item });
      }}
    >
      <Image
        source={{ uri: item.cover || 'https://via.placeholder.com/150x225' }}
        style={styles.seriesPoster}
        resizeMode="cover"
      />
      <View style={styles.seriesInfo}>
        <Text style={styles.seriesName} numberOfLines={1}>
          {item.name}
        </Text>
        <View style={styles.seriesMeta}>
          <Text style={styles.seriesRating}>★ {item.rating || 'N/A'}</Text>
          {(item.release_date || item.releaseDate) && (
            <Text style={styles.seriesYear}>{(item.release_date || item.releaseDate)?.substring(0, 4)}</Text>
          )}
        </View>
      </View>
    </FocusablePressable>
  );
}

const styles = StyleSheet.create({
  seriesCard: {
    width: CARD_WIDTH,
    margin: CARD_MARGIN,
    backgroundColor: colors.card,
    borderRadius: scaledPixels(12),
    borderWidth: 3,
    borderColor: 'transparent',
  },
  seriesCardFocused: {
    borderColor: colors.primary,
    transform: [{ scale: 1.08 }],
    zIndex: 10,
    shadowColor: colors.primary,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.6,
    shadowRadius: 15,
    elevation: 10,
  },
  seriesPoster: {
    width: '100%',
    borderRadius: scaledPixels(12),
    aspectRatio: 2 / 3,
  },
  seriesInfo: {
    padding: scaledPixels(12),
  },
  seriesName: {
    color: colors.text,
    fontSize: scaledPixels(16),
    fontWeight: '500',
  },
  seriesMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: scaledPixels(8),
    marginTop: scaledPixels(4),
  },
  seriesRating: {
    color: colors.warning,
    fontSize: scaledPixels(14),
  },
  seriesYear: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
  },
});
