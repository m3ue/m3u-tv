import mitt from 'mitt';
import { EventSubscription, HWEvent, TVEventHandler } from 'react-native';
import { SupportedKeys } from './SupportedKeys';
import { RemoteControlManagerInterface } from './RemoteControlManager.interface';

const KEY_MAPPING: Record<string, SupportedKeys> = {
  right: SupportedKeys.Right,
  left: SupportedKeys.Left,
  up: SupportedKeys.Up,
  down: SupportedKeys.Down,
  select: SupportedKeys.Enter,
  longSelect: SupportedKeys.Enter, // Long press on center button
  playPause: SupportedKeys.PlayPause,
  menu: SupportedKeys.Back,
  swipeLeft: SupportedKeys.Left,
  swipeRight: SupportedKeys.Right,
  swipeUp: SupportedKeys.Up,
  swipeDown: SupportedKeys.Down,
};

// Track if we've already set up the TVEventHandler to prevent duplicate listeners on hot reload
let isInitialized = false;

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private tvEventSubscription: EventSubscription | null = null;
  private listeners = new Set<(event: SupportedKeys) => void>();

  constructor() {
    this.initialize();
  }

  private initialize(): void {
    // Prevent duplicate TVEventHandler listeners on hot reload
    if (isInitialized) {
      console.log('[iOS Remote] Already initialized, skipping TVEventHandler setup');
      return;
    }
    isInitialized = true;
    this.tvEventSubscription = TVEventHandler.addListener(this.handleKeyDown);
    console.log('[iOS Remote] TVEventHandler initialized');
  }

  private handleKeyDown = (evt: HWEvent): void => {
    if (!evt) return;

    const eventKeyAction = (evt as any).eventKeyAction;

    // Only process keyUp events (eventKeyAction=1) for more reliable detection
    // Some events like directional presses fire both keyDown (0) and keyUp (1)
    // For select/enter, we only want to trigger once per press
    if (eventKeyAction !== undefined && eventKeyAction !== 1) {
      return;
    }

    const mappedKey = KEY_MAPPING[evt.eventType];
    if (mappedKey) {
      console.log(`[iOS Remote] Key: ${mappedKey}, listeners: ${this.listeners.size}`);
      this.eventEmitter.emit('keyDown', mappedKey);
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    // Support multiple listeners - don't remove existing ones
    if (this.listeners.has(listener)) {
      console.log('[iOS Remote] Listener already registered, skipping');
      return listener;
    }
    this.listeners.add(listener);
    this.eventEmitter.on('keyDown', listener);
    console.log(`[iOS Remote] Listener added, total: ${this.listeners.size}`);
    return listener;
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    this.eventEmitter.off('keyDown', listener);
    this.listeners.delete(listener);
    console.log(`[iOS Remote] Listener removed, total: ${this.listeners.size}`);
  };

  emitKeyDown = (key: SupportedKeys): void => {
    this.eventEmitter.emit('keyDown', key);
  };

  cleanup = (): void => {
    if (this.tvEventSubscription) {
      this.tvEventSubscription.remove();
      this.tvEventSubscription = null;
    }
    this.listeners.clear();
    this.eventEmitter.all.clear();
    isInitialized = false;
  };
}

export default new RemoteControlManager();
