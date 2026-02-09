import React, { useEffect, useCallback, useRef } from 'react';
import { View, Text, StyleSheet, Image, Pressable } from 'react-native';
import Animated, {
    useSharedValue,
    useAnimatedStyle,
    withSpring,
    withRepeat,
    withSequence,
    withTiming,
    interpolate,
    Extrapolate,
    cancelAnimation,
    Easing
} from 'react-native-reanimated';
import {
    SpatialNavigationNode,
    DefaultFocus,
    SpatialNavigationNodeRef,
} from 'react-tv-space-navigation';
import { useNavigation, useNavigationState, useIsFocused } from '@react-navigation/native';
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
    const isFocused = useIsFocused();
    const { isExpanded, setExpanded } = useMenu();
    const navigation = useNavigation<any>();

    // Timeout ref for debouncing the collapse
    const collapseTimeout = useRef<NodeJS.Timeout | null>(null);

    const currentRouteName = useNavigationState(state => {
        if (!state) return 'Home';
        let route: any = state.routes[state.index];
        while (route?.state && typeof route.state.index === 'number') {
            route = route.state.routes[route.state.index];
        }
        return route?.name || 'Home';
    });

    // Also capture the top-level route name (useful for child-detail pages)
    const topRouteName = useNavigationState(state => {
        if (!state) return 'Home';
        return state.routes[state.index]?.name || 'Home';
    });

    // Refs to each menu item so we can set focus programmatically
    const menuItemRefs = useRef<Record<string, SpatialNavigationNodeRef | null>>({});

    useEffect(() => {
        console.log('[SideBar] Active screen changed to:', currentRouteName, 'top:', topRouteName);

        // When navigating, ensure the sidebar highlights the relevant top-level menu item
        const menuIds = MENU_ITEMS.map((m) => m.id);
        let targetMenu: string | null = null;

        if (menuIds.includes(topRouteName as any)) {
            targetMenu = topRouteName;
        } else if (menuIds.includes(currentRouteName as any)) {
            targetMenu = currentRouteName;
        }

        if (targetMenu && menuItemRefs.current[targetMenu]) {
            // Delay briefly to allow the tree to render before focusing
            setTimeout(() => {
                menuItemRefs.current[targetMenu as string]?.focus();
            }, 120);
        }
    }, [currentRouteName, topRouteName]);

    // Width Animation
    const animatedWidth = useSharedValue(isExpanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED);

    useEffect(() => {
        animatedWidth.value = withTiming(
            isExpanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED,
            { duration: 300, easing: Easing.inOut(Easing.ease) }
        );
    }, [isExpanded]);

    const animatedStyle = useAnimatedStyle(() => {
        return {
            width: animatedWidth.value,
        };
    });

    // Logo Animation values
    const logoScale = useSharedValue(1);
    const logoOpacity = useSharedValue(1);

    useEffect(() => {
        if (isExpanded) {
            // Pulse effect when expanded
            logoScale.value = withRepeat(
                withSequence(
                    withTiming(1.05, { duration: 1500, easing: Easing.inOut(Easing.ease) }),
                    withTiming(1, { duration: 1500, easing: Easing.inOut(Easing.ease) })
                ),
                -1,
                true
            );
            logoOpacity.value = withRepeat(
                withSequence(
                    withTiming(0.8, { duration: 1500, easing: Easing.inOut(Easing.ease) }),
                    withTiming(1, { duration: 1500, easing: Easing.inOut(Easing.ease) })
                ),
                -1,
                true
            );
        } else {
            cancelAnimation(logoScale);
            cancelAnimation(logoOpacity);
            logoScale.value = withTiming(1, { duration: 300 });
            logoOpacity.value = withTiming(1, { duration: 300 });
        }
    }, [isExpanded]);

    const logoAnimatedStyle = useAnimatedStyle(() => {
        return {
            transform: [{ scale: logoScale.value }],
            opacity: logoOpacity.value,
        };
    });

    const handleFocus = useCallback(() => {
        if (collapseTimeout.current) {
            clearTimeout(collapseTimeout.current);
            collapseTimeout.current = null;
        }
        setExpanded(true);
    }, [setExpanded]);

    const handleBlur = useCallback(() => {
        if (collapseTimeout.current) {
            clearTimeout(collapseTimeout.current);
        }
        collapseTimeout.current = setTimeout(() => {
            setExpanded(false);
        }, 100);
    }, [setExpanded]);

    return (
        <SpatialNavigationNode
            orientation="vertical"
            isFocusable={false}
        >
            <Animated.View style={[styles.container, animatedStyle]}>
                <View style={styles.logoContainer}>
                    <Animated.Image
                        source={require('../../assets/images/logo.png')}
                        style={[{ width: scaledPixels(60), height: scaledPixels(60) }, logoAnimatedStyle]}
                    />
                    {isExpanded && (
                        <Text numberOfLines={1} style={[styles.logoText, { width: scaledPixels(200) }]}>
                            M3U TV
                        </Text>
                    )}
                </View>

                <View style={styles.menuContainer}>
                    {MENU_ITEMS.map((item, index) => (
                        <FocusablePressable
                            ref={(r) => (menuItemRefs.current[item.id] = r)}
                            key={item.id}
                            onFocus={() => {
                                console.log(`[SideBar] Item focused: ${item.id}`);
                                handleFocus();
                            }}
                            onBlur={() => {
                                handleBlur();
                            }}
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
                                        <Text
                                            numberOfLines={1}
                                            style={[
                                                styles.menuLabel,
                                                {
                                                    color: isFocused ? colors.text : (currentRouteName === item.id ? colors.primary : colors.textSecondary),
                                                    width: scaledPixels(200)
                                                }
                                            ]}
                                        >
                                            {item.label}
                                        </Text>
                                    )}
                                </>
                            )}
                        </FocusablePressable>
                    ))}
                </View>
            </Animated.View>
        </SpatialNavigationNode>
    );
};

const styles = StyleSheet.create({
    container: {
        height: '100%',
        backgroundColor: colors.background,
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
