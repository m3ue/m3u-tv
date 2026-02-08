import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Text, Animated } from 'react-native';
import Video, { OnLoadData, OnProgressData, OnVideoErrorData, ResizeMode, VideoRef } from 'react-native-video';
import { VLCPlayer } from 'react-native-vlc-media-player';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';
import { DefaultFocus, SpatialNavigationView, SpatialNavigationNode } from 'react-tv-space-navigation';

const OVERLAY_TIMEOUT = 8000;
const SEEK_STEP = 10; // seconds
const USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

// Formats that AVPlayer can't handle - send directly to VLC
const VLC_ONLY_EXTENSIONS = ['.avi', '.mkv', '.wmv', '.flv', '.rmvb', '.rm', '.asf', '.divx', '.ogm'];

type PlayerBackend = 'native' | 'vlc';

function getInitialBackend(url: string): PlayerBackend {
    const path = url.split('?')[0].toLowerCase();
    if (VLC_ONLY_EXTENSIONS.some((ext) => path.endsWith(ext))) {
        return 'vlc';
    }
    return 'native';
}

function formatTime(seconds: number): string {
    const s = Math.max(0, Math.floor(seconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const pad = (n: number) => n.toString().padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title, type } = route.params;
    const initialBackend = useMemo(() => getInitialBackend(streamUrl), [streamUrl]);
    const [backend, setBackend] = useState<PlayerBackend>(initialBackend);

    // Playback state
    const [paused, setPaused] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);
    const isLive = type === 'live';

    // Refs
    const nativeRef = useRef<VideoRef>(null);
    const vlcSeekTo = useRef<number | undefined>(undefined);
    const [vlcSeekValue, setVlcSeekValue] = useState<number | undefined>(undefined);

    // Overlay state
    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    // --- Player error handling ---

    const handleNativeError = useCallback((error: OnVideoErrorData) => {
        console.warn('[Player] react-native-video error, falling back to VLC:', error.error);
        setBackend('vlc');
    }, []);

    const handleVlcError = useCallback(() => {
        console.error('[Player] VLC also failed to play stream');
    }, []);

    // --- Progress tracking ---

    const handleNativeLoad = useCallback((data: OnLoadData) => {
        console.log('[Player] Native video loaded, duration:', data.duration);
        setDuration(data.duration);
    }, []);

    const handleNativeProgress = useCallback((data: OnProgressData) => {
        setCurrentTime(data.currentTime);
    }, []);

    const handleVlcProgress = useCallback((event: { currentTime: number; duration: number }) => {
        setCurrentTime(event.currentTime / 1000); // VLC reports in ms
        if (event.duration > 0) {
            setDuration(event.duration / 1000);
        }
    }, []);

    // --- Playback controls ---

    const togglePlayPause = useCallback(() => {
        setPaused((prev) => !prev);
        resetHideTimer();
    }, []);

    const seekBy = useCallback((offset: number) => {
        const target = Math.max(0, Math.min(currentTime + offset, duration));
        if (backend === 'native') {
            nativeRef.current?.seek(target);
        } else {
            // VLC seek expects a value in seconds
            vlcSeekTo.current = target;
            setVlcSeekValue(target);
        }
        setCurrentTime(target);
        resetHideTimer();
    }, [currentTime, duration, backend]);

    // --- Overlay logic ---

    const resetHideTimer = useCallback(() => {
        clearTimeout(hideTimer.current);
        hideTimer.current = setTimeout(hideOverlayAnim, OVERLAY_TIMEOUT);
    }, []);

    const hideOverlayAnim = useCallback(() => {
        Animated.timing(fadeAnim, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
        }).start(() => setOverlayVisible(false));
    }, [fadeAnim]);

    const showOverlay = useCallback(() => {
        setOverlayVisible(true);
        fadeAnim.setValue(1);
        resetHideTimer();
    }, [fadeAnim, resetHideTimer]);

    useEffect(() => {
        resetHideTimer();
        return () => clearTimeout(hideTimer.current);
    }, [resetHideTimer]);

    // Progress bar percentage
    const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

    return (
        <View style={styles.container}>
            {/* Video layer */}
            {backend === 'native' ? (
                <Video
                    ref={nativeRef}
                    source={{
                        uri: streamUrl,
                        headers: { 'User-Agent': USER_AGENT },
                    }}
                    style={styles.video}
                    resizeMode={ResizeMode.CONTAIN}
                    controls={false}
                    paused={paused}
                    onLoad={handleNativeLoad}
                    onProgress={handleNativeProgress}
                    onError={handleNativeError}
                    progressUpdateInterval={500}
                />
            ) : (
                <VLCPlayer
                    source={{
                        uri: streamUrl,
                        initOptions: [
                            '--network-caching=3000',
                            `--http-user-agent=${USER_AGENT}`,
                        ],
                    }}
                    style={styles.video}
                    autoplay={true}
                    paused={paused}
                    seek={vlcSeekValue}
                    onProgress={handleVlcProgress}
                    onError={handleVlcError}
                />
            )}

            {/* Controls overlay */}
            {overlayVisible && (
                <Animated.View
                    style={[styles.overlay, { opacity: fadeAnim }]}
                    pointerEvents="box-none"
                >
                    {/* Top bar: back + title */}
                    <View style={styles.header}>
                        <SpatialNavigationNode>
                            <FocusablePressable
                                onSelect={() => navigation.goBack()}
                                style={styles.backButton}
                            >
                                <Icon name="ArrowLeft" size={scaledPixels(32)} color={colors.text} />
                            </FocusablePressable>
                        </SpatialNavigationNode>
                        <Text style={styles.title} numberOfLines={1}>{title}</Text>
                    </View>

                    {/* Bottom bar: controls + progress */}
                    <SpatialNavigationView direction="vertical">
                        <View style={styles.controlsBar}>
                            {/* Progress bar (VOD/series only) */}
                            {!isLive && duration > 0 && (
                                <View style={styles.progressContainer}>
                                    <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
                                    <View style={styles.progressTrack}>
                                        <View style={[styles.progressFill, { width: `${progress}%` }]} />
                                    </View>
                                    <Text style={styles.timeText}>{formatTime(duration)}</Text>
                                </View>
                            )}

                            {/* Transport controls */}
                            <View style={styles.transportRow}>
                                {!isLive && (
                                    <SpatialNavigationNode>
                                        <FocusablePressable
                                            onSelect={() => seekBy(-SEEK_STEP)}
                                            style={({ isFocused }) => [
                                                styles.controlButton,
                                                isFocused && styles.controlButtonFocused,
                                            ]}
                                        >
                                            <Icon name="SkipBack" size={scaledPixels(28)} color={colors.text} />
                                        </FocusablePressable>
                                    </SpatialNavigationNode>
                                )}

                                <SpatialNavigationNode>
                                    <DefaultFocus>
                                        <FocusablePressable
                                            onSelect={togglePlayPause}
                                            style={({ isFocused }) => [
                                                styles.controlButton,
                                                styles.playButton,
                                                isFocused && styles.controlButtonFocused,
                                            ]}
                                        >
                                            <Icon
                                                name={paused ? 'Play' : 'Pause'}
                                                size={scaledPixels(36)}
                                                color={colors.text}
                                            />
                                        </FocusablePressable>
                                    </DefaultFocus>
                                </SpatialNavigationNode>

                                {!isLive && (
                                    <SpatialNavigationNode>
                                        <FocusablePressable
                                            onSelect={() => seekBy(SEEK_STEP)}
                                            style={({ isFocused }) => [
                                                styles.controlButton,
                                                isFocused && styles.controlButtonFocused,
                                            ]}
                                        >
                                            <Icon name="SkipForward" size={scaledPixels(28)} color={colors.text} />
                                        </FocusablePressable>
                                    </SpatialNavigationNode>
                                )}
                            </View>
                        </View>
                    </SpatialNavigationView>
                </Animated.View>
            )}

            {/* Invisible focusable to bring overlay back */}
            {!overlayVisible && (
                <View style={styles.tapZone} pointerEvents="box-none">
                    <FocusablePressable onSelect={showOverlay} style={styles.tapZone}>
                        <View />
                    </FocusablePressable>
                </View>
            )}
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
    },
    video: {
        flex: 1,
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
        justifyContent: 'space-between',
        padding: scaledPixels(40),
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    backButton: {
        padding: scaledPixels(10),
        borderRadius: scaledPixels(50),
        backgroundColor: 'rgba(0,0,0,0.5)',
    },
    title: {
        flex: 1,
        color: colors.text,
        fontSize: scaledPixels(24),
        fontWeight: 'bold',
        marginLeft: scaledPixels(20),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 5,
    },
    controlsBar: {
        backgroundColor: 'rgba(0,0,0,0.6)',
        borderRadius: scaledPixels(16),
        paddingHorizontal: scaledPixels(24),
        paddingVertical: scaledPixels(16),
    },
    progressContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: scaledPixels(12),
    },
    progressTrack: {
        flex: 1,
        height: scaledPixels(6),
        backgroundColor: 'rgba(255,255,255,0.3)',
        borderRadius: scaledPixels(3),
        marginHorizontal: scaledPixels(12),
        overflow: 'hidden',
    },
    progressFill: {
        height: '100%',
        backgroundColor: colors.primary,
        borderRadius: scaledPixels(3),
    },
    timeText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(14),
        fontVariant: ['tabular-nums'],
        minWidth: scaledPixels(60),
        textAlign: 'center',
    },
    transportRow: {
        flexDirection: 'row',
        justifyContent: 'center',
        alignItems: 'center',
        gap: scaledPixels(20),
    },
    controlButton: {
        padding: scaledPixels(12),
        borderRadius: scaledPixels(50),
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    playButton: {
        paddingHorizontal: scaledPixels(20),
    },
    controlButtonFocused: {
        backgroundColor: colors.primary,
    },
    tapZone: {
        ...StyleSheet.absoluteFillObject,
    },
});
