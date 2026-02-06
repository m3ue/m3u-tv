import React, { useEffect, useCallback } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import Animated, {
    useSharedValue,
    useAnimatedStyle,
    withSpring,
    interpolate,
    Extrapolate
} from 'react-native-reanimated';
import {
    SpatialNavigationNode,
    SpatialNavigationFocusableView,
    DefaultFocus,
    useSpatialNavigatorFocusableAccessibilityProps
} from 'react-tv-space-navigation';
import { useNavigation, useRoute, useNavigationState } from '@react-navigation/native';
import { Icon, IconName } from './Icon';
import { colors } from '../theme/colors';
import { scaledPixels } from '../hooks/useScale';
import { useMenu } from '../context/MenuContext';
import { DrawerParamList } from '../navigation/types';

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
    const navigation = useNavigation<any>();
    const { isExpanded, setExpanded } = useMenu();
    const expansion = useSharedValue(0);

    const currentRouteName = useNavigationState(state => {
        if (!state) return 'Home';
        const route = state.routes[state.index];
        if (route.name === 'Main' && route.state) {
            return route.state.routes[route.state.index || 0]?.name || 'Home';
        }
        return route.name;
    });

    useEffect(() => {
        expansion.value = withSpring(isExpanded ? 1 : 0, { damping: 20, stiffness: 100 });
    }, [isExpanded]);

    const sidebarAnimatedStyle = useAnimatedStyle(() => {
        return {
            width: interpolate(
                expansion.value,
                [0, 1],
                [SIDEBAR_WIDTH_COLLAPSED, SIDEBAR_WIDTH_EXPANDED],
                Extrapolate.CLAMP
            ),
        };
    });

    const labelAnimatedStyle = useAnimatedStyle(() => {
        return {
            opacity: expansion.value,
            transform: [
                { translateX: interpolate(expansion.value, [0, 1], [-20, 0]) }
            ],
            display: expansion.value > 0.1 ? 'flex' : 'none',
        };
    });

    return (
        <SpatialNavigationNode
            onFocus={() => setExpanded(true)}
            onBlur={() => setExpanded(false)}
            orientation="vertical"
        >
            <Animated.View style={[styles.container, sidebarAnimatedStyle]}>
                <View style={styles.logoContainer}>
                    <Icon name="Play" size={scaledPixels(40)} color={colors.primary} />
                    {isExpanded && (
                        <Animated.Text style={[styles.logoText, labelAnimatedStyle]}>
                            M3U TV
                        </Animated.Text>
                    )}
                </View>

                <View style={styles.menuContainer}>
                    {MENU_ITEMS.map((item, index) => (
                        <SpatialNavigationFocusableView
                            key={item.id}
                            onSelect={() => navigation.navigate(item.id)}
                        >
                            {({ isFocused }) => (
                                <View style={[
                                    styles.menuItem,
                                    isFocused && styles.menuItemFocused,
                                    currentRouteName === item.id && !isFocused && styles.menuItemActive
                                ]}>
                                    <Icon
                                        name={item.icon}
                                        size={scaledPixels(32)}
                                        color={isFocused ? colors.text : (currentRouteName === item.id ? colors.primary : colors.textSecondary)}
                                    />
                                    <Animated.Text style={[
                                        styles.menuLabel,
                                        labelAnimatedStyle,
                                        { color: isFocused ? colors.text : (currentRouteName === item.id ? colors.primary : colors.textSecondary) }
                                    ]}>
                                        {item.label}
                                    </Animated.Text>
                                </View>
                            )}
                        </SpatialNavigationFocusableView>
                    ))}
                </View>
            </Animated.View>
        </SpatialNavigationNode>
    );
};

const styles = StyleSheet.create({
    container: {
        height: '100%',
        backgroundColor: colors.backgroundElevated,
        borderRightWidth: 1,
        borderRightColor: colors.border,
        paddingVertical: scaledPixels(40),
        overflow: 'hidden',
        zIndex: 100,
    },
    logoContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: scaledPixels(30),
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
        paddingHorizontal: scaledPixels(34),
        marginVertical: scaledPixels(5),
        borderRadius: scaledPixels(8),
        marginHorizontal: scaledPixels(10),
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
