import React, { useEffect } from 'react';
import { View, StyleSheet, Text, Platform } from 'react-native';
import { useVideoPlayer, VideoView } from 'expo-video';
import { RootStackScreenProps } from '../navigation/types';
import { colors } from '../theme';
import { FocusablePressable } from '../components/FocusablePressable';
import { Icon } from '../components/Icon';
import { scaledPixels } from '../hooks/useScale';

export const PlayerScreen = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl, title } = route.params;

    const player = useVideoPlayer(streamUrl, (player) => {
        player.loop = false;
        player.play();
    });

    useEffect(() => {
        return () => {
            player.pause();
        };
    }, [player]);

    return (
        <View style={styles.container}>
            <VideoView
                style={styles.video}
                player={player}
                allowsFullscreen
                allowsPictureInPicture
            />

            {/* Custom Overlay for TV Controls can be added here */}
            <View style={styles.overlay}>
                <View style={styles.header}>
                    <FocusablePressable
                        onSelect={() => navigation.goBack()}
                        style={styles.backButton}
                    >
                        <Icon name="ArrowLeft" size={scaledPixels(32)} color={colors.text} />
                    </FocusablePressable>
                    <Text style={styles.title}>{title}</Text>
                </View>
            </View>
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
});
