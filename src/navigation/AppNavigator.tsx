import React, { useEffect, useCallback } from 'react';
import { NavigationContainer, DarkTheme, Theme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { View, StyleSheet, BackHandler } from 'react-native';
import { SpatialNavigationRoot, DefaultFocus } from 'react-tv-space-navigation';
import { useIsFocused } from '@react-navigation/native';
import {
  HomeScreen,
  SettingsScreen,
  LiveTVScreen,
  EPGScreen,
  VODScreen,
  SeriesScreen,
  PlayerScreen,
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

  // When sidebar root hits right edge → switch focus to content
  const handleSidebarBoundary = useCallback((direction: string) => {
    if (direction === 'right') {
      setSidebarActive(false);
    }
  }, [setSidebarActive]);

  // When content root hits left edge → switch focus to sidebar
  const handleContentBoundary = useCallback((direction: string) => {
    if (direction === 'left') {
      setSidebarActive(true);
    }
  }, [setSidebarActive]);

  return (
    <View style={styles.mainContainer}>
      {/* Content area - full width with left margin for collapsed sidebar */}
      <View style={styles.contentContainer}>
        <SpatialNavigationRoot
          isActive={isFocused && !isSidebarActive}
          onDirectionHandledWithoutMovement={handleContentBoundary}
        >
          <DefaultFocus>
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
          </DefaultFocus>
        </SpatialNavigationRoot>
      </View>

      {/* Sidebar - absolutely positioned, overlays content when expanded */}
      <SpatialNavigationRoot
        isActive={isFocused && isSidebarActive}
        onDirectionHandledWithoutMovement={handleSidebarBoundary}
      >
        <SideBar />
      </SpatialNavigationRoot>
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
});
