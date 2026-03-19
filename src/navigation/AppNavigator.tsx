import React, { useCallback, useEffect, useRef, useState } from 'react';
import { NavigationContainer, DarkTheme, Theme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { View, StyleSheet, Platform, findNodeHandle, Pressable } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { FocusGuide } from '../components/FocusGuide';
import { useBackHandler } from '../hooks/useBackHandler';
import {
  HomeScreen,
  SearchScreen,
  SettingsScreen,
  LiveTVScreen,
  VODScreen,
  SeriesScreen,
  PlayerScreen,
  MovieDetailsScreen,
  SeriesDetailsScreen,
  ViewerSelectionScreen,
} from '../screens';
import { ViewerProvider } from '../context/ViewerContext';
import { SideBar, SIDEBAR_WIDTH_COLLAPSED } from '../components/SideBar';
import { colors } from '../theme';
import { RootStackParamList, DrawerParamList } from './types';
import { navigationRef } from './navigationRef';
import { useMenu } from '../context/MenuContext';

const RootStack = createNativeStackNavigator<RootStackParamList>();
const MainStack = createNativeStackNavigator<DrawerParamList>();

// Custom theme that uses our app colors to prevent any color mismatches
const AppTheme: Theme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: colors.background,
    card: colors.card,
    border: colors.border,
  },
};

function MainNavigator() {
  const isFocused = useIsFocused();
  const { isSidebarActive, setSidebarActive } = useMenu();
  const contentFocusRef = useRef<View>(null);
  const [contentFocusTag, setContentFocusTag] = useState<number>();
  const wasFocusedRef = useRef(isFocused);
  const [grabFocus, setGrabFocus] = useState(false);

  useEffect(() => {
    if (Platform.OS === 'web') return;
    const id = setTimeout(() => {
      const tag = findNodeHandle(contentFocusRef.current);
      if (typeof tag === 'number') {
        setContentFocusTag(tag);
      }
    }, 0);
    return () => clearTimeout(id);
  }, []);

  const handleSidebarNavigate = useCallback(() => {
    setGrabFocus(true);
  }, []);

  // Reset grabFocus after it's been applied
  useEffect(() => {
    if (grabFocus) {
      const id = setTimeout(() => setGrabFocus(false), 300);
      return () => clearTimeout(id);
    }
  }, [grabFocus]);

  // When returning from a modal (Player, Details), ensure sidebar stays collapsed
  useEffect(() => {
    if (isFocused && !wasFocusedRef.current) {
      setSidebarActive(false);
    }
    wasFocusedRef.current = isFocused;
  }, [isFocused, setSidebarActive]);

  const handleBackPress = useCallback(() => {
    if (isFocused && !isSidebarActive) {
      setSidebarActive(true);
      return true;
    }
    return false;
  }, [isFocused, isSidebarActive, setSidebarActive]);

  useBackHandler(handleBackPress);

  return (
    <View style={styles.mainContainer}>
      {/* Content area - full width with left margin for collapsed sidebar */}
      <View style={styles.contentContainer}>
        <FocusGuide style={styles.fill} autoFocus>
          <View
            ref={contentFocusRef}
            collapsable={false}
            style={styles.fill}
            pointerEvents="auto"
            onFocusCapture={() => {
              if (isSidebarActive) {
                setSidebarActive(false);
              }
            }}
          >
            {grabFocus && (
              <Pressable
                hasTVPreferredFocus
                style={styles.focusAnchor}
                onFocus={() => setGrabFocus(false)}
              />
            )}
            <MainStack.Navigator
              screenOptions={{
                headerShown: false,
                headerTransparent: true,
                animation: 'none',
                contentStyle: { backgroundColor: colors.background },
              }}
            >
              <MainStack.Screen name="Home" component={HomeScreen} />
              <MainStack.Screen name="Search" component={SearchScreen} />
              <MainStack.Screen name="LiveTV" component={LiveTVScreen} />
              <MainStack.Screen name="VOD" component={VODScreen} />
              <MainStack.Screen name="Series" component={SeriesScreen} />
              <MainStack.Screen name="Settings" component={SettingsScreen} />
            </MainStack.Navigator>
          </View>
        </FocusGuide>
      </View>

      {/* Sidebar - absolutely positioned, overlays content when expanded */}
      <View
        style={[styles.sidebarLayer, Platform.OS === 'web' && styles.sidebarLayerWeb]}
        pointerEvents="box-none"
      >
        <FocusGuide style={styles.fill} trapFocusLeft>
          <SideBar contentFocusTag={contentFocusTag} onNavigate={handleSidebarNavigate} />
        </FocusGuide>
      </View>
    </View>
  );
}

export function AppNavigator() {
  return (
    <ViewerProvider>
    <NavigationContainer theme={AppTheme} ref={navigationRef}>
      <RootStack.Navigator
        screenOptions={{
          headerShown: false,
          headerTransparent: true,
          contentStyle: { backgroundColor: colors.background },
        }}
      >
        <RootStack.Screen name="Main" component={MainNavigator} />
        <RootStack.Screen
          name="Player"
          component={PlayerScreen}
          options={{
            animation: 'fade',
            presentation: 'fullScreenModal',
          }}
        />
        <RootStack.Screen
          name="Details"
          component={MovieDetailsScreen}
          options={{
            animation: 'slide_from_right',
          }}
        />
        <RootStack.Screen
          name="SeriesDetails"
          component={SeriesDetailsScreen}
          options={{
            animation: 'slide_from_right',
          }}
        />
        <RootStack.Screen
          name="ViewerSelection"
          component={ViewerSelectionScreen}
          options={{
            animation: 'fade',
            presentation: 'transparentModal',
          }}
        />
      </RootStack.Navigator>
    </NavigationContainer>
    </ViewerProvider>
  );
}

const styles = StyleSheet.create({
  mainContainer: {
    flex: 1,
    backgroundColor: colors.background,
  },
  contentContainer: {
    flex: 1,
    marginLeft: SIDEBAR_WIDTH_COLLAPSED,
    backgroundColor: colors.background,
  },
  fill: {
    flex: 1,
  },
  sidebarLayer: {
    ...StyleSheet.absoluteFillObject,
  },
  sidebarLayerWeb: {
    right: 'auto' as any,
    width: SIDEBAR_WIDTH_COLLAPSED,
    overflow: 'visible' as any,
  },
  focusAnchor: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    opacity: 0,
  },
});
