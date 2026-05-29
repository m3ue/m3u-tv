import React, { useEffect } from 'react';
import { Platform } from 'react-native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { enableDragScroll } from '../utils/webInteractions';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { NavigationContainer, DarkTheme, Theme } from '@react-navigation/native';
import {
  HomeScreen,
  SettingsScreen,
  LiveTVScreen,
  VODScreen,
  SeriesScreen,
  SearchScreen,
  PlayerScreen,
  MovieDetailsScreen,
  SeriesDetailsScreen,
  ViewerSelectionScreen,
} from '../screens';
import { ViewerProvider } from '../context/ViewerContext';
import { Icon } from '../components/Icon';
import { colors } from '../theme';
import { RootStackParamList, DrawerParamList } from './types';
import { navigationRef } from './navigationRef';

const RootStack = createNativeStackNavigator<RootStackParamList>();
const Tab = createBottomTabNavigator<DrawerParamList>();

const AppTheme: Theme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    background: colors.background,
    card: colors.card,
    border: colors.border,
  },
};

function TabNavigator() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
        tabBarStyle: {
          backgroundColor: colors.card,
          borderTopColor: colors.border,
        },
      }}
    >
      <Tab.Screen
        name="Home"
        component={HomeScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Icon name="Home" size={size} color={color} />,
        }}
      />
      <Tab.Screen
        name="Search"
        component={SearchScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Icon name="Search" size={size} color={color} />,
        }}
      />
      <Tab.Screen
        name="LiveTV"
        component={LiveTVScreen}
        options={{
          title: 'Live TV',
          tabBarIcon: ({ color, size }) => <Icon name="Tv" size={size} color={color} />,
        }}
      />
      <Tab.Screen
        name="VOD"
        component={VODScreen}
        options={{
          title: 'Movies',
          tabBarIcon: ({ color, size }) => <Icon name="Film" size={size} color={color} />,
        }}
      />
      <Tab.Screen
        name="Series"
        component={SeriesScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Icon name="Tv2" size={size} color={color} />,
        }}
      />
      <Tab.Screen
        name="Settings"
        component={SettingsScreen}
        options={{
          tabBarIcon: ({ color, size }) => <Icon name="Settings" size={size} color={color} />,
        }}
      />
    </Tab.Navigator>
  );
}

export function PhoneNavigator() {
  useEffect(() => {
    if (Platform.OS === 'web') return enableDragScroll();
  }, []);

  return (
    <ViewerProvider>
      <NavigationContainer theme={AppTheme} ref={navigationRef}>
        <RootStack.Navigator
          screenOptions={{
            headerShown: false,
            contentStyle: { backgroundColor: colors.background },
          }}
        >
          <RootStack.Screen name="Main" component={TabNavigator} />
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
            options={{ animation: 'slide_from_right' }}
          />
          <RootStack.Screen
            name="SeriesDetails"
            component={SeriesDetailsScreen}
            options={{ animation: 'slide_from_right' }}
          />
          <RootStack.Screen
            name="ViewerSelection"
            component={ViewerSelectionScreen}
            options={{ animation: 'fade', presentation: 'transparentModal' }}
          />
        </RootStack.Navigator>
      </NavigationContainer>
    </ViewerProvider>
  );
}
