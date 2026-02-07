import { StatusBar } from 'expo-status-bar';
import React, { useEffect } from 'react';
import { View, Text, TVEventHandler, LogBox } from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import {
  SpatialNavigationRoot,
  SpatialNavigation,
  SpatialNavigationNode,
  SpatialNavigationFocusableView,
  DefaultFocus,
  Directions
} from 'react-tv-space-navigation';
import { XtreamProvider } from './src/context/XtreamContext';
import { MenuProvider } from './src/context/MenuContext';
import { AppNavigator } from './src/navigation/AppNavigator';

LogBox.ignoreLogs(['Persistent storage is not supported on tvOS']);

export default function App() {
  useEffect(() => {
    console.log('[App] Configuring Remote Control');

    try {
      SpatialNavigation.configureRemoteControl({
        remoteControlSubscriber: (callback) => {
          console.log('[App] Subscriber called. TVEventHandler type:', typeof TVEventHandler);

          let subscription: any = null;
          try {
            // In RN TVOS 0.81, TVEventHandler is a singleton with an addListener method
            const TVHandler: any = TVEventHandler;

            if (TVHandler && typeof TVHandler.addListener === 'function') {
              console.log('[App] Using TVEventHandler.addListener');
              subscription = TVHandler.addListener((event: any) => {
                console.log('[App] TV Event:', event?.eventType);
                if (!event || !event.eventType) return;

                const mapping: Record<string, Directions> = {
                  up: Directions.UP,
                  down: Directions.DOWN,
                  left: Directions.LEFT,
                  right: Directions.RIGHT,
                  select: Directions.ENTER,
                  enter: Directions.ENTER,
                };

                const direction = mapping[event.eventType];
                if (direction) {
                  callback(direction);
                }
              });
            } else if (typeof TVHandler === 'function') {
              // Fallback for older class-based TVEventHandler
              console.log('[App] Instantiating class-based TVHandler');
              const instance = new TVHandler();
              instance.enable(null, (_: any, event: any) => {
                if (!event || !event.eventType) return;
                const mapping: Record<string, Directions> = {
                  up: Directions.UP,
                  down: Directions.DOWN,
                  left: Directions.LEFT,
                  right: Directions.RIGHT,
                  select: Directions.ENTER,
                  enter: Directions.ENTER,
                };
                const direction = mapping[event.eventType];
                if (direction) callback(direction);
              });
              subscription = instance;
            } else {
              console.error('[App] TVEventHandler utility not found. type:', typeof TVHandler, 'Value:', TVHandler);
            }
          } catch (e) {
            console.error('[App] Failed to init TVEventHandler:', e);
          }

          return subscription;
        },
        remoteControlUnsubscriber: (subscription: any) => {
          console.log('[App] Unsubscribing Remote Control');
          if (subscription) {
            if (typeof subscription.remove === 'function') {
              subscription.remove();
            } else if (typeof subscription.disable === 'function') {
              subscription.disable();
            }
          }
        },
      });
      console.log('[App] Remote Control Configured');
    } catch (e) {
      console.error('[App] Failed to configure remote control:', e);
    }
  }, []);

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
