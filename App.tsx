import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { LogBox } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { XtreamProvider } from './src/context/XtreamContext';
import { MenuProvider } from './src/context/MenuContext';
import { AppNavigator } from './src/navigation/AppNavigator';
import { PhoneNavigator } from './src/navigation/PhoneNavigator';
import { useShouldUseSidebar } from './src/hooks/useDeviceType';
import { useGlobalWebStyles } from './src/hooks/useGlobalWebStyles';
import { ElectronTitleBar } from './src/components/ElectronTitleBar';
import { OfflineBanner } from './src/components/OfflineBanner';

LogBox.ignoreLogs(['Persistent storage is not supported on tvOS']);

export default function App() {
  const useSidebar = useShouldUseSidebar();
  useGlobalWebStyles();

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <XtreamProvider>
          <MenuProvider>
            <StatusBar style="light" />
            {useSidebar ? <AppNavigator /> : <PhoneNavigator />}
            <OfflineBanner />
            {/* Custom drag region for the frameless Electron window. Renders
                nothing on native or non-Electron web. Mounted last so it sits
                above all app UI. */}
            <ElectronTitleBar />
          </MenuProvider>
        </XtreamProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
