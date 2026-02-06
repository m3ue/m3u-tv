import React from 'react';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createDrawerNavigator } from '@react-navigation/drawer';
import { View, StyleSheet } from 'react-native';
import { SpatialNavigationNode } from 'react-tv-space-navigation';
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

function MainNavigator() {
  return (
    <SpatialNavigationNode orientation="horizontal">
      <View style={styles.mainContainer}>
        <View style={{ width: undefined }}>
          <SideBar />
        </View>
        <SpatialNavigationNode>
          <View style={styles.contentContainer}>
            <MainStack.Navigator
              screenOptions={{
                headerShown: false,
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
    <NavigationContainer theme={DarkTheme} ref={navigationRef}>
      <RootStack.Navigator
        screenOptions={{
          headerShown: false,
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
  },
});
