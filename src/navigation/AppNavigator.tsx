import React, { useEffect, useRef, useState } from 'react';
import { NavigationContainer, DarkTheme, Theme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { View, StyleSheet, BackHandler, TVFocusGuideView, findNodeHandle } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import {
  HomeScreen,
  SettingsScreen,
  LiveTVScreen,
  EPGScreen,
  VODScreen,
  SeriesScreen,
  PlayerScreen,
  PlayerScreenNew,
  MovieDetailsScreen,
  SeriesDetailsScreen,
} from '../screens';
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

  useEffect(() => {
    const id = setTimeout(() => {
      const tag = findNodeHandle(contentFocusRef.current);
      if (typeof tag === 'number') {
        setContentFocusTag(tag);
      }
    }, 0);
    return () => clearTimeout(id);
  }, []);

  // Back button: focus sidebar instead of exiting when on a top-level screen
  useEffect(() => {
    const backHandler = BackHandler.addEventListener('hardwareBackPress', () => {
      if (isFocused && !isSidebarActive) {
        setSidebarActive(true);
        return true; // prevent default (exit app)
      }
      return false; // allow default behavior
    });
    return () => backHandler.remove();
  }, [isFocused, isSidebarActive, setSidebarActive]);

  return (
    <View style={styles.mainContainer}>
      {/* Content area - full width with left margin for collapsed sidebar */}
      <View style={styles.contentContainer}>
        <TVFocusGuideView style={styles.fill} autoFocus>
          <View
            ref={contentFocusRef}
            collapsable={false}
            style={styles.fill}
            pointerEvents={isFocused && !isSidebarActive ? 'auto' : 'none'}
          >
            <MainStack.Navigator
              screenOptions={{
                headerShown: false,
                headerTransparent: true,
                animation: 'none',
                contentStyle: { backgroundColor: colors.background },
              }}
            >
              <MainStack.Screen name="Home" component={HomeScreen} />
              <MainStack.Screen name="LiveTV" component={LiveTVScreen} />
              <MainStack.Screen name="EPG" component={EPGScreen} />
              <MainStack.Screen name="VOD" component={VODScreen} />
              <MainStack.Screen name="Series" component={SeriesScreen} />
              <MainStack.Screen name="Settings" component={SettingsScreen} />
            </MainStack.Navigator>
          </View>
        </TVFocusGuideView>
      </View>

      {/* Sidebar - absolutely positioned, overlays content when expanded */}
      <View pointerEvents={isFocused && isSidebarActive ? 'auto' : 'none'}>
        <SideBar contentFocusTag={contentFocusTag} />
      </View>
    </View>
  );
}

export function AppNavigator() {
  console.log('AppNavigator: Rendering');
  return (
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
          component={PlayerScreenNew}
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
      </RootStack.Navigator>
    </NavigationContainer>
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
});
