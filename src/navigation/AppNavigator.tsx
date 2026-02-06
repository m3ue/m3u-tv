import React from 'react';
import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
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
import { RootStackParamList, DrawerParamList } from './types';

const RootStack = createNativeStackNavigator<RootStackParamList>();
const ContentStack = createNativeStackNavigator<DrawerParamList>();

function ContentNavigator() {
  return (
    <ContentStack.Navigator
      screenOptions={{
        headerShown: false,
        contentStyle: { backgroundColor: colors.background },
      }}
    >
      <ContentStack.Screen name="Home" component={HomeScreen} />
      <ContentStack.Screen name="LiveTV" component={LiveTVScreen} />
      <ContentStack.Screen name="EPG" component={EPGScreen} />
      <ContentStack.Screen name="VOD" component={VODScreen} />
      <ContentStack.Screen name="Series" component={SeriesScreen} />
      <ContentStack.Screen name="Settings" component={SettingsScreen} />
    </ContentStack.Navigator>
  );
}

function MainLayout() {
  return (
    <View style={styles.mainContainer}>
      <SideBar />
      <View style={styles.contentContainer}>
        <ContentNavigator />
      </View>
    </View>
  );
}

export function AppNavigator() {
  console.log('AppNavigator: Rendering');
  return (
    <NavigationContainer theme={DarkTheme}>
      <RootStack.Navigator
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.background },
        }}
      >
        <RootStack.Screen name="Main" component={MainLayout} />
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
