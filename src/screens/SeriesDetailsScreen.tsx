import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, Image, ScrollView, FlatList, ImageBackground, useWindowDimensions } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors, spacing, typography } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamSeriesInfo, XtreamEpisode } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';
import { DefaultFocus, SpatialNavigationNode, SpatialNavigationScrollView, SpatialNavigationView, SpatialNavigationVirtualizedList } from 'react-tv-space-navigation';

export const SeriesDetailsScreen = ({ route, navigation }: RootStackScreenProps<'SeriesDetails'>) => {
    const { item } = route.params;
    const { fetchSeriesInfo, getSeriesStreamUrl } = useXtream();
    const [seriesInfo, setSeriesInfo] = useState<XtreamSeriesInfo | null>(null);
    const [selectedSeason, setSelectedSeason] = useState<string | null>(null);

    const { width, height } = useWindowDimensions();

    useEffect(() => {
        const loadInfo = async () => {
            try {
                const info = await fetchSeriesInfo(item.series_id);
                setSeriesInfo(info);
                if (info.seasons && info.seasons.length > 0) {
                    setSelectedSeason(String(info.seasons[0].season_number));
                }
            } catch (error) {
                console.error('Failed to fetch series info:', error);
            }
        };
        loadInfo();
    }, [item.series_id]);

    const episodes = seriesInfo?.episodes[selectedSeason || ''] || [];

    const handlePlayEpisode = useCallback((episode: XtreamEpisode) => {
        const streamUrl = getSeriesStreamUrl(episode.id, episode.container_extension);
        navigation.navigate('Player', {
            streamUrl,
            title: episode.title,
            type: 'series',
        });
    }, [navigation, getSeriesStreamUrl]);

    return (
        <View style={styles.container}>
            <ImageBackground
                source={{ uri: item.cover }}
                style={styles.backdrop}
                blurRadius={5}
            >
                <LinearGradient
                    colors={['rgba(0,0,0,0.2)', 'rgba(0,0,0,0.8)', colors.background]}
                    style={styles.gradient}
                >
                    <View style={styles.content}>
                        <View style={styles.header}>
                            <View style={styles.mainInfo}>
                                <Text style={styles.title}>{item.name}</Text>
                                <View style={styles.metaRow}>
                                    {item.release_date && <Text style={styles.metaText}>{item.release_date.split('-')[0]}</Text>}
                                    <Text style={styles.rating}>★ {item.rating}</Text>
                                </View>
                                <Text style={styles.plot} numberOfLines={3}>{item.plot}</Text>
                            </View>
                        </View>

                        <SpatialNavigationNode orientation="horizontal">
                            <View style={styles.navigationSection}>
                                <View style={styles.seasonsColumn}>
                                    <Text style={styles.sectionTitle}>Seasons</Text>
                                    <SpatialNavigationNode>
                                        <SpatialNavigationScrollView>
                                            <SpatialNavigationView direction="vertical">
                                                {seriesInfo?.seasons.map((season) => (
                                                    <FocusablePressable
                                                        key={season.season_number}
                                                        onSelect={() => setSelectedSeason(String(season.season_number))}
                                                        style={({ isFocused }) => [
                                                            styles.seasonItem,
                                                            selectedSeason === String(season.season_number) && styles.seasonItemActive,
                                                            isFocused && styles.itemFocused
                                                        ]}
                                                    >
                                                        {({ isFocused }) => (
                                                            <Text style={[
                                                                styles.seasonText,
                                                                selectedSeason === String(season.season_number) && styles.seasonTextActive,
                                                                isFocused && styles.seasonTextActive,
                                                            ]}>
                                                                Season {season.season_number}
                                                            </Text>
                                                        )}
                                                    </FocusablePressable>
                                                ))}
                                            </SpatialNavigationView>
                                        </SpatialNavigationScrollView>
                                    </SpatialNavigationNode>
                                </View>

                                <View style={styles.episodesColumn}>
                                    <Text style={styles.sectionTitle}>Episodes</Text>
                                    <SpatialNavigationNode>
                                        <SpatialNavigationView direction="vertical" style={styles.episodesColumn}>
                                            <SpatialNavigationVirtualizedList
                                                data={episodes}
                                                itemSize={scaledPixels(200)}
                                                orientation="vertical"
                                                renderItem={({ item: ep }) => (
                                                    <FocusablePressable
                                                        onSelect={() => handlePlayEpisode(ep)}
                                                        style={({ isFocused }) => [
                                                            styles.episodeItem,
                                                            isFocused && styles.itemFocused,
                                                            { width: width - scaledPixels(450) }
                                                        ]}
                                                    >
                                                        <View style={styles.episodeMain}>
                                                            <Text style={styles.episodeNumber}>{ep.episode_num}</Text>
                                                            <Image
                                                                source={{ uri: ep.info?.movie_image || item.cover }}
                                                                style={styles.episodeImage}
                                                                resizeMode="contain"
                                                            />
                                                            <View style={styles.episodeInfo}>
                                                                <Text style={styles.episodeTitle} numberOfLines={1}>{ep.title}</Text>
                                                                <Text style={styles.episodePlot} numberOfLines={3}>{ep.info?.plot || 'No description available for this episode.'}</Text>
                                                            </View>
                                                            <Icon name="ChevronRight" size={scaledPixels(24)} color={colors.text} />
                                                        </View>
                                                    </FocusablePressable>
                                                )}
                                            />
                                        </SpatialNavigationView>
                                    </SpatialNavigationNode>
                                </View>
                            </View>
                        </SpatialNavigationNode>
                    </View>
                </LinearGradient>
            </ImageBackground>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: colors.background,
    },
    backdrop: {
        flex: 1,
    },
    gradient: {
        flex: 1,
        paddingHorizontal: scaledPixels(80),
        paddingTop: scaledPixels(40),
    },
    content: {
        flex: 1,
    },
    header: {
        marginBottom: scaledPixels(40),
    },
    mainInfo: {
        maxWidth: '70%',
    },
    title: {
        fontSize: scaledPixels(48),
        color: colors.text,
        fontWeight: 'bold',
        marginBottom: scaledPixels(10),
    },
    metaRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: scaledPixels(15),
    },
    metaText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(20),
        marginRight: scaledPixels(20),
    },
    rating: {
        color: '#ffcc00',
        fontSize: scaledPixels(20),
        fontWeight: 'bold',
    },
    plot: {
        fontSize: scaledPixels(20),
        color: colors.textSecondary,
        lineHeight: scaledPixels(30),
    },
    navigationSection: {
        flex: 1,
        flexDirection: 'row',
        marginTop: scaledPixels(20),
    },
    seasonsColumn: {
        width: scaledPixels(250),
        marginRight: scaledPixels(40),
    },
    episodesColumn: {
        flex: 1,
        overflow: 'hidden',
    },
    sectionTitle: {
        fontSize: scaledPixels(24),
        color: colors.text,
        fontWeight: 'bold',
        marginBottom: scaledPixels(20),
        textTransform: 'uppercase',
        letterSpacing: 1,
    },
    seasonItem: {
        paddingVertical: scaledPixels(15),
        paddingHorizontal: scaledPixels(20),
        borderRadius: scaledPixels(8),
        marginBottom: scaledPixels(10),
        backgroundColor: 'rgba(255,255,255,0.05)',
        overflow: 'hidden',
        borderWidth: 2,
        borderColor: 'transparent',
    },
    seasonItemActive: {
        backgroundColor: 'rgba(236, 0, 63, 0.2)',
        borderLeftWidth: 6,
        borderLeftColor: colors.primary,
    },
    seasonText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(20),
    },
    seasonTextActive: {
        color: colors.text,
        fontWeight: 'bold',
    },
    episodeItem: {
        backgroundColor: 'rgba(255,255,255,0.05)',
        borderRadius: scaledPixels(8),
        marginBottom: scaledPixels(10),
        padding: scaledPixels(20),
        borderWidth: 2,
        borderColor: 'transparent',
    },
    itemFocused: {
        borderColor: colors.primary,
    },
    episodeMain: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(20),
        height: scaledPixels(150),
    },
    episodeNumber: {
        fontSize: scaledPixels(24),
        color: colors.text,
        width: scaledPixels(50),
        fontWeight: 'bold',
    },
    episodeInfo: {
        flexDirection: 'column',
        alignItems: 'flex-start',
        flex: 1,
    },
    episodeTitle: {
        fontSize: scaledPixels(24),
        color: colors.textSecondary,
        marginTop: scaledPixels(32),
    },
    episodeImage: {
        width: scaledPixels(200),
        aspectRatio: 3 / 2,
    },
    episodePlot: {
        fontSize: scaledPixels(20),
        color: colors.text,
        lineHeight: scaledPixels(26),
        marginBottom: scaledPixels(40),
    },
    buttonFocused: {
        borderWidth: 2,
        borderColor: colors.text,
        transform: [{ scale: 1.05 }],
    },
    buttonText: {
        color: colors.text,
        fontSize: scaledPixels(20),
        fontWeight: 'bold',
        marginLeft: scaledPixels(10),
    },
});
