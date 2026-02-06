import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, Image, ScrollView, FlatList, Modal, ImageBackground } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors, spacing, typography } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamSeriesInfo, XtreamEpisode } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';
import { SpatialNavigationNode, DefaultFocus } from 'react-tv-space-navigation';

export const SeriesDetailsScreen = ({ route, navigation }: RootStackScreenProps<'SeriesDetails'>) => {
    const { item } = route.params;
    const { fetchSeriesInfo, getSeriesStreamUrl } = useXtream();
    const [seriesInfo, setSeriesInfo] = useState<XtreamSeriesInfo | null>(null);
    const [selectedSeason, setSelectedSeason] = useState<string | null>(null);
    const [selectedEpisode, setSelectedEpisode] = useState<XtreamEpisode | null>(null);
    const [isModalVisible, setIsModalVisible] = useState(false);

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
                blurRadius={10}
            >
                <LinearGradient
                    colors={['rgba(0,0,0,0.6)', colors.background]}
                    style={styles.gradient}
                >
                    <View style={styles.content}>
                        <View style={styles.header}>
                            <View style={styles.mainInfo}>
                                <Text style={styles.title}>{item.name}</Text>
                                <View style={styles.metaRow}>
                                    {item.release_date && <Text style={styles.metaText}>{item.release_date.split('-')[0]}</Text>}
                                    <Text style={styles.rating}>★ {item.rating_5based.toFixed(1)}</Text>
                                </View>
                                <Text style={styles.plot} numberOfLines={3}>{item.plot}</Text>
                            </View>
                        </View>

                        <View style={styles.navigationSection}>
                            <View style={styles.seasonsColumn}>
                                <Text style={styles.sectionTitle}>Seasons</Text>
                                <SpatialNavigationNode>
                                    <ScrollView showsVerticalScrollIndicator={false}>
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
                                                <Text style={[
                                                    styles.seasonText,
                                                    selectedSeason === String(season.season_number) && styles.seasonTextActive
                                                ]}>
                                                    Season {season.season_number}
                                                </Text>
                                            </FocusablePressable>
                                        ))}
                                    </ScrollView>
                                </SpatialNavigationNode>
                            </View>

                            <View style={styles.episodesColumn}>
                                <Text style={styles.sectionTitle}>Episodes</Text>
                                <SpatialNavigationNode>
                                    <FlatList
                                        data={episodes}
                                        keyExtractor={(ep) => ep.id}
                                        renderItem={({ item: ep }) => (
                                            <FocusablePressable
                                                onSelect={() => {
                                                    setSelectedEpisode(ep);
                                                    setIsModalVisible(true);
                                                }}
                                                style={({ isFocused }) => [
                                                    styles.episodeItem,
                                                    isFocused && styles.itemFocused
                                                ]}
                                            >
                                                <View style={styles.episodeMain}>
                                                    <Text style={styles.episodeNumber}>{ep.episode_num}</Text>
                                                    <View style={styles.episodeInfo}>
                                                        <Text style={styles.episodeTitle} numberOfLines={1}>{ep.title}</Text>
                                                    </View>
                                                    <Icon name="ChevronRight" size={scaledPixels(24)} color={colors.textTertiary} />
                                                </View>
                                            </FocusablePressable>
                                        )}
                                        showsVerticalScrollIndicator={false}
                                    />
                                </SpatialNavigationNode>
                            </View>
                        </View>
                    </View>
                </LinearGradient>
            </ImageBackground>

            {/* Episode Details Modal */}
            <Modal
                visible={isModalVisible}
                transparent={true}
                animationType="fade"
                onRequestClose={() => setIsModalVisible(false)}
            >
                <SpatialNavigationNode>
                    <View style={styles.modalOverlay}>
                        <View style={styles.modalContent}>
                            <Image
                                source={{ uri: selectedEpisode?.info?.movie_image || item.cover }}
                                style={styles.modalImage}
                                resizeMode="cover"
                            />
                            <View style={styles.modalBody}>
                                <Text style={styles.modalTitle}>{selectedEpisode?.title}</Text>
                                <Text style={styles.modalMeta}>Episode {selectedEpisode?.episode_num}</Text>
                                <Text style={styles.modalPlot}>{selectedEpisode?.info?.plot || 'No description available for this episode.'}</Text>

                                <View style={styles.modalButtons}>
                                    <SpatialNavigationNode orientation="horizontal">
                                        <DefaultFocus>
                                            <FocusablePressable
                                                onSelect={() => {
                                                    if (selectedEpisode) handlePlayEpisode(selectedEpisode);
                                                    setIsModalVisible(false);
                                                }}
                                                style={({ isFocused }) => [
                                                    styles.modalPlayButton,
                                                    isFocused && styles.buttonFocused
                                                ]}
                                            >
                                                <Icon name="Play" size={scaledPixels(24)} color={colors.text} />
                                                <Text style={styles.buttonText}>Play Episode</Text>
                                            </FocusablePressable>
                                        </DefaultFocus>
                                        <FocusablePressable
                                            onSelect={() => setIsModalVisible(false)}
                                            style={({ isFocused }) => [
                                                styles.modalCloseButton,
                                                isFocused && styles.buttonFocused
                                            ]}
                                        >
                                            <Text style={styles.buttonText}>Close</Text>
                                        </FocusablePressable>
                                    </SpatialNavigationNode>
                                </View>
                            </View>
                        </View>
                    </View>
                </SpatialNavigationNode>
            </Modal>
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
    },
    seasonItemActive: {
        backgroundColor: 'rgba(236, 0, 63, 0.2)',
        borderLeftWidth: 4,
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
    },
    itemFocused: {
        backgroundColor: colors.primary,
        transform: [{ scale: 1.02 }],
    },
    episodeMain: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    episodeNumber: {
        fontSize: scaledPixels(24),
        color: colors.textTertiary,
        width: scaledPixels(50),
        fontWeight: 'bold',
    },
    episodeInfo: {
        flex: 1,
    },
    episodeTitle: {
        fontSize: scaledPixels(22),
        color: colors.text,
        fontWeight: '500',
    },
    modalOverlay: {
        flex: 1,
        backgroundColor: 'rgba(0,0,0,0.85)',
        justifyContent: 'center',
        alignItems: 'center',
    },
    modalContent: {
        width: '60%',
        backgroundColor: colors.backgroundElevated,
        borderRadius: scaledPixels(15),
        overflow: 'hidden',
        flexDirection: 'row',
        maxHeight: '80%',
    },
    modalImage: {
        width: '40%',
        aspectRatio: 2 / 3,
    },
    modalBody: {
        flex: 1,
        padding: scaledPixels(40),
    },
    modalTitle: {
        fontSize: scaledPixels(32),
        color: colors.text,
        fontWeight: 'bold',
        marginBottom: scaledPixels(10),
    },
    modalMeta: {
        fontSize: scaledPixels(20),
        color: colors.primary,
        fontWeight: 'bold',
        marginBottom: scaledPixels(20),
    },
    modalPlot: {
        fontSize: scaledPixels(18),
        color: colors.textSecondary,
        lineHeight: scaledPixels(26),
        marginBottom: scaledPixels(40),
    },
    modalButtons: {
        flexDirection: 'row',
        marginTop: 'auto',
    },
    modalPlayButton: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: colors.primary,
        paddingVertical: scaledPixels(15),
        paddingHorizontal: scaledPixels(30),
        borderRadius: scaledPixels(8),
        marginRight: scaledPixels(20),
    },
    modalCloseButton: {
        backgroundColor: 'rgba(255,255,255,0.1)',
        paddingVertical: scaledPixels(15),
        paddingHorizontal: scaledPixels(30),
        borderRadius: scaledPixels(8),
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
