import React, { useMemo } from 'react';
import { StyleSheet, View, Text, Image } from 'react-native';
import { scaledPixels } from '../hooks/useScale';
import { colors } from '../theme';

export type MediaCardType = 'live' | 'vod' | 'series';

export interface MediaCardProps {
  name: string;
  image?: string;
  isFocused: boolean;
  type: MediaCardType;
  rating?: number;
  year?: string;
}

const MediaCard = React.memo(
  ({ name, image, isFocused, type, rating, year }: MediaCardProps) => {
    const imageSource = useMemo(
      () => (image ? { uri: image } : undefined),
      [image],
    );

    const placeholderEmoji = type === 'live' ? '📺' : type === 'vod' ? '🎬' : '📺';

    return (
      <View style={[styles.card, isFocused && styles.cardFocused]}>
        <View style={styles.posterContainer}>
          {imageSource ? (
            <Image source={imageSource} style={styles.posterImage} resizeMode="cover" />
          ) : (
            <View style={styles.placeholder}>
              <Text style={styles.placeholderText}>{placeholderEmoji}</Text>
            </View>
          )}
          {rating !== undefined && rating > 0 && (
            <View style={styles.ratingBadge}>
              <Text style={styles.ratingText}>★ {rating.toFixed(1)}</Text>
            </View>
          )}
        </View>
        <View style={styles.infoContainer}>
          <Text style={styles.title} numberOfLines={2}>
            {name}
          </Text>
          {year && (
            <Text style={styles.year}>{year}</Text>
          )}
        </View>
      </View>
    );
  },
);

MediaCard.displayName = 'MediaCard';

export const MEDIA_CARD_WIDTH = scaledPixels(200);
export const MEDIA_CARD_HEIGHT = scaledPixels(340);
export const MEDIA_CARD_MARGIN = scaledPixels(20);

const styles = StyleSheet.create({
  card: {
    width: MEDIA_CARD_WIDTH,
    height: MEDIA_CARD_HEIGHT,
    marginRight: MEDIA_CARD_MARGIN,
    borderRadius: scaledPixels(12),
    overflow: 'hidden',
    backgroundColor: colors.card,
    borderWidth: scaledPixels(3),
    borderColor: 'transparent',
  },
  cardFocused: {
    borderColor: colors.focusBorder,
    transform: [{ scale: 1.05 }],
    shadowColor: colors.focusGlow,
    shadowOffset: { width: 0, height: scaledPixels(4) },
    shadowOpacity: 0.3,
    shadowRadius: scaledPixels(12),
    elevation: 8,
  },
  posterContainer: {
    width: '100%',
    height: scaledPixels(260),
    backgroundColor: colors.cardElevated,
    position: 'relative',
  },
  posterImage: {
    width: '100%',
    height: '100%',
  },
  placeholder: {
    width: '100%',
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.cardElevated,
  },
  placeholderText: {
    fontSize: scaledPixels(48),
  },
  ratingBadge: {
    position: 'absolute',
    top: scaledPixels(8),
    right: scaledPixels(8),
    backgroundColor: 'rgba(0, 0, 0, 0.7)',
    paddingHorizontal: scaledPixels(8),
    paddingVertical: scaledPixels(4),
    borderRadius: scaledPixels(4),
  },
  ratingText: {
    color: '#fbbf24',
    fontSize: scaledPixels(16),
    fontWeight: 'bold',
  },
  infoContainer: {
    flex: 1,
    padding: scaledPixels(12),
    justifyContent: 'center',
  },
  title: {
    color: colors.text,
    fontSize: scaledPixels(18),
    fontWeight: '500',
  },
  year: {
    color: colors.textSecondary,
    fontSize: scaledPixels(14),
    marginTop: scaledPixels(4),
  },
});

export default MediaCard;
