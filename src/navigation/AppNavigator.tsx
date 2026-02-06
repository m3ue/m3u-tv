import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { createDrawerNavigator } from '@react-navigation/drawer';
import { View, Text, StyleSheet } from 'react-native';
import {
  HomeScreen,
  SettingsScreen,
  LiveTVScreen,
  EPGScreen,
  VODScreen,
  SeriesScreen,
} from '../screens';
import { colors, spacing, typography } from '../theme';
import { RootStackParamList, DrawerParamList } from './types';

const Stack = createNativeStackNavigator<RootStackParamList>();
const Drawer = createDrawerNavigator<DrawerParamList>();

function CustomDrawerContent() {
  return (
    <View style={styles.drawerContent}>
      <View style={styles.drawerHeader}>
        <Text style={styles.drawerTitle}>M3U TV</Text>
      </View>
    </View>
  );
}

function DrawerNavigator() {
  return (
    <Drawer.Navigator
      screenOptions={{
        headerStyle: {
          backgroundColor: colors.backgroundElevated,
        },
        headerTintColor: colors.text,
        headerTitleStyle: {
          fontWeight: typography.fontWeight.semibold,
          fontSize: typography.fontSize.lg,
        },
        drawerStyle: {
          backgroundColor: colors.background,
          width: 280,
        },
        drawerLabelStyle: {
          color: colors.text,
          fontSize: typography.fontSize.md,
        },
        drawerActiveTintColor: colors.primary,
        drawerInactiveTintColor: colors.textSecondary,
        drawerActiveBackgroundColor: colors.focusBackgroundSecondary,
      }}
      drawerContent={() => <CustomDrawerContent />}
    >
      <Drawer.Screen name="Home" component={HomeScreen} options={{ title: 'Home' }} />
      <Drawer.Screen name="LiveTV" component={LiveTVScreen} options={{ title: 'Live TV' }} />
      <Drawer.Screen name="EPG" component={EPGScreen} options={{ title: 'TV Guide' }} />
      <Drawer.Screen name="VOD" component={VODScreen} options={{ title: 'Movies' }} />
      <Drawer.Screen name="Series" component={SeriesScreen} options={{ title: 'TV Series' }} />
      <Drawer.Screen name="Settings" component={SettingsScreen} options={{ title: 'Settings' }} />
    </Drawer.Navigator>
  );
}

function PlayerScreen() {
  // Placeholder - will be implemented with react-native-video
  return (
    <View style={styles.playerContainer}>
      <Text style={styles.playerText}>Player Screen (TODO: Add video player)</Text>
    </View>
  );
}

function DetailsScreen() {
  // Placeholder - will be implemented for series details
  return (
    <View style={styles.playerContainer}>
      <Text style={styles.playerText}>Details Screen (TODO: Add series/movie details)</Text>
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
        <Stack.Screen name="Main" component={DrawerNavigator} />
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
          component={DetailsScreen}
          options={{
            headerShown: true,
            headerStyle: { backgroundColor: colors.backgroundElevated },
            headerTintColor: colors.text,
          }}
        />
      </Stack.Navigator>
    </NavigationContainer>
  );
}

const styles = StyleSheet.create({
  drawerContent: {
    flex: 1,
    backgroundColor: colors.background,
  },
  drawerHeader: {
    padding: spacing.lg,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  drawerTitle: {
    fontSize: typography.fontSize.xl,
    fontWeight: typography.fontWeight.bold,
    color: colors.primary,
  },
  playerContainer: {
    flex: 1,
    backgroundColor: '#000',
    justifyContent: 'center',
    alignItems: 'center',
  },
  playerText: {
    color: colors.text,
    fontSize: typography.fontSize.lg,
  },
});
