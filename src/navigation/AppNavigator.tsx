import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { View, StyleSheet } from 'react-native';
import {
  HomeScreen,
  SettingsScreen,
  LiveTVScreen,
  EPGScreen,
  VODScreen,
  SeriesScreen,
} from '../screens';
import { SideBar } from '../components/SideBar';
import { colors } from '../theme';
import { RootStackParamList } from './types';
import { PlayerScreen } from '../screens/PlayerScreen';
import { MovieDetailsScreen } from '../screens/MovieDetailsScreen';
import { SeriesDetailsScreen } from '../screens/SeriesDetailsScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

function MainLayout() {
  return (
    <View style={styles.mainContainer}>
      <SideBar />
      <View style={styles.contentContainer}>
        <Stack.Navigator
          screenOptions={{
            headerShown: false,
            contentStyle: { backgroundColor: 'transparent' },
          }}
        >
          <Stack.Screen name="Home" component={HomeScreen} />
          <Stack.Screen name="LiveTV" component={LiveTVScreen} />
          <Stack.Screen name="EPG" component={EPGScreen} />
          <Stack.Screen name="VOD" component={VODScreen} />
          <Stack.Screen name="Series" component={SeriesScreen} />
          <Stack.Screen name="Settings" component={SettingsScreen} />
        </Stack.Navigator>
      </View>
    </View>
  );
}

export function AppNavigator() {
  return (
    <NavigationContainer>
      <Stack.Navigator
        screenOptions={{
          headerShown: false,
          contentStyle: { backgroundColor: colors.background },
        }}
      >
        <Stack.Screen name="Main" component={MainLayout} />
        <Stack.Screen
          name="Player"
          component={PlayerScreen}
          options={{
            animation: 'fade',
            presentation: 'fullScreenModal',
          }}
        />
        <Stack.Screen
          name="Details"
          component={MovieDetailsScreen}
          options={{
            animation: 'slide_from_right',
          }}
        />
        <Stack.Screen
          name="SeriesDetails"
          component={SeriesDetailsScreen}
          options={{
            animation: 'slide_from_right',
          }}
        />
      </Stack.Navigator>
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
