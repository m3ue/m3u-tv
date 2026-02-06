import React, { useEffect, useState, useCallback } from 'react';
import { View, Text, StyleSheet, Image, ScrollView, ImageBackground } from 'react-native';
import { useXtream } from '../context/XtreamContext';
import { colors, spacing, typography } from '../theme';
import { RootStackScreenProps } from '../navigation/types';
import { XtreamVodInfo } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { LinearGradient } from 'expo-linear-gradient';

export const MovieDetailsScreen = ({ route, navigation }: RootStackScreenProps<'Details'>) => {
    const { item } = route.params;
    const { fetchVodInfo, getVodStreamUrl } = useXtream();
    const [movieInfo, setMovieInfo] = useState<XtreamVodInfo | null>(null);
    const [isLoading, setIsLoading] = useState(true);

    useEffect(() => {
        const loadInfo = async () => {
            try {
                const info = await fetchVodInfo(item.stream_id);
                setMovieInfo(info);
            } catch (error) {
                console.error('Failed to fetch movie info:', error);
            } finally {
                setIsLoading(false);
            }
        };
        loadInfo();
    }, [item.stream_id]);

    const handlePlay = useCallback(() => {
        const streamUrl = getVodStreamUrl(item.stream_id, item.container_extension);
        navigation.navigate('Player', {
            streamUrl,
            title: item.name,
            type: 'vod',
        });
    }, [item, navigation, getVodStreamUrl]);

    const info = movieInfo?.info;
    const backdrop = info?.backdrop_path?.[0] || item.stream_icon;

    return (
        <View style={styles.container}>
            <ImageBackground
                source={{ uri: backdrop }}
                style={styles.backdrop}
                blurRadius={10}
            >
                <LinearGradient
                    colors={['rgba(0,0,0,0.5)', colors.background]}
                    style={styles.gradient}
                >
                    <ScrollView contentContainerStyle={styles.scrollContent}>
                        <View style={styles.header}>
                            <Image
                                source={{ uri: item.stream_icon }}
                                style={styles.poster}
                                resizeMode="cover"
                            />
                            <View style={styles.mainInfo}>
                                <Text style={styles.title}>{item.name}</Text>

                                <View style={styles.metaRow}>
                                    {info?.release_date && <Text style={styles.metaText}>{info.release_date.split('-')[0]}</Text>}
                                    {info?.duration && <Text style={styles.metaText}>{info.duration}</Text>}
                                    {info?.rating && <Text style={styles.rating}>★ {info.rating}</Text>}
                                </View>

                                {info?.genre && <Text style={styles.genre}>{info.genre}</Text>}

                                <View style={styles.buttonRow}>
                                    <FocusablePressable
                                        onSelect={handlePlay}
                                        style={({ isFocused }) => [
                                            styles.playButton,
                                            isFocused && styles.buttonFocused
                                        ]}
                                    >
                                        <Icon name="Play" size={scaledPixels(24)} color={colors.text} />
                                        <Text style={styles.buttonText}>Watch Now</Text>
                                    </FocusablePressable>
                                </View>
                            </View>
                        </View>

                        <View style={styles.detailsSection}>
                            <Text style={styles.sectionTitle}>Plot Summary</Text>
                            <Text style={styles.plot}>{info?.plot || 'No summary available.'}</Text>

                            {info?.director && (
                                <View style={styles.detailItem}>
                                    <Text style={styles.detailLabel}>Director</Text>
                                    <Text style={styles.detailValue}>{info.director}</Text>
                                </View>
                            )}

                            {info?.actors && (
                                <View style={styles.detailItem}>
                                    <Text style={styles.detailLabel}>Cast</Text>
                                    <Text style={styles.detailValue}>{info.actors}</Text>
                                </View>
                            )}
                        </View>
                    </ScrollView>
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
        paddingTop: scaledPixels(60),
    },
    scrollContent: {
        paddingBottom: scaledPixels(100),
    },
    header: {
        flexDirection: 'row',
        marginBottom: scaledPixels(40),
    },
    poster: {
        width: scaledPixels(300),
        height: scaledPixels(450),
        borderRadius: scaledPixels(12),
        borderWidth: 2,
        borderColor: 'rgba(255,255,255,0.1)',
    },
    mainInfo: {
        flex: 1,
        marginLeft: scaledPixels(40),
        justifyContent: 'center',
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
        marginBottom: scaledPixels(10),
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
    genre: {
        color: colors.primary,
        fontSize: scaledPixels(18),
        marginBottom: scaledPixels(30),
    },
    buttonRow: {
        flexDirection: 'row',
    },
    playButton: {
        flexDirection: 'row',
        alignItems: 'center',
        backgroundColor: 'rgba(255,255,255,0.1)',
        paddingVertical: scaledPixels(15),
        paddingHorizontal: scaledPixels(30),
        borderRadius: scaledPixels(8),
    },
    buttonFocused: {
        backgroundColor: colors.primary,
        transform: [{ scale: 1.05 }],
    },
    buttonText: {
        color: colors.text,
        fontSize: scaledPixels(20),
        fontWeight: 'bold',
        marginLeft: scaledPixels(10),
    },
    detailsSection: {
        marginTop: scaledPixels(40),
    },
    sectionTitle: {
        fontSize: scaledPixels(28),
        color: colors.text,
        fontWeight: 'bold',
        marginBottom: scaledPixels(15),
    },
    plot: {
        fontSize: scaledPixels(20),
        color: colors.textSecondary,
        lineHeight: scaledPixels(30),
        marginBottom: scaledPixels(30),
    },
    detailItem: {
        marginBottom: scaledPixels(15),
    },
    detailLabel: {
        fontSize: scaledPixels(18),
        color: colors.textTertiary,
        marginBottom: scaledPixels(5),
    },
    detailValue: {
        fontSize: scaledPixels(20),
        color: colors.text,
    },
});
