import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    View,
    StyleSheet,
    Text,
    Pressable,
    ActivityIndicator,
    Animated,
    TVEventHandler,
    TVFocusGuideView,
    BackHandler,
    Platform,
    Alert,
    ActionSheetIOS,
} from 'react-native';
import Video, { OnLoadData, OnProgressData, OnVideoErrorData, OnAudioTracksData, OnTextTracksData, SelectedTrackType, ResizeMode, VideoRef } from 'react-native-video';
import { VLCPlayer } from 'react-native-vlc-media-player';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';

const OVERLAY_TIMEOUT = 8000;
const SEEK_STEP = 10;
const TIMELINE_SEEK_STEP = 30;
const USER_AGENT =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';
const VLC_ONLY_EXTENSIONS = ['.avi', '.mkv', '.wmv', '.flv', '.rmvb', '.rm', '.asf', '.divx', '.ogm'];

type PlayerBackend = 'native' | 'vlc';
type PlayerTrack = { id: number; name: string; language?: string };

function getInitialBackend(url: string): PlayerBackend {
    if (Platform.OS !== 'android') {
        return 'vlc';
    }

    const path = url.split('?')[0].toLowerCase();
    if (VLC_ONLY_EXTENSIONS.some((ext) => path.endsWith(ext))) {
        return 'vlc';
    }

    return 'native';
}

