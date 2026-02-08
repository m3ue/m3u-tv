import React, { useCallback, useEffect, useRef, useState } from 'react';
import { View, StyleSheet, Text, Animated } from 'react-native';
import { useVideoPlayer, VideoView } from 'expo-video';
import { useEventListener } from 'expo';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';

const OVERLAY_TIMEOUT = 5000;

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title } = route.params;
    const [overlayVisible, setOverlayVisible] = useState(true);
    const fadeAnim = useRef(new Animated.Value(1)).current;
    const hideTimer = useRef<ReturnType<typeof setTimeout>>(undefined);

    const player = useVideoPlayer(streamUrl, (player) => {
        player.loop = false;
        player.play();
    });

    // Debug: log status changes
    useEventListener(player, 'statusChange', ({ status, error }) => {
        console.log('[Player] Status:', status, error ? `Error: ${error.message}` : '');
    });

    useEventListener(player, 'playingChange', ({ isPlaying }) => {
        console.log('[Player] Playing:', isPlaying);
    });

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

    // Auto-hide overlay after initial display
    useEffect(() => {
        hideTimer.current = setTimeout(hideOverlay, OVERLAY_TIMEOUT);
        return () => clearTimeout(hideTimer.current);
    }, [hideOverlay]);

    return (
        <View style={styles.container}>
            <VideoView
                style={styles.video}
                player={player}
                nativeControls
                contentFit="contain"
            />

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
