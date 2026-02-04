import { useEffect } from 'react';
import { StyleSheet, View, Platform } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { createDrawerNavigator } from '@react-navigation/drawer';
import { useNavigation, DrawerActions } from '@react-navigation/native';
import { useMenuContext } from '../components/MenuContext';
import CustomDrawerContent from '../components/CustomDrawerContent';
import { scaledPixels } from '../hooks/useScale';
import { DrawerParamList } from './types';

// Import screens
import HomeScreen from '../screens/HomeScreen';
import LiveTVScreen from '../screens/LiveTVScreen';
import VODScreen from '../screens/VODScreen';
import SeriesScreen from '../screens/SeriesScreen';
import SettingsScreen from '../screens/SettingsScreen';

const Drawer = createDrawerNavigator<DrawerParamList>();

function DrawerSyncWrapper() {
  const { isOpen: isMenuOpen } = useMenuContext();
  const navigation = useNavigation();

  // Open drawer on mount if menu context says it should be open
  useEffect(() => {
    if (isMenuOpen) {
      navigation.dispatch(DrawerActions.openDrawer());
    }
  }, []);

  return null;
}

export default function DrawerNavigator() {
  const styles = drawerStyles;

  const navigationContent = (
    <>
      <Drawer.Navigator
        drawerContent={CustomDrawerContent}
        initialRouteName="Home"
        defaultStatus="closed"
        screenOptions={{
          headerShown: false,
          drawerActiveBackgroundColor: '#6366f1',
          drawerActiveTintColor: '#ffffff',
          drawerInactiveTintColor: '#94a3b8',
          drawerStyle: styles.drawerStyle,
          drawerLabelStyle: styles.drawerLabelStyle,
          drawerType: 'front',
          swipeEnabled: false,
          animationEnabled: false,
        }}
      >
        <Drawer.Screen
          name="Home"
          component={HomeScreen}
          options={{
            drawerLabel: 'Home',
          }}
        />
        <Drawer.Screen
          name="LiveTV"
          component={LiveTVScreen}
          options={{
            drawerLabel: 'Live TV',
          }}
        />
        <Drawer.Screen
          name="VOD"
          component={VODScreen}
          options={{
            drawerLabel: 'Movies',
          }}
        />
        <Drawer.Screen
          name="Series"
          component={SeriesScreen}
          options={{
            drawerLabel: 'Series',
          }}
        />
        <Drawer.Screen
          name="Settings"
          component={SettingsScreen}
          options={{
            drawerLabel: 'Settings',
          }}
        />
      </Drawer.Navigator>
      <DrawerSyncWrapper />
    </>
  );

  // On TV platforms, don't use GestureHandlerRootView as we use remote control navigation
  if (Platform.isTV) {
    return <View style={{ flex: 1 }}>{navigationContent}</View>;
  }

  // On mobile/web, use GestureHandlerRootView for swipe gestures
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      {navigationContent}
    </GestureHandlerRootView>
  );
}

const drawerStyles = StyleSheet.create({
  drawerStyle: {
    width: scaledPixels(300),
    backgroundColor: '#0f172a',
    paddingTop: scaledPixels(0),
  },
  drawerLabelStyle: {
    fontSize: scaledPixels(18),
    fontWeight: 'bold',
    marginLeft: scaledPixels(10),
  },
});