function formatTime(seconds: number): string {
    const safeSeconds = Number.isFinite(seconds) ? seconds : 0;
    const s = Math.max(0, Math.floor(safeSeconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const pad = (n: number) => n.toString().padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

function toErrorMessage(error: unknown): string {
    if (error instanceof Error) return error.message;
    if (typeof error === 'string') return error;
    if (typeof error === 'object' && error !== null) {
        try {
            return JSON.stringify(error);
        } catch {
            return 'Unknown playback error';
        }
    }

    return 'Unknown playback error';
}

function showNativeSelect(
    title: string,
    options: string[],
    selectedIndex: number,
    onPick: (index: number) => void,
) {
    if (Platform.OS === 'ios' && !Platform.isTV) {
        ActionSheetIOS.showActionSheetWithOptions(
            {
                title,
                options: [...options, 'Cancel'],
                cancelButtonIndex: options.length,
            },
            (buttonIndex) => {
                if (buttonIndex < options.length) {
                    onPick(buttonIndex);
                }
            },
        );
        return;
    }

    Alert.alert(
        title,
        undefined,
        [
            ...options.map((option, index) => ({
                text: index === selectedIndex ? `✓ ${option}` : option,
                onPress: () => onPick(index),
            })),
            { text: 'Cancel', style: 'cancel' },
        ],
        { cancelable: true },
    );
}

const isTV = Platform.isTV;
const isTVOS = Platform.OS === 'ios' && isTV;

// On tvOS, use TVFocusGuideView with autoFocus to guide focus into overlay regions.
// On Android TV, spatial focus works natively — TVFocusGuideView interferes with FocusFinder.
const FocusContainer = isTVOS
    ? ({ style, children }: { style?: any; children: React.ReactNode }) => (
        <TVFocusGuideView style={style} autoFocus>{children}</TVFocusGuideView>
    )
    : ({ style, children }: { style?: any; children: React.ReactNode }) => (
        <View style={style}>{children}</View>
    );

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { title, type } = route.params;
    const isLive = type === 'live';


    // DEBUGGING: Temporary hardcoded stream URL for testing purposes
    let streamUrl = 'https://ftp.halifax.rwth-aachen.de/blender/demo/movies/Sintel.2010.1080p.mkv';
    if (isLive) {
        streamUrl = 'https://cfd-v4-service-channel-stitcher-use1-1.prd.pluto.tv/stitch/hls/channel/5c12ba66eae03059cbdc77f2/master.m3u8?advertisingId=&appName=web&appVersion=unknown&appStoreUrl=&architecture=&buildVersion=&clientTime=0&deviceDNT=0&deviceId=3c1b5410-0cf9-11f1-aa0b-e3d711d187f5&deviceMake=Chrome&deviceModel=web&deviceType=web&deviceVersion=unknown&includeExtendedEvents=false&sid=ffaf6ba5-9e47-4c47-b494-a79be9873606&userId=&serverSideAds=true';
    }


    const initialBackend = useMemo(() => getInitialBackend(streamUrl), [streamUrl]);
    const [backend, setBackend] = useState<PlayerBackend>(initialBackend);

    const backButtonRef = useRef<FocusablePressableRef>(null);
    const rewindButtonRef = useRef<FocusablePressableRef>(null);
    const playButtonRef = useRef<FocusablePressableRef>(null);
    const forwardButtonRef = useRef<FocusablePressableRef>(null);
    const timelineRef = useRef<FocusablePressableRef>(null);
    const timelineFocusedRef = useRef(false);
    const audioButtonRef = useRef<FocusablePressableRef>(null);
    const subtitleButtonRef = useRef<FocusablePressableRef>(null);

    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [paused, setPaused] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);
    const [vlcSeekValue, setVlcSeekValue] = useState(-1);

    const [audioTracks, setAudioTracks] = useState<PlayerTrack[]>([]);
    const [textTracks, setTextTracks] = useState<PlayerTrack[]>([]);
    const [selectedAudioTrack, setSelectedAudioTrack] = useState<number | undefined>(undefined);
    const [selectedTextTrack, setSelectedTextTrack] = useState<number>(-1);

    const nativeRef = useRef<VideoRef>(null);
    const vlcRef = useRef<any>(null);
    const audioAutoSelectedRef = useRef(false);
    const vlcTracksLoadedRef = useRef(false);
    const userSelectedAudioRef = useRef(false);
    const userSelectedTextRef = useRef(false);
    const seekingRef = useRef(false);
    const seekLockoutTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const exitGuardRef = useRef(false);

    const currentTimeRef = useRef(currentTime);
    const durationRef = useRef(duration);
    const backendRef = useRef(backend);

    useEffect(() => {
        currentTimeRef.current = currentTime;
    }, [currentTime]);

    useEffect(() => {
        durationRef.current = duration;
    }, [duration]);

    useEffect(() => {
        backendRef.current = backend;
    }, [backend]);

    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const overlayVisibleRef = useRef(overlayVisible);

    useEffect(() => {
        overlayVisibleRef.current = overlayVisible;
    }, [overlayVisible]);

    const nativeSourceRef = useRef<any>(null);
    const vlcSourceRef = useRef<any>(null);

    if (!nativeSourceRef.current || nativeSourceRef.current.uri !== streamUrl) {
        nativeSourceRef.current = {
            uri: streamUrl,
            headers: { 'User-Agent': USER_AGENT },
            isNetwork: true,
        };
        vlcSourceRef.current = {
            uri: streamUrl,
            initOptions: ['--network-caching=3000', `--http-user-agent=${USER_AGENT}`],
            isNetwork: true,
        };
    }

    const hideOverlayAnim = useCallback(() => {
        Animated.timing(fadeAnim, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
        }).start(() => {
            setOverlayVisible(false);
        });
    }, [fadeAnim]);

    const resetHideTimer = useCallback(() => {
        clearTimeout(hideTimer.current);
        hideTimer.current = setTimeout(hideOverlayAnim, OVERLAY_TIMEOUT);
    }, [hideOverlayAnim]);

    const showOverlay = useCallback(() => {
        setOverlayVisible(true);
        fadeAnim.setValue(1);
        resetHideTimer();

        setTimeout(() => {
            backButtonRef.current?.focus();
        }, 150);
    }, [fadeAnim, resetHideTimer]);

    useEffect(() => {
        resetHideTimer();
        if (overlayVisible) {
            setTimeout(() => {
                backButtonRef.current?.focus();
            }, 150);
        }

        return () => clearTimeout(hideTimer.current);
    }, [overlayVisible, resetHideTimer]);

    const goBackSafe = useCallback(() => {
        if (exitGuardRef.current) {
            return;
        }

        exitGuardRef.current = true;
        navigation.goBack();
    }, [navigation]);

    const doSeekTo = useCallback((targetSeconds: number) => {
        const dur = durationRef.current;
        if (dur <= 0 || isLive) {
            return;
        }

        const target = Math.max(0, Math.min(targetSeconds, dur));
        seekingRef.current = true;
        setCurrentTime(target);

        if (seekLockoutTimer.current) {
            clearTimeout(seekLockoutTimer.current);
        }

        seekLockoutTimer.current = setTimeout(() => {
            seekingRef.current = false;
        }, 1500);

        if (backendRef.current === 'native') {
            nativeRef.current?.seek(target);
        } else {
            setVlcSeekValue(target / dur);
            setTimeout(() => {
                setVlcSeekValue(-1);
            }, 300);
        }
    }, [isLive]);

    const doSeek = useCallback((offset: number) => {
        doSeekTo(currentTimeRef.current + offset);
    }, [doSeekTo]);

    const doTogglePlayPause = useCallback(() => {
        setPaused((prev) => !prev);
    }, []);

    const openAudioSelector = useCallback(() => {
        if (audioTracks.length === 0) {
            return;
        }

        const options = ['Disable', ...audioTracks.map((track) => track.name || `Track ${track.id}`)];
        const selectedIndex = selectedAudioTrack === -1
            ? 0
            : audioTracks.findIndex((track) => track.id === selectedAudioTrack) + 1;

        showNativeSelect('Audio Track', options, selectedIndex < 0 ? 0 : selectedIndex, (index) => {
            userSelectedAudioRef.current = true;
            if (index === 0) {
                setSelectedAudioTrack(-1);
            } else {
                setSelectedAudioTrack(audioTracks[index - 1].id);
            }
            resetHideTimer();
        });
    }, [audioTracks, selectedAudioTrack, resetHideTimer]);

    const openSubtitleSelector = useCallback(() => {
        const options = ['Off', ...textTracks.map((track) => track.name || `Track ${track.id}`)];
        const selectedIndex = selectedTextTrack === -1
            ? 0
            : Math.max(0, textTracks.findIndex((track) => track.id === selectedTextTrack) + 1);

        showNativeSelect('Subtitle Track', options, selectedIndex, (index) => {
            userSelectedTextRef.current = true;
            if (index === 0) {
                setSelectedTextTrack(-1);
            } else {
                const selectedTrack = textTracks[index - 1];
                if (selectedTrack) {
                    setSelectedTextTrack(selectedTrack.id);
                }
            }

            resetHideTimer();
        });
    }, [textTracks, selectedTextTrack, resetHideTimer]);

    const handleNativeLoad = useCallback((data: OnLoadData) => {
        setError(null);
        setIsLoading(false);
        setDuration(data.duration || 0);

        // react-native-video includes audioTracks in OnLoadData
        const nativeAudio = (data as any).audioTracks as Array<{ index: number; title: string; language: string; type: string }> | undefined;
        if (nativeAudio && nativeAudio.length > 0) {
            const mapped: PlayerTrack[] = nativeAudio.map(t => ({
                id: t.index,
                name: t.title || t.language || `Track ${t.index}`,
                language: t.language,
            }));
            setAudioTracks(mapped);
            if (!audioAutoSelectedRef.current && mapped.length > 0) {
                setSelectedAudioTrack(mapped[0].id);
                audioAutoSelectedRef.current = true;
            }
        }

        const nativeText = (data as any).textTracks as Array<{ index: number; title: string; language: string; type: string }> | undefined;
        if (nativeText && nativeText.length > 0) {
            const mapped: PlayerTrack[] = nativeText.map(t => ({
                id: t.index,
                name: t.title || t.language || `Track ${t.index}`,
                language: t.language,
            }));
            setTextTracks(mapped);
        }
    }, []);

    const handleNativeAudioTracks = useCallback((data: OnAudioTracksData) => {
        if (data.audioTracks && data.audioTracks.length > 0) {
            const mapped: PlayerTrack[] = data.audioTracks.map(t => ({
                id: t.index,
                name: t.title || t.language || `Track ${t.index}`,
                language: t.language,
            }));
            setAudioTracks(mapped);
            if (!audioAutoSelectedRef.current && mapped.length > 0) {
                setSelectedAudioTrack(mapped[0].id);
                audioAutoSelectedRef.current = true;
            }
        }
    }, []);

    const handleNativeTextTracks = useCallback((data: OnTextTracksData) => {
        if (data.textTracks && data.textTracks.length > 0) {
            const mapped: PlayerTrack[] = data.textTracks.map(t => ({
                id: t.index,
                name: t.title || t.language || `Track ${t.index}`,
                language: t.language,
            }));
            setTextTracks(mapped);
        }
    }, []);

    const handleNativeProgress = useCallback((data: OnProgressData) => {
        if (!seekingRef.current) {
            setCurrentTime(data.currentTime || 0);
        }
    }, []);

    const handleNativeError = useCallback((nativeError: OnVideoErrorData) => {
        console.error('[PlayerScreenNew] Native playback error', nativeError);

        if (backendRef.current === 'native') {
            setBackend('vlc');
            setError('Native playback failed, retrying with VLC...');
            setIsLoading(true);
            return;
        }

        setIsLoading(false);
        setError(toErrorMessage(nativeError));
    }, []);

    const handleVlcLoad = useCallback((data: {
        duration: number;
        audioTracks?: PlayerTrack[];
        textTracks?: PlayerTrack[];
    }) => {
        setError(null);
        setIsLoading(false);
        setDuration((data.duration || 0) / 1000);

        // VLC re-fires onLoad when track state changes (e.g. subtitle switch),
        // and track IDs can shift between calls. Only populate tracks on first load.
        if (!vlcTracksLoadedRef.current) {
            const realAudioTracks = (data.audioTracks ?? []).filter(t => t.id >= 0);
            const realTextTracks = (data.textTracks ?? []).filter(t => t.id >= 0);

            if (realAudioTracks.length > 0 || realTextTracks.length > 0) {
                vlcTracksLoadedRef.current = true;
                setAudioTracks(realAudioTracks);
                setTextTracks(realTextTracks);

                if (realAudioTracks.length > 0 && !audioAutoSelectedRef.current) {
                    setSelectedAudioTrack(realAudioTracks[0].id);
                    audioAutoSelectedRef.current = true;
                }
            }
        }
    }, []);

    const handleVlcProgress = useCallback((data: {
        currentTime: number;
        duration: number;
    }) => {
        if (isLoading) {
            setIsLoading(false);
        }

        if (!seekingRef.current) {
            if (typeof data.duration === 'number' && data.duration > 0) {
                const durSeconds = data.duration / 1000;
                if (durSeconds !== durationRef.current) {
                    setDuration(durSeconds);
                }
            }

            if (typeof data.currentTime === 'number') {
                setCurrentTime(data.currentTime / 1000);
            }
        }
    }, [isLoading]);

    const handleVlcError = useCallback((vlcError: unknown) => {
        console.error('[PlayerScreen] VLC playback error', vlcError);
        setIsLoading(false);

        let message = 'Unknown playback error';
        if (vlcError && typeof vlcError === 'object') {
            const err = vlcError as Record<string, unknown>;
            if (typeof err.message === 'string' && err.message) {
                message = err.message;
            } else if (typeof err.title === 'string' && err.title) {
                message = [err.title, err.message].filter(Boolean).join(': ');
            } else if (err.type === 'Error' && err.duration === 0 && err.currentTime === 0) {
                message = 'Failed to open stream. Check that the URL is reachable and the format is supported.';
            } else {
                message = toErrorMessage(vlcError);
            }
        }

        setError(message);
    }, []);

    useEffect(() => {
        const backAction = () => {
            if (overlayVisibleRef.current) {
                hideOverlayAnim();
                return true;
            }

            goBackSafe();
            return true;
        };

        const backHandler = BackHandler.addEventListener('hardwareBackPress', backAction);
        const TVHandler: any = TVEventHandler;
        if (!TVHandler) {
            return () => {
                backHandler.remove();
            };
        }

        const listener = (event: { eventType?: string }) => {
            if (!event?.eventType) {
                return;
            }

            if (!overlayVisibleRef.current) {
                if (event.eventType === 'back' || event.eventType === 'menu') {
                    goBackSafe();
                    return;
                }

                showOverlay();
                return;
            }

            if (event.eventType === 'back' || event.eventType === 'menu') {
                hideOverlayAnim();
                return;
            }

            // When timeline is focused, intercept left/right for scrubbing
            if (timelineFocusedRef.current) {
                if (event.eventType === 'left') {
                    doSeek(-SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'right') {
                    doSeek(SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'longLeft') {
                    doSeek(-TIMELINE_SEEK_STEP);
                    resetHideTimer();
                    return;
                }
                if (event.eventType === 'longRight') {
                    doSeek(TIMELINE_SEEK_STEP);
                    resetHideTimer();
                    return;
                }
            }

            if (event.eventType === 'playPause') {
                doTogglePlayPause();
                resetHideTimer();
                return;
            }

            if (event.eventType === 'fastForward') {
                doSeek(SEEK_STEP);
                resetHideTimer();
                return;
            }

            if (event.eventType === 'rewind') {
                doSeek(-SEEK_STEP);
                resetHideTimer();
                return;
            }

            resetHideTimer();
        };

        let subscription: { remove?: () => void } | undefined;
        if (typeof TVHandler.addListener === 'function') {
            subscription = TVHandler.addListener(listener);
        } else if (typeof TVHandler === 'function') {
            const instance = new TVHandler();
            instance.enable(null, (_: unknown, event: { eventType?: string }) => listener(event));
            subscription = { remove: () => instance.disable() };
        }

        return () => {
            backHandler.remove();
            subscription?.remove?.();
        };
    }, [doSeek, doTogglePlayPause, goBackSafe, hideOverlayAnim, resetHideTimer, showOverlay]);

    useEffect(() => {
        return () => {
            if (seekLockoutTimer.current) {
                clearTimeout(seekLockoutTimer.current);
            }
            // Explicitly stop VLC on unmount to prevent "can't get VLCObject instance"
            try {
                vlcRef.current?.stopPlayer?.();
            } catch (_) { /* ignore */ }
        };
    }, []);

    const canSeek = !isLive && duration > 0;
    const progress = canSeek ? (currentTime / duration) * 100 : 0;
    const selectedAudioLabel = selectedAudioTrack === -1
        ? 'Disabled'
        : (audioTracks.find((track) => track.id === selectedAudioTrack)?.name ?? 'Select');
    const selectedSubtitleLabel = selectedTextTrack === -1
        ? 'Off'
        : (textTracks.find((track) => track.id === selectedTextTrack)?.name ?? 'Select');

    // For native player text track selection, prefer language-based selection (more reliable for HLS/ExoPlayer)
    const nativeSelectedTextTrack = useMemo(() => {
        if (!userSelectedTextRef.current || selectedTextTrack < 0) return undefined;
        const track = textTracks.find(t => t.id === selectedTextTrack);
        if (track?.language) {
            return { type: SelectedTrackType.LANGUAGE, value: track.language };
        }
        return { type: SelectedTrackType.INDEX, value: selectedTextTrack };
    }, [selectedTextTrack, textTracks]);

    return (
        <View style={styles.container}>
            <View style={StyleSheet.absoluteFill} pointerEvents="none">
                {backend === 'native' ? (
                    <Video
                        ref={nativeRef}
                        source={{ ...nativeSourceRef.current }}
                        style={styles.player}
                        resizeMode={ResizeMode.CONTAIN}
                        controls={false}
                        paused={paused}
                        selectedAudioTrack={
                            userSelectedAudioRef.current && selectedAudioTrack != null && selectedAudioTrack >= 0
                                ? { type: SelectedTrackType.INDEX, value: selectedAudioTrack }
                                : undefined
                        }
                        selectedTextTrack={nativeSelectedTextTrack}
                        onLoad={handleNativeLoad}
                        onAudioTracks={handleNativeAudioTracks}
                        onTextTracks={handleNativeTextTracks}
                        onProgress={handleNativeProgress}
                        onError={handleNativeError}
                        progressUpdateInterval={500}
                        onEnd={goBackSafe}
                    />
                ) : (
                    <VLCPlayer
                        ref={vlcRef}
                        style={styles.player}
                        source={{ ...vlcSourceRef.current }}
                        autoplay
                        paused={paused}
                        seek={vlcSeekValue}
                        audioTrack={selectedAudioTrack}
                        textTrack={selectedTextTrack}
                        onBuffering={() => {
                            setIsLoading(true);
                            setError(null);
                        }}
                        onLoad={handleVlcLoad}
                        onProgress={handleVlcProgress}
                        onError={handleVlcError}
                        onEnd={goBackSafe}
                    />
                )}
            </View>

            {isLoading && !error && (
                <View style={styles.centerOverlay} pointerEvents="none">
                    <ActivityIndicator color="#ffffff" size="large" />
                    <Text style={styles.loadingText}>Loading stream...</Text>
                    <Text style={styles.loadingSubtext}>Backend: {backend.toUpperCase()}</Text>
                </View>
            )}

            {error && (
                <View style={styles.centerOverlay}>
                    <Text style={styles.errorTitle}>Playback error</Text>
                    <Text style={styles.errorText} numberOfLines={6}>
                        {error}
                    </Text>
                </View>
            )}

            {!overlayVisible && (
                <Pressable
                    style={StyleSheet.absoluteFill}
                    focusable
                    onPress={showOverlay}
                    onFocus={showOverlay}
                />
            )}

            <Animated.View
                style={[styles.overlay, { opacity: fadeAnim }]}
                pointerEvents={overlayVisible ? 'auto' : 'none'}
            >
                <FocusContainer style={styles.overlayInner}>
                    <View style={styles.header}>
                        <FocusablePressable
                            ref={backButtonRef}
                            onSelect={goBackSafe}
                            onFocus={resetHideTimer}
                            style={({ isFocused }) => [
                                styles.backButton,
                                isFocused && styles.controlButtonFocused,
                            ]}
                        >
                            <Icon name="ArrowLeft" size={scaledPixels(32)} color={colors.text} />
                        </FocusablePressable>

                        <Text style={styles.title} numberOfLines={1}>
                            {title}
                        </Text>
                    </View>

                    <FocusContainer style={styles.controlsBar}>
                        {canSeek && (
                            <FocusablePressable
                                ref={timelineRef}
                                onFocus={() => {
                                    timelineFocusedRef.current = true;
                                    resetHideTimer();
                                }}
                                onBlur={() => {
                                    timelineFocusedRef.current = false;
                                }}
                                style={({ isFocused }) => [
                                    styles.progressContainer,
                                    isFocused && styles.progressContainerFocused,
                                ]}
                            >
                                {({ isFocused }) => (
                                    <>
                                        <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
                                        <View style={[
                                            styles.progressTrack,
                                            isFocused && styles.progressTrackFocused,
                                        ]}>
                                            <View style={[styles.progressFill, { width: `${progress}%` }]} />
                                            {isFocused && (
                                                <View style={[
                                                    styles.progressThumb,
                                                    { left: `${progress}%` },
                                                ]} />
                                            )}
                                        </View>
                                        <Text style={styles.timeText}>{formatTime(duration)}</Text>
                                    </>
                                )}
                            </FocusablePressable>
                        )}

                        <View style={styles.controlsRow}>
                            <FocusablePressable
                                ref={playButtonRef}
                                onSelect={doTogglePlayPause}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.controlButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon
                                    name={paused ? 'Play' : 'Pause'}
                                    size={scaledPixels(22)}
                                    color={colors.text}
                                />
                            </FocusablePressable>

                            {!isLive && (
                                <FocusablePressable
                                    ref={rewindButtonRef}
                                    onSelect={() => doSeek(-SEEK_STEP)}
                                    onFocus={resetHideTimer}
                                    style={({ isFocused }) => [
                                        styles.controlButton,
                                        isFocused && styles.controlButtonFocused,
                                    ]}
                                >
                                    <Icon name="SkipBack" size={scaledPixels(22)} color={colors.text} />
                                </FocusablePressable>
                            )}

                            {!isLive && (
                                <FocusablePressable
                                    ref={forwardButtonRef}
                                    onSelect={() => doSeek(SEEK_STEP)}
                                    onFocus={resetHideTimer}
                                    style={({ isFocused }) => [
                                        styles.controlButton,
                                        isFocused && styles.controlButtonFocused,
                                    ]}
                                >
                                    <Icon name="SkipForward" size={scaledPixels(22)} color={colors.text} />
                                </FocusablePressable>
                            )}

                            <View style={styles.controlsDivider} />

                            <FocusablePressable
                                ref={audioButtonRef}
                                onSelect={openAudioSelector}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.trackButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon name="Languages" size={scaledPixels(16)} color={colors.text} />
                                <Text style={styles.trackButtonText} numberOfLines={1}>
                                    {selectedAudioLabel}
                                </Text>
                            </FocusablePressable>

                            <FocusablePressable
                                ref={subtitleButtonRef}
                                onSelect={openSubtitleSelector}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.trackButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon name="Captions" size={scaledPixels(16)} color={colors.text} />
                                <Text style={styles.trackButtonText} numberOfLines={1}>
                                    {selectedSubtitleLabel}
                                </Text>
                            </FocusablePressable>
                        </View>
                    </FocusContainer>
                </FocusContainer>
            </Animated.View>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
    },
    player: {
        flex: 1,
    },
    centerOverlay: {
        ...StyleSheet.absoluteFillObject,
        justifyContent: 'center',
        alignItems: 'center',
        paddingHorizontal: scaledPixels(24),
        backgroundColor: 'rgba(0,0,0,0.35)',
    },
    loadingText: {
        marginTop: scaledPixels(12),
        color: '#ffffff',
        fontSize: scaledPixels(16),
    },
    loadingSubtext: {
        marginTop: scaledPixels(4),
        color: '#ffffff',
        fontSize: scaledPixels(12),
        opacity: 0.8,
    },
    errorTitle: {
        color: '#ffffff',
        fontSize: scaledPixels(18),
        fontWeight: '700',
        marginBottom: scaledPixels(8),
    },
    errorText: {
        color: '#ffffff',
        fontSize: scaledPixels(14),
        textAlign: 'center',
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
        backgroundColor: 'rgba(0,0,0,0.7)',
        borderRadius: scaledPixels(16),
        paddingHorizontal: scaledPixels(24),
        paddingVertical: scaledPixels(16),
        gap: scaledPixels(12),
    },
    progressContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        borderRadius: scaledPixels(8),
        paddingVertical: scaledPixels(8),
        paddingHorizontal: scaledPixels(4),
    },
    progressContainerFocused: {
        backgroundColor: 'rgba(255,255,255,0.05)',
    },
    progressTrack: {
        flex: 1,
        height: scaledPixels(6),
        backgroundColor: 'rgba(255,255,255,0.3)',
        borderRadius: scaledPixels(3),
        marginHorizontal: scaledPixels(12),
    },
    progressTrackFocused: {
        height: scaledPixels(10),
        borderRadius: scaledPixels(5),
        backgroundColor: 'rgba(255,255,255,0.4)',
    },
    progressFill: {
        height: '100%',
        backgroundColor: colors.primary,
        borderRadius: scaledPixels(5),
    },
    progressThumb: {
        position: 'absolute',
        top: '50%',
        width: scaledPixels(18),
        height: scaledPixels(18),
        borderRadius: scaledPixels(9),
        backgroundColor: colors.primary,
        borderWidth: scaledPixels(2),
        borderColor: '#fff',
        marginLeft: -scaledPixels(9),
        marginTop: -scaledPixels(9),
    },
    timeText: {
        color: colors.textSecondary,
        fontSize: scaledPixels(14),
        fontVariant: ['tabular-nums'],
        minWidth: scaledPixels(60),
        textAlign: 'center',
    },
    controlsRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(8),
    },
    controlButton: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'center',
        paddingHorizontal: scaledPixels(14),
        paddingVertical: scaledPixels(10),
        borderRadius: scaledPixels(8),
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    controlButtonFocused: {
        backgroundColor: colors.primary,
    },
    controlsDivider: {
        width: 1,
        height: scaledPixels(20),
        backgroundColor: 'rgba(255,255,255,0.2)',
        marginHorizontal: scaledPixels(4),
    },
    trackButton: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(6),
        paddingHorizontal: scaledPixels(12),
        paddingVertical: scaledPixels(10),
        borderRadius: scaledPixels(8),
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
    trackButtonText: {
        color: colors.text,
        fontSize: scaledPixels(13),
        fontWeight: '600',
    },
});
