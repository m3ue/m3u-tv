import React, { useEffect, useCallback } from 'react';
import { View, Text, StyleSheet, Image, Pressable } from 'react-native';
import Animated, {
    useSharedValue,
    useAnimatedStyle,
    withSpring,
    interpolate,
    Extrapolate
} from 'react-native-reanimated';
import {
    SpatialNavigationNode,
    DefaultFocus,
} from 'react-tv-space-navigation';
import { useNavigation, useNavigationState } from '@react-navigation/native';
import { Icon, IconName } from './Icon';
import { colors } from '../theme/colors';
import { scaledPixels } from '../hooks/useScale';
import { useMenu } from '../context/MenuContext';
import { DrawerParamList } from '../navigation/types';
import { FocusablePressable } from './FocusablePressable';
import { navigationRef } from '../navigation/navigationRef';

const SIDEBAR_WIDTH_COLLAPSED = scaledPixels(100);
const SIDEBAR_WIDTH_EXPANDED = scaledPixels(300);

// Export these for use in screens
export { SIDEBAR_WIDTH_COLLAPSED, SIDEBAR_WIDTH_EXPANDED };

interface MenuItem {
    id: keyof DrawerParamList;
    label: string;
    icon: IconName;
}

const MENU_ITEMS: MenuItem[] = [
    { id: 'Home', label: 'Home', icon: 'Home' },
    { id: 'LiveTV', label: 'Live TV', icon: 'Tv' },
    { id: 'EPG', label: 'TV Guide', icon: 'Calendar' },
    { id: 'VOD', label: 'Movies', icon: 'Film' },
    { id: 'Series', label: 'Series', icon: 'Tv2' },
    { id: 'Settings', label: 'Settings', icon: 'Settings' },
];

export const SideBar = () => {
    const { isExpanded, setExpanded } = useMenu();
    const navigation = useNavigation<any>();

    const currentRouteName = useNavigationState(state => {
        if (!state) return 'Home';
        let route: any = state.routes[state.index];
        while (route?.state && typeof route.state.index === 'number') {
            route = route.state.routes[route.state.index];
        }
        return route?.name || 'Home';
    });

    useEffect(() => {
        console.log('[SideBar] Active screen changed to:', currentRouteName);
    }, [currentRouteName]);

    const width = isExpanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED;

    return (
        <SpatialNavigationNode
            onFocus={() => setExpanded(true)}
            onBlur={() => setExpanded(false)}
            orientation="vertical"
            isFocusable={false}
        >
            <View style={[styles.container, { width }]}>
                <View style={styles.logoContainer}>
                    <Image source={require('../../assets/logo.png')} style={{ width: scaledPixels(60), height: scaledPixels(60) }} />
                    {isExpanded && (
                        <Text style={styles.logoText}>
                            M3U TV
                        </Text>
                    )}
                </View>

                <View style={styles.menuContainer}>
                    {MENU_ITEMS.map((item, index) => (
                        <FocusablePressable
                            key={item.id}
                            onFocus={() => console.log(`[SideBar] Item focused: ${item.id}`)}
                            onSelect={() => {
                                console.log(`[SideBar] onSelect triggered for: ${item.id}`);
                                if (navigationRef.isReady()) {
                                    // @ts-ignore
                                    navigationRef.navigate('Main', { screen: item.id });
                                }
                            }}
                            style={({ isFocused }) => [
                                styles.menuItem,
                                isFocused && styles.menuItemFocused,
                                currentRouteName === item.id && !isFocused && styles.menuItemActive
                            ]}
                        >
                            {({ isFocused }) => (
                                <>
                                    <Icon
                                        name={item.icon}
                                        size={scaledPixels(32)}
                                        color={isFocused ? colors.text : (currentRouteName === item.id ? colors.primary : colors.textSecondary)}
                                    />
                                    {isExpanded && (
                                        <Text style={[
                                            styles.menuLabel,
                                            { color: isFocused ? colors.text : (currentRouteName === item.id ? colors.primary : colors.textSecondary) }
                                        ]}>
                                            {item.label}
                                        </Text>
                                    )}
                                </>
                            )}
                        </FocusablePressable>
                    ))}
                </View>
            </View>
        </SpatialNavigationNode>
    );
};

const styles = StyleSheet.create({
    container: {
        height: '100%',

        paddingVertical: scaledPixels(40),
        overflow: 'hidden',
        zIndex: 100,
    },
    logoContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: scaledPixels(20),
        marginBottom: scaledPixels(60),
    },
    logoText: {
        color: colors.text,
        fontSize: scaledPixels(28),
        fontWeight: 'bold',
        marginLeft: scaledPixels(15),
    },
    menuContainer: {
        flex: 1,
    },
    menuItem: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: scaledPixels(20),
        paddingHorizontal: scaledPixels(24),
        marginVertical: scaledPixels(5),
        borderRadius: scaledPixels(8),
        marginHorizontal: scaledPixels(10),
        minHeight: scaledPixels(70),
    },
    menuItemFocused: {
        backgroundColor: colors.primary,
    },
    menuItemActive: {
        backgroundColor: 'transparent',
    },
    menuLabel: {
        fontSize: scaledPixels(20),
        marginLeft: scaledPixels(20),
        fontWeight: '500',
    },
});
