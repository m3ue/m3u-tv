import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { View, StyleSheet, Text, Animated } from 'react-native';
import Video, { OnVideoErrorData, ResizeMode } from 'react-native-video';
import { VLCPlayer } from 'react-native-vlc-media-player';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';

const OVERLAY_TIMEOUT = 5000;
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

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title, type } = route.params;
    const [overlayVisible, setOverlayVisible] = useState(true);
    const initialBackend = useMemo(() => getInitialBackend(streamUrl), [streamUrl]);
    const [backend, setBackend] = useState<PlayerBackend>(initialBackend);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    console.log(`[Player] Loading ${type} stream: ${title}`);
    console.log(`[Player] URL: ${streamUrl}`);
    console.log(`[Player] Backend: ${backend}`);

    const handleNativeError = useCallback((error: OnVideoErrorData) => {
        console.warn('[Player] react-native-video error, falling back to VLC:', error.error);
        setBackend('vlc');
    }, []);

    const handleVlcError = useCallback(() => {
        console.error('[Player] VLC also failed to play stream');
    }, []);

    // --- Overlay logic ---

    const hideOverlay = useCallback(() => {
        Animated.timing(fadeAnim, {
            toValue: 0,
            duration: 300,
            useNativeDriver: true,
        }).start(() => setOverlayVisible(false));
    }, [fadeAnim]);

    const showOverlay = useCallback(() => {
        setOverlayVisible(true);
        fadeAnim.setValue(1);
        clearTimeout(hideTimer.current);
        hideTimer.current = setTimeout(hideOverlay, OVERLAY_TIMEOUT);
    }, [fadeAnim, hideOverlay]);

    useEffect(() => {
        hideTimer.current = setTimeout(hideOverlay, OVERLAY_TIMEOUT);
        return () => clearTimeout(hideTimer.current);
    }, [hideOverlay]);

    return (
        <View style={styles.container}>
            {backend === 'native' ? (
                <Video
                    source={{
                        uri: streamUrl,
                        headers: { 'User-Agent': USER_AGENT },
                    }}
                    style={styles.video}
                    resizeMode={ResizeMode.CONTAIN}
                    controls={true}
                    onError={handleNativeError}
                    onLoad={() => console.log('[Player] Native video loaded')}
                    onBuffer={({ isBuffering }) =>
                        console.log('[Player] Buffering:', isBuffering)
                    }
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
                    onError={handleVlcError}
                    onPlaying={() => console.log('[Player] VLC playing')}
                    onBuffering={() => console.log('[Player] VLC buffering')}
                />
            )}

            {overlayVisible && (
                <Animated.View
                    style={[styles.overlay, { opacity: fadeAnim }]}
                    pointerEvents="box-none"
                >
                    <View style={styles.header}>
                        <FocusablePressable
                            onSelect={() => navigation.goBack()}
                            style={styles.backButton}
                        >
                            <Icon name="ArrowLeft" size={scaledPixels(32)} color={colors.text} />
                        </FocusablePressable>
                        <Text style={styles.title}>{title}</Text>
                    </View>
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
        color: colors.text,
        fontSize: scaledPixels(24),
        fontWeight: 'bold',
        marginLeft: scaledPixels(20),
        textShadowColor: 'black',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 5,
    },
    tapZone: {
        ...StyleSheet.absoluteFillObject,
    },
});
