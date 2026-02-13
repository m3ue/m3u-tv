import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Text, Animated, TVEventHandler, BackHandler } from 'react-native';
import Video, { OnLoadData, OnProgressData, OnVideoErrorData, ResizeMode, VideoRef } from 'react-native-video';
import { VLCPlayer } from 'react-native-vlc-media-player';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';

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

    // Focus refs
    const playButtonRef = useRef<FocusablePressableRef>(null);

    // Playback state
    const [paused, setPaused] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);
    const isLive = type === 'live';

    // Refs
    const nativeRef = useRef<VideoRef>(null);
    const vlcRef = useRef<any>(null);
    const [vlcSeekValue, setVlcSeekValue] = useState<number | undefined>(undefined);
    const seekingRef = useRef(false);
    const seekLockoutTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    // Overlay state
    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    // Use refs so handlers always have current values
    const overlayVisibleRef = useRef(overlayVisible);
    const pausedRef = useRef(paused);
    const currentTimeRef = useRef(currentTime);
    const durationRef = useRef(duration);
    const backendRef = useRef(backend);

    useEffect(() => {
        overlayVisibleRef.current = overlayVisible;
    }, [overlayVisible]);
    useEffect(() => {
        pausedRef.current = paused;
    }, [paused]);
    useEffect(() => {
        currentTimeRef.current = currentTime;
    }, [currentTime]);
    useEffect(() => {
        durationRef.current = duration;
    }, [duration]);
    useEffect(() => {
        backendRef.current = backend;
    }, [backend]);

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
        // Give it a delay to ensure the nodes are rendered before focusing
        setTimeout(() => {
            playButtonRef.current?.focus();
        }, 150);
    }, [fadeAnim, resetHideTimer]);

    useEffect(() => {
        resetHideTimer();
        // Set initial focus to play button
        if (overlayVisible) {
            setTimeout(() => playButtonRef.current?.focus(), 150);
        }
        return () => clearTimeout(hideTimer.current);
    }, [resetHideTimer]);

    // --- Playback controls (using refs for stable callback) ---

    const doSeek = useCallback((offset: number) => {
        const ct = currentTimeRef.current;
        const dur = durationRef.current;
        if (dur <= 0) {
            console.log('[Player] Seek ignored: duration is 0 or live');
            return;
        }

        const target = Math.max(0, Math.min(ct + offset, dur));
        console.log(`[Player] Seeking to ${target}s (current: ${ct}s, offset: ${offset}s, backend: ${backendRef.current})`);

        // Lock out progress updates during seek to prevent jumping back
        seekingRef.current = true;
        setCurrentTime(target);

        if (seekLockoutTimer.current) clearTimeout(seekLockoutTimer.current);
        seekLockoutTimer.current = setTimeout(() => {
            seekingRef.current = false;
        }, 2500); // 2.5s lockout to ensure buffer is stable

        if (backendRef.current === 'native') {
            nativeRef.current?.seek(target);
        } else {
            // VLC expects milliseconds.
            // We set it, then clear it back to undefined so it doesn't stay at a value that might re-trigger
            const targetMs = Math.floor(target * 1000);
            setVlcSeekValue(targetMs);
            // Longer delay before resetting to undefined, or maybe don't reset if undefined causes issues
            setTimeout(() => setVlcSeekValue(undefined), 500);
        }
    }, []);

    const doTogglePlayPause = useCallback(() => {
        setPaused((prev) => !prev);
    }, []);

    // --- Backend Handlers ---

    const handleNativeLoad = useCallback((data: OnLoadData) => {
        console.log('[Player] Native loaded, duration:', data.duration);
        setDuration(data.duration);
    }, []);

    const handleNativeProgress = useCallback((data: OnProgressData) => {
        if (!seekingRef.current) {
            setCurrentTime(data.currentTime);
        }
    }, []);

    const handleNativeError = useCallback((error: OnVideoErrorData) => {
        console.error('[Player] Native video error:', error);
        setBackend('vlc'); // Fallback to VLC
    }, []);

    const handleVlcProgress = useCallback((data: any) => {
        if (!seekingRef.current) {
            // VLC provides duration and currentTime in ms
            if (data.duration && data.duration / 1000 !== durationRef.current) {
                setDuration(data.duration / 1000);
            }
            setCurrentTime(data.currentTime / 1000);
        }
    }, []);

    const handleVlcError = useCallback((error: any) => {
        console.error('[Player] VLC error:', error);
    }, []);

    // --- TV Events & Back Handling ---

    useEffect(() => {
        const backAction = () => {
            if (overlayVisibleRef.current) {
                hideOverlayAnim();
                return true;
            }
            navigation.goBack();
            return true;
        };

        const backHandler = BackHandler.addEventListener('hardwareBackPress', backAction);

        const TVHandler: any = TVEventHandler;
        if (!TVHandler) return () => backHandler.remove();

        const listener = (event: any) => {
            if (!event?.eventType) return;

            // If overlay is hidden, show it on any button that isn't back/menu
            if (!overlayVisibleRef.current) {
                if (['back', 'menu'].includes(event.eventType)) {
                    navigation.goBack();
                    return;
                }
                showOverlay();
                return;
            }

            // If overlay is visible, handle back/menu to hide it
            if (['back', 'menu'].includes(event.eventType)) {
                hideOverlayAnim();
                return;
            }

            // Standard transport controls
            if (event.eventType === 'playPause') doTogglePlayPause();
            if (event.eventType === 'fastForward') doSeek(SEEK_STEP);
            if (event.eventType === 'rewind') doSeek(-SEEK_STEP);

            resetHideTimer();
        };

        let subscription: any;
        if (typeof TVHandler.addListener === 'function') {
            subscription = TVHandler.addListener(listener);
        } else if (typeof TVHandler === 'function') {
            const instance = new TVHandler();
            instance.enable(null, (_: any, event: any) => listener(event));
            subscription = { remove: () => instance.disable() };
        }

        return () => {
            backHandler.remove();
            subscription?.remove();
        };
    }, [navigation, showOverlay, hideOverlayAnim, resetHideTimer, doTogglePlayPause, doSeek]);

    // Use refs for source to ensure stable reference AND avoid React.memo/Hermes freezing
    // We use Object.assign to ensure the object is not a frozen literal
    const nativeSourceRef = useRef<any>(null);
    const vlcSourceRef = useRef<any>(null);

    if (!nativeSourceRef.current || nativeSourceRef.current.uri !== streamUrl) {
        nativeSourceRef.current = Object.assign(
            {},
            {
                uri: streamUrl,
                headers: { 'User-Agent': USER_AGENT },
                isNetwork: true,
            },
        );
        vlcSourceRef.current = Object.assign(
            {},
            {
                uri: streamUrl,
                initOptions: ['--network-caching=3000', `--http-user-agent=${USER_AGENT}`],
                isNetwork: true,
            },
        );
    }

    // Progress bar percentage
    const progress = duration > 0 ? (currentTime / duration) * 100 : 0;

    return (
        <View style={styles.container}>
            {/* Video layer */}
            {backend === 'native' ? (
                <Video
                    ref={nativeRef}
                    source={{ ...nativeSourceRef.current }}
                    style={styles.video}
                    resizeMode={ResizeMode.CONTAIN}
                    controls={false}
                    paused={paused}
                    onLoad={handleNativeLoad}
                    onProgress={handleNativeProgress}
                    onError={handleNativeError}
                    onSeek={() => {
                        console.log('[Player] Native seek completed');
                        seekingRef.current = false;
                    }}
                    progressUpdateInterval={500}
                />
            ) : (
                <VLCPlayer
                    ref={vlcRef}
                    source={{ ...vlcSourceRef.current }}
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
                <Animated.View style={[styles.overlay, { opacity: fadeAnim }]}>
                    <View style={styles.overlayInner}>
                        {/* Top bar: back + title */}
                        <View style={styles.header}>
                            <FocusablePressable
                                onSelect={() => navigation.goBack()}
                                onFocus={() => {
                                    console.log('[Player] Back focused');
                                    resetHideTimer();
                                }}
                                style={({ isFocused }) => [styles.backButton, isFocused && styles.controlButtonFocused]}
                            >
                                <Icon name="ArrowLeft" size={scaledPixels(32)} color={colors.text} />
                            </FocusablePressable>
                            <Text style={styles.title} numberOfLines={1}>
                                {title}
                            </Text>
                        </View>

                        {/* Bottom bar: controls + progress */}
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
                                    <FocusablePressable
                                        onSelect={() => doSeek(-SEEK_STEP)}
                                        onFocus={() => {
                                            console.log('[Player] Rewind focused');
                                            resetHideTimer();
                                        }}
                                        style={({ isFocused }) => [styles.controlButton, isFocused && styles.controlButtonFocused]}
                                    >
                                        <Icon name="SkipBack" size={scaledPixels(28)} color={colors.text} />
                                    </FocusablePressable>
                                )}

                                <FocusablePressable
                                    ref={playButtonRef}
                                    preferredFocus
                                    onSelect={doTogglePlayPause}
                                    onFocus={() => {
                                        console.log('[Player] Play focused');
                                        resetHideTimer();
                                    }}
                                    style={({ isFocused }) => [
                                        styles.controlButton,
                                        styles.playButton,
                                        isFocused && styles.controlButtonFocused,
                                    ]}
                                >
                                    <Icon name={paused ? 'Play' : 'Pause'} size={scaledPixels(36)} color={colors.text} />
                                </FocusablePressable>

                                {!isLive && (
                                    <FocusablePressable
                                        onSelect={() => doSeek(SEEK_STEP)}
                                        onFocus={() => {
                                            console.log('[Player] Forward focused');
                                            resetHideTimer();
                                        }}
                                        style={({ isFocused }) => [styles.controlButton, isFocused && styles.controlButtonFocused]}
                                    >
                                        <Icon name="SkipForward" size={scaledPixels(28)} color={colors.text} />
                                    </FocusablePressable>
                                )}
                            </View>
                        </View>
                    </View>
                </Animated.View>
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
        padding: scaledPixels(40),
    },
    overlayInner: {
        flex: 1,
        justifyContent: 'space-between' as const,
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
});
