import React from 'react';
import { View, StyleSheet, Text } from 'react-native';
import { RootStackScreenProps } from '../navigation/types';

export const PlayerScreenNew = ({ route, navigation }: RootStackScreenProps<'Player'>) => {
    const { streamUrl } = route.params;

    return (
        <View style={styles.container}>
            <Text style={{ color: '#ffffff' }}>Todo: Implement</Text>
        </View>
    );
};

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
    },
});
