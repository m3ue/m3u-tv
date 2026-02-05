import React, { useCallback, useState, useEffect, useMemo } from 'react';
import { StyleSheet, View, Text, Image, ScrollView } from 'react-native';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import {
    SpatialNavigationRoot,
    SpatialNavigationNode,
    DefaultFocus,
} from 'react-tv-space-navigation';
import { xtreamService } from '../services/XtreamService';
import { XtreamVodInfo } from '../types/xtream';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList } from '../navigation/types';
import { colors, safeZones } from '../theme';
import LoadingIndicator from '../components/LoadingIndicator';
import FocusablePressable from '../components/FocusablePressable';
import PlatformLinearGradient from '../components/PlatformLinearGradient';

type MovieDetailsNavigationProp = NativeStackNavigationProp<RootStackParamList, 'VodDetails'>;
type MovieDetailsRouteProp = RouteProp<RootStackParamList, 'VodDetails'>;

export default function MovieDetailsScreen() {
    const navigation = useNavigation<MovieDetailsNavigationProp>();
    const route = useRoute<MovieDetailsRouteProp>();
    const { streamId, name, icon, extension, plot, rating, year, genre, director, cast, duration, backdrop } = route.params;

    const [movieInfo, setMovieInfo] = useState<XtreamVodInfo | null>(null);
    const [isLoading, setIsLoading] = useState(true);

    useEffect(() => {
        const loadMovieInfo = async () => {
            setIsLoading(true);
            try {
                const info = await xtreamService.getVodInfo(streamId);
                setMovieInfo(info);
            } catch (error) {
                console.error('Failed to load movie info:', error);
            } finally {
                setIsLoading(false);
            }
        };

        loadMovieInfo();
    }, [streamId]);

    const handlePlay = useCallback(() => {
        const streamUrl = xtreamService.getVodStreamUrl(streamId, extension);
        navigation.navigate('Player', {
            movie: streamUrl,
            headerImage: icon,
            title: name,
            isLive: false,
        });
    }, [navigation, streamId, extension, icon, name]);

    // Use passed params or info from getVodInfo
    const moviePlot = movieInfo?.info?.plot || movieInfo?.info?.description || plot;
    const movieRating = movieInfo?.info?.rating || rating;
    const movieYear = movieInfo?.info?.release_date?.substring(0, 4) || year;
    const movieGenre = movieInfo?.info?.genre || genre;
    const movieDirector = movieInfo?.info?.director || director;
    const movieCast = movieInfo?.info?.cast || movieInfo?.info?.actors || cast;
    const movieBackdrop = movieInfo?.info?.backdrop_path?.[0] || movieInfo?.info?.cover_big || backdrop;

    const movieDuration = useMemo(() => {
        if (movieInfo?.info?.duration_secs) {
            const totalSecs = typeof movieInfo.info.duration_secs === 'string'
                ? parseInt(movieInfo.info.duration_secs, 10)
                : movieInfo.info.duration_secs;
            const h = Math.floor(totalSecs / 3600);
            const m = Math.floor((totalSecs % 3600) / 60);
            return h > 0 ? `${h}h ${m}m` : `${m}m`;
        }
        return movieInfo?.info?.duration || duration;
    }, [movieInfo, duration]);

    if (isLoading) {
        return (
            <View style={styles.container}>
                <LoadingIndicator />
            </View>
        );
    }

    return (
        <SpatialNavigationRoot isActive={true}>
            <View style={styles.container}>
                {/* Backdrop */}
                <View style={styles.header}>
                    {movieBackdrop && (
                        <Image source={{ uri: movieBackdrop }} style={styles.backdrop} resizeMode="cover" />
                    )}
                    <PlatformLinearGradient
                        colors={['rgba(0,0,0,0.3)', 'rgba(0,0,0,0.7)', colors.background]}
                        style={styles.gradient}
                    />

                    <View style={styles.contentContainer}>
                        <View style={styles.mainInfo}>
                            <View style={styles.posterContainer}>
                                {icon ? (
                                    <Image source={{ uri: icon }} style={styles.poster} resizeMode="cover" />
                                ) : (
                                    <View style={styles.posterPlaceholder}>
                                        <Text style={styles.placeholderText}>No Poster</Text>
                                    </View>
                                )}
                            </View>

                            <View style={styles.detailsContainer}>
                                <Text style={styles.title}>{name}</Text>

                                <View style={styles.metaRow}>
                                    {movieYear && <Text style={styles.metaText}>{movieYear}</Text>}
                                    {movieGenre && <Text style={styles.metaText}>{movieGenre}</Text>}
                                    {movieRating && parseFloat(String(movieRating)) > 0 && (
                                        <Text style={styles.metaText}>★ {parseFloat(String(movieRating)).toFixed(1)}</Text>
                                    )}
                                    {movieDuration && <Text style={styles.metaText}>{movieDuration}</Text>}
                                </View>

                                {moviePlot && (
                                    <Text style={styles.plot} numberOfLines={5}>
                                        {moviePlot}
                                    </Text>
                                )}

                                <SpatialNavigationNode orientation="horizontal">
                                    <View style={styles.actionsRow}>
                                        <DefaultFocus>
                                            <FocusablePressable
                                                text="Play Movie"
                                                onSelect={handlePlay}
                                                style={styles.playButton}
                                            />
                                        </DefaultFocus>

                                        <FocusablePressable
                                            text="Back"
                                            onSelect={() => navigation.goBack()}
                                            style={styles.backButton}
                                        />
                                    </View>
                                </SpatialNavigationNode>

                                {(movieDirector || movieCast) && (
                                    <View style={styles.extraInfo}>
                                        {movieDirector && (
                                            <Text style={styles.extraInfoText}>
                                                <Text style={styles.extraInfoLabel}>Director: </Text>
                                                {movieDirector}
                                            </Text>
                                        )}
                                        {movieCast && (
                                            <Text style={styles.extraInfoText} numberOfLines={2}>
                                                <Text style={styles.extraInfoLabel}>Cast: </Text>
                                                {movieCast}
                                            </Text>
                                        )}
                                    </View>
                                )}
                            </View>
                        </View>
                    </View>
                </View>
            </View>
        </SpatialNavigationRoot>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: colors.background,
    },
    header: {
        flex: 1,
        position: 'relative',
    },
    backdrop: {
        ...StyleSheet.absoluteFillObject,
        opacity: 0.4,
    },
    gradient: {
        ...StyleSheet.absoluteFillObject,
    },
    contentContainer: {
        flex: 1,
        paddingHorizontal: scaledPixels(safeZones.actionSafe.horizontal),
        justifyContent: 'center',
    },
    mainInfo: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(40),
    },
    posterContainer: {
        width: scaledPixels(300),
        height: scaledPixels(450),
        borderRadius: scaledPixels(16),
        overflow: 'hidden',
        backgroundColor: colors.card,
        elevation: 10,
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 10 },
        shadowOpacity: 0.5,
        shadowRadius: 15,
    },
    poster: {
        width: '100%',
        height: '100%',
    },
    posterPlaceholder: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
    },
    placeholderText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(20),
    },
    detailsContainer: {
        flex: 1,
        paddingRight: scaledPixels(40),
    },
    title: {
        color: colors.text,
        fontSize: scaledPixels(52),
        fontWeight: 'bold',
        marginBottom: scaledPixels(16),
    },
    metaRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(20),
        marginBottom: scaledPixels(20),
    },
    metaText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(22),
        backgroundColor: 'rgba(255,255,255,0.1)',
        paddingHorizontal: scaledPixels(12),
        paddingVertical: scaledPixels(4),
        borderRadius: scaledPixels(8),
    },
    plot: {
        color: colors.textSecondary,
        fontSize: scaledPixels(20),
        lineHeight: scaledPixels(30),
        marginBottom: scaledPixels(32),
        maxWidth: '90%',
    },
    actionsRow: {
        gap: scaledPixels(16),
        marginBottom: scaledPixels(32),
    },
    playButton: {
        minWidth: scaledPixels(200),
    },
    backButton: {
        minWidth: scaledPixels(150),
    },
    extraInfo: {
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.1)',
        paddingTop: scaledPixels(16),
        gap: scaledPixels(8),
    },
    extraInfoText: {
        color: colors.text,
        fontSize: scaledPixels(18),
    },
    extraInfoLabel: {
        color: colors.textSecondary,
    },
});
