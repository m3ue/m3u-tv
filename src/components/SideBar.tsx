import React, { useEffect, useRef, useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import Animated, {
    useSharedValue,
    useAnimatedStyle,
    withRepeat,
    withSequence,
    withTiming,
    cancelAnimation,
    Easing,
} from 'react-native-reanimated';
import { useNavigationState } from '@react-navigation/native';
import { Icon, IconName } from './Icon';
import { colors } from '../theme/colors';
import { scaledPixels } from '../hooks/useScale';
import { useMenu } from '../context/MenuContext';
import { DrawerParamList } from '../navigation/types';
import { FocusablePressable, FocusablePressableRef } from './FocusablePressable';
import { navigationRef } from '../navigation/navigationRef';
import { BlurView } from 'expo-blur';

const SIDEBAR_WIDTH_COLLAPSED = scaledPixels(100);
const SIDEBAR_WIDTH_EXPANDED = scaledPixels(300);

// Export these for use in screens
export { SIDEBAR_WIDTH_COLLAPSED, SIDEBAR_WIDTH_EXPANDED };

interface SideBarProps {
    contentFocusTag?: number;
}

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

export const SideBar = ({ contentFocusTag }: SideBarProps) => {
    const { isExpanded, setExpanded, isSidebarActive, setSidebarActive, setSidebarFocusTag } = useMenu();
    const [preferredMenuId, setPreferredMenuId] = useState<string>('Home');
    const [focusRequestId, setFocusRequestId] = useState<string | null>(null);

    const currentRouteName = useNavigationState((state) => {
        if (!state) return 'Home';
        let route: any = state.routes[state.index];
        while (route?.state && typeof route.state.index === 'number') {
            route = route.state.routes[route.state.index];
        }
        return route?.name || 'Home';
    });

    // Refs to each menu item so we can set focus programmatically
    const menuItemRefs = useRef<Record<string, FocusablePressableRef | null>>({});

    // Expand/collapse and focus management tied to isSidebarActive
    useEffect(() => {
        if (isSidebarActive) {
            setExpanded(true);
            const targetMenu = preferredMenuId;
            if (targetMenu) {
                setFocusRequestId(targetMenu);
                const tag = menuItemRefs.current[targetMenu]?.getNodeHandle();
                if (typeof tag === 'number') {
                    setSidebarFocusTag(tag);
                }
            }
        } else {
            setExpanded(false);
            setFocusRequestId(null);
        }
    }, [isSidebarActive, setExpanded, preferredMenuId, setSidebarFocusTag]);

    // Keep preferred item in sync with active route while content is active.
    useEffect(() => {
        if (isSidebarActive) return;
        const isTopLevelMenuRoute = MENU_ITEMS.some((item) => item.id === (currentRouteName as keyof DrawerParamList));
        if (isTopLevelMenuRoute && preferredMenuId !== currentRouteName) {
            setPreferredMenuId(currentRouteName);
        }
    }, [currentRouteName, isSidebarActive, preferredMenuId]);

    // Publish a stable sidebar focus target tag even before sidebar is activated,
    // so content `nextFocusLeft` links can always resolve to a valid sidebar item.
    useEffect(() => {
        const id = setTimeout(() => {
            const preferredTag = menuItemRefs.current[preferredMenuId]?.getNodeHandle();
            const fallbackTag = menuItemRefs.current['Home']?.getNodeHandle();
            const tag = preferredTag ?? fallbackTag;
            if (typeof tag === 'number') {
                setSidebarFocusTag(tag);
            }
        }, 0);

        return () => clearTimeout(id);
    }, [preferredMenuId, isExpanded, setSidebarFocusTag]);

    // Width Animation
    const animatedWidth = useSharedValue(isExpanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED);

    useEffect(() => {
        animatedWidth.value = withTiming(isExpanded ? SIDEBAR_WIDTH_EXPANDED : SIDEBAR_WIDTH_COLLAPSED, {
            duration: 200,
            easing: Easing.inOut(Easing.ease),
        });
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
                    withTiming(1, { duration: 1500, easing: Easing.inOut(Easing.ease) }),
                ),
                -1,
                true,
            );
            logoOpacity.value = withRepeat(
                withSequence(
                    withTiming(0.8, { duration: 1500, easing: Easing.inOut(Easing.ease) }),
                    withTiming(1, { duration: 1500, easing: Easing.inOut(Easing.ease) }),
                ),
                -1,
                true,
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

    return (
        <Animated.View style={[styles.container, animatedStyle]}>
            <View style={styles.navContainer}>
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
                    {MENU_ITEMS.map((item) => (
                        <FocusablePressable
                            ref={(r) => {
                                menuItemRefs.current[item.id] = r;
                            }}
                            key={item.id}
                            preferredFocus={isSidebarActive && focusRequestId === item.id}
                            nextFocusRight={contentFocusTag}
                            onSelect={() => {
                                console.log(`[SideBar] onSelect triggered for: ${item.id}`);
                                if (navigationRef.isReady()) {
                                    // @ts-ignore
                                    navigationRef.navigate('Main', { screen: item.id });
                                    setPreferredMenuId(item.id);
                                    setSidebarActive(false);
                                    setExpanded(false);
                                }
                            }}
                            onFocus={() => {
                                setFocusRequestId(null);
                                if (!isSidebarActive) {
                                    setSidebarActive(true);
                                }
                                setPreferredMenuId(item.id);
                                const tag = menuItemRefs.current[item.id]?.getNodeHandle();
                                if (typeof tag === 'number') {
                                    setSidebarFocusTag(tag);
                                }
                            }}
                            style={({ isFocused }) => [
                                styles.menuItem,
                                isFocused && styles.menuItemFocused,
                                currentRouteName === item.id && !isFocused && styles.menuItemActive,
                            ]}
                        >
                            {({ isFocused }) => (
                                <>
                                    <Icon
                                        name={item.icon}
                                        size={scaledPixels(32)}
                                        color={
                                            isFocused ? colors.text : currentRouteName === item.id ? colors.primary : colors.textSecondary
                                        }
                                    />
                                    {isExpanded && (
                                        <Text
                                            numberOfLines={1}
                                            style={[
                                                styles.menuLabel,
                                                {
                                                    color: isFocused
                                                        ? colors.text
                                                        : currentRouteName === item.id
                                                            ? colors.primary
                                                            : colors.textSecondary,
                                                    width: scaledPixels(200),
                                                },
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
            </View>

            <BlurView intensity={30} experimentalBlurMethod={'dimezisBlurView'} style={StyleSheet.absoluteFill} />
        </Animated.View>
    );
};

const styles = StyleSheet.create({
    container: {
        position: 'absolute',
        left: 0,
        top: 0,
        bottom: 0,
        height: '100%',
        backgroundColor: 'transparent',
        overflow: 'hidden',
        zIndex: 100,
        elevation: 100,
    },
    navContainer: {
        flex: 1,
        backgroundColor: colors.scrimMedium,
        position: 'relative',
        paddingVertical: scaledPixels(40),
        zIndex: 1
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
