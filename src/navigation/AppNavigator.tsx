import React from 'react';
import { NavigationContainer, DarkTheme, Theme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createDrawerNavigator } from '@react-navigation/drawer';
import { View, StyleSheet } from 'react-native';
import { SpatialNavigationNode } from 'react-tv-space-navigation';
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
import { SideBar } from '../components/SideBar';
import { colors } from '../theme';
import { scaledPixels } from '../hooks/useScale';
import { RootStackParamList, DrawerParamList } from './types';
import { navigationRef } from './navigationRef';

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
  return (
    <SpatialNavigationNode orientation="horizontal">
      <View style={styles.mainContainer}>
        <SideBar />
        <SpatialNavigationNode>
          <View style={styles.contentContainer}>
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
        </SpatialNavigationNode>
      </View>
    </SpatialNavigationNode>
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
    flexDirection: 'row',
    backgroundColor: colors.background,
  },
  contentContainer: {
    flex: 1,
    backgroundColor: colors.background,
  },
});
