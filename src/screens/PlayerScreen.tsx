import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useViewer } from '../context/ViewerContext';
import { useXtream } from '../context/XtreamContext';
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
import { epgService } from '../services/EpgService';

const OVERLAY_TIMEOUT = 8000;
const SEEK_STEP = 10;
const TIMELINE_SEEK_STEP = 30;
const LOADING_TIMEOUT_MS = 20_000;
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

const PROGRESS_INTERVAL_MS = 10_000; // Report progress every 10 seconds

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title, type, streamId, seriesId, seasonNumber, startPosition } = route.params;
    const isLive = type === 'live';

    const { isM3UEditor } = useXtream();
    const { activeViewer, updateProgress } = useViewer();

    const [currentStreamUrl, setCurrentStreamUrl] = useState(streamUrl);
    const formatRetried = useRef(false);

    const initialBackend = useMemo(() => getInitialBackend(currentStreamUrl), [currentStreamUrl]);
    const [backend, setBackend] = useState<PlayerBackend>(initialBackend);

    const rewindButtonRef = useRef<FocusablePressableRef>(null);
    const playButtonRef = useRef<FocusablePressableRef>(null);
    const forwardButtonRef = useRef<FocusablePressableRef>(null);
    const timelineRef = useRef<FocusablePressableRef>(null);
    const timelineFocusedRef = useRef(false);
    const audioButtonRef = useRef<FocusablePressableRef>(null);
    const subtitleButtonRef = useRef<FocusablePressableRef>(null);
    const backButtonRef = useRef<FocusablePressableRef>(null);
    const selectGuardRef = useRef(false);

    // EPG info for live channels
    const [epgCurrent, setEpgCurrent] = useState<{ title: string; progress: number } | null>(null);
    const [epgNext, setEpgNext] = useState<string | null>(null);

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
    const startPositionRef = useRef(startPosition ?? 0);
    const hasSeekedToStartRef = useRef(false);
    const loadingTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);

    // Loading timeout: if stream never loads or errors, show a timeout message
    useEffect(() => {
        if (isLoading && !error) {
            loadingTimerRef.current = setTimeout(() => {
                if (isLoading) {
                    setIsLoading(false);
                    setError('Stream loading timed out. The server may be unreachable or the stream URL is invalid.');
                }
            }, LOADING_TIMEOUT_MS);
        } else {
            clearTimeout(loadingTimerRef.current);
        }
        return () => clearTimeout(loadingTimerRef.current);
    }, [isLoading, error]);

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

    // Watch progress tracking
    useEffect(() => {
        if (!isM3UEditor || !activeViewer || !streamId) return;

        if (isLive) {
            // For live TV, report once on mount to increment watch count
            updateProgress({ content_type: 'live', stream_id: streamId });
            return;
        }

        // For VOD/episode, report every 10 seconds
        const interval = setInterval(() => {
            updateProgress({
                content_type: type === 'series' ? 'episode' : 'vod',
                stream_id: streamId,
                position_seconds: Math.floor(currentTimeRef.current),
                duration_seconds: durationRef.current > 0 ? Math.floor(durationRef.current) : undefined,
                series_id: seriesId,
                season_number: seasonNumber,
            });
        }, PROGRESS_INTERVAL_MS);

        return () => {
            clearInterval(interval);
            // Final update on unmount
            if (currentTimeRef.current > 0) {
                updateProgress({
                    content_type: type === 'series' ? 'episode' : 'vod',
                    stream_id: streamId,
                    position_seconds: Math.floor(currentTimeRef.current),
                    duration_seconds: durationRef.current > 0 ? Math.floor(durationRef.current) : undefined,
                    series_id: seriesId,
                    season_number: seasonNumber,
                });
            }
        };
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [isM3UEditor, activeViewer, streamId, isLive, type, seriesId, seasonNumber]);

    // Fetch EPG data for live channel
    useEffect(() => {
        if (!isLive || !streamId) return;

        let interval: ReturnType<typeof setInterval>;
        let cancelled = false;

        const epgChannelId = route.params.epgChannelId;

        const updateEpg = async () => {
            const data = await epgService.getCurrentAndNextAsync(
                epgChannelId || '',
                streamId,
            );
            if (cancelled) return;

            if (!data) {
                setEpgCurrent(null);
                setEpgNext(null);
                return;
            }

            setEpgCurrent({ title: data.currentTitle, progress: data.currentProgress });
            setEpgNext(data.nextTitle);
        };

        updateEpg();
        interval = setInterval(updateEpg, 30000);

        return () => {
            cancelled = true;
            clearInterval(interval);
        };
    }, [isLive, streamId, route.params.epgChannelId]);

    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const overlayVisibleRef = useRef(overlayVisible);

    useEffect(() => {
        overlayVisibleRef.current = overlayVisible;
    }, [overlayVisible]);

    const nativeSourceRef = useRef<any>(null);
    const vlcSourceRef = useRef<any>(null);

    if (!nativeSourceRef.current || nativeSourceRef.current.uri !== currentStreamUrl) {
        nativeSourceRef.current = {
            uri: currentStreamUrl,
            headers: { 'User-Agent': USER_AGENT },
            isNetwork: true,
        };
        vlcSourceRef.current = {
            uri: currentStreamUrl,
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

        // Guard: prevent the same OK press from triggering play/pause
        selectGuardRef.current = true;
        setTimeout(() => {
            selectGuardRef.current = false;
            playButtonRef.current?.focus();
        }, 200);
    }, [fadeAnim, resetHideTimer]);

    useEffect(() => {
        resetHideTimer();
        if (overlayVisible) {
            setTimeout(() => {
                playButtonRef.current?.focus();
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
        if (selectGuardRef.current) return;
        setPaused((prev) => !prev);
    }, []);

    const openAudioSelector = useCallback(() => {
        if (selectGuardRef.current) return;
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
        if (selectGuardRef.current) return;
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
        const loadedDuration = data.duration || 0;
        setDuration(loadedDuration);

        if (startPositionRef.current > 0 && !hasSeekedToStartRef.current && loadedDuration > 0) {
            hasSeekedToStartRef.current = true;
            nativeRef.current?.seek(startPositionRef.current);
        }

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
        const errorStr = JSON.stringify(nativeError).toLowerCase();

        // Check if this is a non-recoverable HTTP error (403/404)
        const isHttpForbidden = errorStr.includes('403') || errorStr.includes('io_bad_http_status');
        const isHttpNotFound = errorStr.includes('404');

        if (isHttpForbidden || isHttpNotFound) {
            console.error('[PlayerScreen] HTTP error (non-recoverable)', nativeError);
            setIsLoading(false);
            setError(
                isHttpForbidden
                    ? 'Stream not available (403 Forbidden). The server rejected the connection.'
                    : 'Stream not found (404). The channel may have been removed.',
            );
            return;
        }

        // If HLS parse error and we haven't tried swapping format yet, try .ts ↔ .m3u8
        if (backendRef.current === 'native' && !formatRetried.current) {
            const isFormatError = errorStr.includes('parserexception') ||
                errorStr.includes('parsing_manifest') ||
                errorStr.includes('contentismalformed');

            if (isFormatError) {
                formatRetried.current = true;
                setCurrentStreamUrl((prev) => {
                    const newUrl = prev.endsWith('.m3u8')
                        ? prev.replace(/\.m3u8$/, '.ts')
                        : prev.endsWith('.ts')
                            ? prev.replace(/\.ts$/, '.m3u8')
                            : prev;
                    return newUrl;
                });
                setError(null);
                setIsLoading(true);
                return;
            }
        }

        console.error('[PlayerScreen] Playback error', nativeError);

        if (backendRef.current === 'native') {
            console.log('[PlayerScreen] Native failed, switching to VLC backend');
            setBackend('vlc');
            setError(null);
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
        const durSeconds = (data.duration || 0) / 1000;
        setDuration(durSeconds);

        if (startPositionRef.current > 0 && !hasSeekedToStartRef.current && durSeconds > 0) {
            hasSeekedToStartRef.current = true;
            const fraction = startPositionRef.current / durSeconds;
            setVlcSeekValue(fraction);
            setTimeout(() => setVlcSeekValue(-1), 300);
        }

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
                        key={`native-${currentStreamUrl}`}
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
                        key={`vlc-${currentStreamUrl}`}
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
                                isFocused && styles.backButtonFocused,
                            ]}
                        >
                            <Icon name="ArrowLeft" size={scaledPixels(24)} color={colors.text} />
                        </FocusablePressable>
                        <View style={styles.headerInfo}>
                            <Text style={styles.title} numberOfLines={1}>
                                {title}
                            </Text>
                            {isLive && epgCurrent && (
                                <View style={styles.epgInfoRow}>
                                    <View style={styles.epgCurrentRow}>
                                        <View style={styles.epgLiveBadge}>
                                            <Text style={styles.epgLiveBadgeText}>LIVE</Text>
                                        </View>
                                        <Text style={styles.epgCurrentTitle} numberOfLines={1}>
                                            {epgCurrent.title}
                                        </Text>
                                    </View>
                                    <View style={styles.epgProgressBg}>
                                        <View style={[styles.epgProgressFill, { width: `${Math.round(epgCurrent.progress * 100)}%` }]} />
                                    </View>
                                    {epgNext && (
                                        <Text style={styles.epgNextText} numberOfLines={1}>
                                            Next: {epgNext}
                                        </Text>
                                    )}
                                </View>
                            )}
                        </View>
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
        justifyContent: 'flex-end' as const,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: scaledPixels(12),
        marginBottom: scaledPixels(16),
    },
    backButton: {
        padding: scaledPixels(10),
        borderRadius: scaledPixels(50),
        backgroundColor: 'rgba(0,0,0,0.5)',
        borderWidth: 2,
        borderColor: 'transparent',
    },
    backButtonFocused: {
        backgroundColor: colors.primary,
        borderColor: colors.primary,
    },
    headerInfo: {
        flex: 1,
    },
    title: {
        color: colors.text,
        fontSize: scaledPixels(32),
        fontWeight: 'bold',
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 5,
    },
    // EPG info in player overlay
    epgInfoRow: {
        marginTop: scaledPixels(8),
        gap: scaledPixels(4),
    },
    epgCurrentRow: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: scaledPixels(8),
    },
    epgLiveBadge: {
        backgroundColor: colors.primary,
        paddingHorizontal: scaledPixels(8),
        paddingVertical: scaledPixels(2),
        borderRadius: scaledPixels(4),
    },
    epgLiveBadgeText: {
        color: '#ffffff',
        fontSize: scaledPixels(11),
        fontWeight: '700',
    },
    epgCurrentTitle: {
        flex: 1,
        color: 'rgba(255,255,255,0.9)',
        fontSize: scaledPixels(18),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 3,
    },
    epgProgressBg: {
        height: scaledPixels(3),
        borderRadius: scaledPixels(2),
        backgroundColor: 'rgba(255,255,255,0.2)',
        overflow: 'hidden',
        maxWidth: scaledPixels(400),
    },
    epgProgressFill: {
        height: '100%',
        borderRadius: scaledPixels(2),
        backgroundColor: colors.primary,
    },
    epgNextText: {
        color: 'rgba(255,255,255,0.75)',
        fontSize: scaledPixels(15),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 4,
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
