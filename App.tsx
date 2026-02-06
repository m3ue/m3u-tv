import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { SpatialNavigationRoot } from 'react-tv-space-navigation';
import { XtreamProvider } from './src/context/XtreamContext';
import { MenuProvider } from './src/context/MenuContext';
import { AppNavigator } from './src/navigation/AppNavigator';

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <XtreamProvider>
          <MenuProvider>
            <SpatialNavigationRoot>
              <StatusBar style="light" />
              <AppNavigator />
            </SpatialNavigationRoot>
          </MenuProvider>
        </XtreamProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
