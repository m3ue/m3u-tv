import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { LogBox } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { XtreamProvider } from './src/context/XtreamContext';
import { MenuProvider } from './src/context/MenuContext';
import { AppNavigator } from './src/navigation/AppNavigator';

LogBox.ignoreLogs(['Persistent storage is not supported on tvOS']);

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <XtreamProvider>
          <MenuProvider>
            <StatusBar style="light" />
            <AppNavigator />
          </MenuProvider>
        </XtreamProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
