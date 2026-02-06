import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { XtreamProvider } from './src/context/XtreamContext';
import { AppNavigator } from './src/navigation/AppNavigator';

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <XtreamProvider>
          <StatusBar style="light" />
          <AppNavigator />
        </XtreamProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
