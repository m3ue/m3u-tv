import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, StyleSheet, Text, Pressable, ActivityIndicator, Animated } from 'react-native';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { FocusablePressable, FocusablePressableRef } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { useViewer } from '../context/ViewerContext';
import { useXtream } from '../context/XtreamContext';
import { useTVRemoteEvents } from '../hooks/useTVRemoteEvents';
import { epgService } from '../services/EpgService';

const OVERLAY_TIMEOUT = 5000;
const SEEK_STEP = 10;
const PROGRESS_INTERVAL_MS = 10_000;

// Check if we're running inside Electron
const electronAPI = typeof window !== 'undefined' ? (window as any).electronAPI : undefined;
const isElectron = !!electronAPI?.isElectron;

function formatTime(seconds: number): string {
    const safeSeconds = Number.isFinite(seconds) ? seconds : 0;
    const s = Math.max(0, Math.floor(safeSeconds));
    const h = Math.floor(s / 3600);
    const m = Math.floor((s % 3600) / 60);
    const sec = s % 60;
    const pad = (n: number) => n.toString().padStart(2, '0');
    return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title, type, streamId, seriesId, seasonNumber, startPosition, epgChannelId } = route.params;
    const isLive = type === 'live';

    const { isM3UEditor } = useXtream();
    const { activeViewer, updateProgress } = useViewer();

    const videoRef = useRef<HTMLVideoElement | null>(null);
    const hlsRef = useRef<any>(null);
    const playButtonRef = useRef<FocusablePressableRef>(null);

    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [paused, setPaused] = useState(false);
    const [currentTime, setCurrentTime] = useState(0);
    const [duration, setDuration] = useState(0);
    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);
    const overlayVisibleRef = useRef(overlayVisible);
    const currentTimeRef = useRef(0);
    const durationRef = useRef(0);
    const exitGuardRef = useRef(false);

    const [epgCurrent, setEpgCurrent] = useState<{ title: string; progress: number } | null>(null);
    const [epgNext, setEpgNext] = useState<string | null>(null);

    useEffect(() => {
        overlayVisibleRef.current = overlayVisible;
    }, [overlayVisible]);

    const goBackSafe = useCallback(() => {
        if (exitGuardRef.current) return;
        exitGuardRef.current = true;
        navigation.goBack();
    }, [navigation]);

    const hideOverlayAnim = useCallback(() => {
        Animated.timing(fadeAnim, {
            toValue: 0,
            duration: 300,
            useNativeDriver: false,
        }).start(() => setOverlayVisible(false));
    }, [fadeAnim]);

    const resetHideTimer = useCallback(() => {
        clearTimeout(hideTimer.current);
        hideTimer.current = setTimeout(hideOverlayAnim, OVERLAY_TIMEOUT);
    }, [hideOverlayAnim]);

    const showOverlay = useCallback(() => {
        setOverlayVisible(true);
        fadeAnim.setValue(1);
        resetHideTimer();
        setTimeout(() => playButtonRef.current?.focus(), 150);
    }, [fadeAnim, resetHideTimer]);

    const doSeek = useCallback((offset: number) => {
        const video = videoRef.current;
        if (!video || isLive) return;
        video.currentTime = Math.max(0, Math.min(video.currentTime + offset, video.duration || 0));
    }, [isLive]);

    const doTogglePlayPause = useCallback(() => {
        const video = videoRef.current;
        if (!video) return;
        if (video.paused) {
            video.play().catch(() => {});
        } else {
            video.pause();
        }
    }, []);

    // Fetch EPG data for live channel
    useEffect(() => {
        if (!isLive || !streamId) return;

        let interval: ReturnType<typeof setInterval>;
        let cancelled = false;

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
    }, [isLive, streamId, epgChannelId]);

    // Guard to prevent multiple external player launches
    const externalPlayerLaunched = useRef(false);
    const [externalPlaying, setExternalPlaying] = useState(false);

    // Listen for external player close to navigate back
    useEffect(() => {
        if (!externalPlaying || !electronAPI?.onExternalPlayerClosed) return;
        const cleanup = electronAPI.onExternalPlayerClosed(() => {
            setExternalPlaying(false);
            externalPlayerLaunched.current = false;
            goBackSafe();
        });
        return cleanup;
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [externalPlaying]);

    // Try to open the stream in an external player (mpv/vlc) when in Electron
    const openInExternalPlayer = useCallback(async () => {
        if (!electronAPI?.openExternal) return;
        if (externalPlayerLaunched.current) return;
        externalPlayerLaunched.current = true;

        setError(null);
        setIsLoading(false);
        setExternalPlaying(true);
        try {
            const result = await electronAPI.openExternal(streamUrl, startPosition || 0);
            if (!result.success) {
                setError(result.error || 'Failed to open external player');
                setExternalPlaying(false);
                externalPlayerLaunched.current = false;
            }
            // Don't goBack — let the user close mpv and come back manually
        } catch (err: any) {
            setError(`External player error: ${err?.message || err}`);
            setExternalPlaying(false);
            externalPlayerLaunched.current = false;
        }
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [streamUrl]);

    // Video playback setup
    useEffect(() => {
        const video = videoRef.current;
        if (!video) return;

        // In Electron: always use external player (mpv/vlc)
        // Chromium can't play raw MPEG-TS, MKV, or most IPTV formats
        if (isElectron) {
            openInExternalPlayer();
            return;
        }

        // Browser playback: try HLS.js for .m3u8, direct for MP4/WebM
        const isHls = streamUrl.includes('.m3u8');

        if (isHls && !video.canPlayType('application/vnd.apple.mpegurl')) {
            let cancelled = false;
            import('hls.js').then(({ default: Hls }) => {
                if (cancelled) return;
                if (!Hls.isSupported()) {
                    setError('HLS is not supported in this browser.');
                    setIsLoading(false);
                    return;
                }

                const hls = new Hls({
                    enableWorker: true,
                    lowLatencyMode: isLive,
                    xhrSetup: (xhr: XMLHttpRequest) => {
                        xhr.withCredentials = false;
                    },
                });
                hlsRef.current = hls;
                hls.loadSource(streamUrl);
                hls.attachMedia(video);

                hls.on(Hls.Events.MANIFEST_PARSED, () => {
                    setIsLoading(false);
                    if (startPosition && startPosition > 0) {
                        video.currentTime = startPosition;
                    }
                    video.play().catch(() => {});
                });

                let mediaErrorRecoveries = 0;
                hls.on(Hls.Events.ERROR, (_: any, data: any) => {
                    if (data.fatal) {
                        if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
                            hls.startLoad();
                        } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR && mediaErrorRecoveries < 2) {
                            mediaErrorRecoveries++;
                            hls.recoverMediaError();
                        } else {
                            setError(`Playback Error: ${data.details}`);
                            setIsLoading(false);
                        }
                    }
                });
            }).catch((err) => {
                setError(`Failed to load HLS player: ${err?.message || err}`);
                setIsLoading(false);
            });

            return () => {
                cancelled = true;
                hlsRef.current?.destroy();
                hlsRef.current = null;
            };
        } else {
            // Direct playback (native HLS on Safari, or MP4/WebM)
            video.src = streamUrl;
            video.load();

            const onCanPlay = () => {
                setIsLoading(false);
                if (startPosition && startPosition > 0) {
                    video.currentTime = startPosition;
                }
                video.play().catch(() => {});
            };

            const onError = () => {
                setError('Failed to load video. The format may not be supported in the browser.');
                setIsLoading(false);
            };

            video.addEventListener('canplay', onCanPlay);
            video.addEventListener('error', onError);

            return () => {
                video.removeEventListener('canplay', onCanPlay);
                video.removeEventListener('error', onError);
                video.src = '';
            };
        }
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [streamUrl, isLive, startPosition]);

    // Sync video element state
    useEffect(() => {
        const video = videoRef.current;
        if (!video) return;

        const onTimeUpdate = () => {
            const t = video.currentTime || 0;
            setCurrentTime(t);
            currentTimeRef.current = t;
        };
        const onDurationChange = () => {
            const d = video.duration || 0;
            if (Number.isFinite(d)) {
                setDuration(d);
                durationRef.current = d;
            }
        };
        const onPlay = () => setPaused(false);
        const onPause = () => setPaused(true);
        const onEnded = () => goBackSafe();

        video.addEventListener('timeupdate', onTimeUpdate);
        video.addEventListener('durationchange', onDurationChange);
        video.addEventListener('play', onPlay);
        video.addEventListener('pause', onPause);
        video.addEventListener('ended', onEnded);

        return () => {
            video.removeEventListener('timeupdate', onTimeUpdate);
            video.removeEventListener('durationchange', onDurationChange);
            video.removeEventListener('play', onPlay);
            video.removeEventListener('pause', onPause);
            video.removeEventListener('ended', onEnded);
        };
    }, [goBackSafe]);

    // Mouse movement shows overlay
    useEffect(() => {
        let mouseTimer: ReturnType<typeof setTimeout> | undefined;
        const onMouseMove = () => {
            if (!overlayVisibleRef.current) {
                showOverlay();
            } else {
                resetHideTimer();
            }
        };

        document.addEventListener('mousemove', onMouseMove);
        return () => {
            document.removeEventListener('mousemove', onMouseMove);
            clearTimeout(mouseTimer);
        };
    }, [showOverlay, resetHideTimer]);

    // Keyboard / remote events
    useTVRemoteEvents((event) => {
        if (!overlayVisibleRef.current) {
            if (event === 'back') {
                goBackSafe();
                return;
            }
            showOverlay();
            return;
        }

        switch (event) {
            case 'back':
                hideOverlayAnim();
                break;
            case 'playPause':
                doTogglePlayPause();
                resetHideTimer();
                break;
            case 'left':
                doSeek(-SEEK_STEP);
                resetHideTimer();
                break;
            case 'right':
                doSeek(SEEK_STEP);
                resetHideTimer();
                break;
            case 'longLeft':
                doSeek(-30);
                resetHideTimer();
                break;
            case 'longRight':
                doSeek(30);
                resetHideTimer();
                break;
            case 'fastForward':
                doSeek(SEEK_STEP);
                resetHideTimer();
                break;
            case 'rewind':
                doSeek(-SEEK_STEP);
                resetHideTimer();
                break;
            default:
                resetHideTimer();
        }
    });

    // Overlay hide timer
    useEffect(() => {
        resetHideTimer();
        return () => clearTimeout(hideTimer.current);
    }, [overlayVisible, resetHideTimer]);

    // Watch progress tracking
    useEffect(() => {
        if (!isM3UEditor || !activeViewer || !streamId) return;

        if (isLive) {
            updateProgress({ content_type: 'live', stream_id: streamId });
            return;
        }

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

    const canSeek = !isLive && duration > 0;
    const progress = canSeek ? (currentTime / duration) * 100 : 0;

    return (
        <View style={styles.container}>
            <video
                ref={videoRef as any}
                style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    width: '100%',
                    height: '100%',
                    backgroundColor: '#000',
                    objectFit: 'contain',
                }}
                autoPlay
                playsInline
            />

            {externalPlaying && (
                <View style={styles.centerOverlay}>
                    <Text style={styles.loadingText}>Playing in external player</Text>
                    <FocusablePressable
                        onSelect={goBackSafe}
                        style={({ isFocused }) => [
                            styles.backButton,
                            { marginTop: scaledPixels(20) },
                            isFocused && styles.controlButtonFocused,
                        ]}
                    >
                        <Text style={{ color: colors.text, fontSize: scaledPixels(16) }}>Go Back</Text>
                    </FocusablePressable>
                </View>
            )}

            {isLoading && !error && !externalPlaying && (
                <View style={styles.centerOverlay} pointerEvents="none">
                    <ActivityIndicator color="#ffffff" size="large" />
                    <Text style={styles.loadingText}>Loading stream...</Text>
                </View>
            )}

            {error && (
                <View style={styles.centerOverlay}>
                    <Text style={styles.errorTitle}>Playback error</Text>
                    <Text style={styles.errorText}>{error}</Text>
                </View>
            )}

            {!overlayVisible && (
                <Pressable style={StyleSheet.absoluteFill} onPress={showOverlay} />
            )}

            <Animated.View
                style={[styles.overlay, { opacity: fadeAnim }]}
                pointerEvents={overlayVisible ? 'auto' : 'none'}
            >
                <View style={styles.overlayInner}>
                    <View style={styles.header}>
                        <FocusablePressable
                            onSelect={goBackSafe}
                            style={({ isFocused }) => [
                                styles.backButton,
                                isFocused && styles.controlButtonFocused,
                            ]}
                        >
                            <Icon name="ArrowLeft" size={scaledPixels(22)} color={colors.text} />
                        </FocusablePressable>
                        <View style={styles.headerInfo}>
                            <Text style={styles.title} numberOfLines={1}>{title}</Text>
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

                    <View style={styles.controlsBar}>
                        {canSeek && (
                            <View style={styles.progressContainer}>
                                <Text style={styles.timeText}>{formatTime(currentTime)}</Text>
                                <Pressable
                                    style={styles.progressTrack}
                                    onPress={(e: any) => {
                                        const rect = e.target?.getBoundingClientRect?.();
                                        if (rect && videoRef.current) {
                                            const fraction = (e.nativeEvent.pageX - rect.left) / rect.width;
                                            videoRef.current.currentTime = fraction * (videoRef.current.duration || 0);
                                        }
                                    }}
                                >
                                    <View style={[styles.progressFill, { width: `${progress}%` }]} />
                                    <View style={[styles.progressThumb, { left: `${progress}%` }]} />
                                </Pressable>
                                <Text style={styles.timeText}>{formatTime(duration)}</Text>
                            </View>
                        )}

                        <View style={styles.controlsRow}>
                            <FocusablePressable
                                ref={playButtonRef}
                                preferredFocus
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
                                onSelect={() => {
                                    const video = videoRef.current;
                                    if (video?.requestFullscreen) {
                                        video.requestFullscreen().catch(() => {});
                                    }
                                }}
                                onFocus={resetHideTimer}
                                style={({ isFocused }) => [
                                    styles.controlButton,
                                    isFocused && styles.controlButtonFocused,
                                ]}
                            >
                                <Icon name="Maximize" size={scaledPixels(16)} color={colors.text} />
                            </FocusablePressable>
                        </View>
                    </View>
                </View>
            </Animated.View>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
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
    },
    backButton: {
        padding: scaledPixels(10),
        borderRadius: scaledPixels(50),
        backgroundColor: 'rgba(0,0,0,0.5)',
        marginTop: scaledPixels(4),
    },
    headerInfo: {
        flex: 1,
        marginLeft: scaledPixels(10),
        marginBottom: scaledPixels(16),
    },
    title: {
        color: colors.text,
        fontSize: scaledPixels(32),
        fontWeight: 'bold',
    },
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
        paddingVertical: scaledPixels(8),
        paddingHorizontal: scaledPixels(4),
    },
    progressTrack: {
        flex: 1,
        height: scaledPixels(8),
        backgroundColor: 'rgba(255,255,255,0.3)',
        borderRadius: scaledPixels(4),
        marginHorizontal: scaledPixels(12),
        cursor: 'pointer' as any,
    },
    progressFill: {
        height: '100%',
        backgroundColor: colors.primary,
        borderRadius: scaledPixels(4),
    },
    progressThumb: {
        position: 'absolute',
        top: '50%',
        width: scaledPixels(16),
        height: scaledPixels(16),
        borderRadius: scaledPixels(8),
        backgroundColor: colors.primary,
        borderWidth: scaledPixels(2),
        borderColor: '#fff',
        marginLeft: -scaledPixels(8),
        marginTop: -scaledPixels(8),
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
        cursor: 'pointer' as any,
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
});
