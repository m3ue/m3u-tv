import mitt from 'mitt';
import KeyEvent from 'react-native-keyevent';
import { SupportedKeys } from './SupportedKeys';
import { RemoteControlManagerInterface } from './RemoteControlManager.interface';

const KEY_CODE_MAPPING: Record<number, SupportedKeys> = {
  21: SupportedKeys.Left,
  22: SupportedKeys.Right,
  20: SupportedKeys.Down,
  19: SupportedKeys.Up,
  66: SupportedKeys.Enter,   // KEYCODE_ENTER
  23: SupportedKeys.Enter,   // KEYCODE_DPAD_CENTER
  96: SupportedKeys.Enter,   // KEYCODE_NUMPAD_ENTER
  160: SupportedKeys.Enter,  // KEYCODE_BUTTON_A (gamepad)
  67: SupportedKeys.Back,
  4: SupportedKeys.Back,     // KEYCODE_BACK
  85: SupportedKeys.PlayPause,
  89: SupportedKeys.Rewind,
  90: SupportedKeys.FastForward,
};

// Track if we've already set up the KeyEvent listener to prevent duplicate listeners on hot reload
let isInitialized = false;

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private listeners = new Set<(event: SupportedKeys) => void>();
  // Map original listeners to safe wrapped listeners so we can remove the wrapper later
  private listenerWrappers = new Map<(event: SupportedKeys) => void, (event: SupportedKeys) => void>();

  constructor() {
    this.initialize();
  }

  private initialize(): void {
    // Prevent duplicate KeyEvent listeners on hot reload
    if (isInitialized) {
      console.log('[Android Remote] Already initialized, skipping KeyEvent setup');
      return;
    }
    isInitialized = true;
    KeyEvent.onKeyDownListener(this.handleKeyDown);
    console.log('[Android Remote] KeyEvent initialized');
  }

  private handleKeyDown = (keyEvent: { keyCode: number }): void => {
    const mappedKey = KEY_CODE_MAPPING[keyEvent.keyCode];
    if (mappedKey) {
      console.log(`[Android Remote] Key: ${mappedKey}, listeners: ${this.listeners.size}`);
      try {
        this.eventEmitter.emit('keyDown', mappedKey);
      } catch (err) {
        // Defensive: log any unexpected error during emit so one bad listener can't break
        console.error('[Android Remote] Error during emit:', err);
      }
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    // Support multiple listeners - don't remove existing ones
    if (this.listeners.has(listener)) {
      console.log('[Android Remote] Listener already registered, skipping');
      return listener;
    }

    // Wrap the listener so any thrown error is caught and logged, preventing it from
    // interrupting the event loop and other listeners.
    const wrapped = (event: SupportedKeys) => {
      try {
        listener(event);
      } catch (err) {
        console.error('[Android Remote] Listener threw error:', err);
      }
    };

    this.listenerWrappers.set(listener, wrapped);
    this.listeners.add(listener);
    this.eventEmitter.on('keyDown', wrapped);
    console.log(`[Android Remote] Listener added, total: ${this.listeners.size}`);
    return listener;
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    const wrapped = this.listenerWrappers.get(listener);
    if (wrapped) {
      this.eventEmitter.off('keyDown', wrapped);
      this.listenerWrappers.delete(listener);
    } else {
      // Fallback: try to remove the original listener in case it was registered directly
      this.eventEmitter.off('keyDown', listener);
    }

    this.listeners.delete(listener);
    console.log(`[Android Remote] Listener removed, total: ${this.listeners.size}`);
  };

  emitKeyDown = (key: SupportedKeys): void => {
    this.eventEmitter.emit('keyDown', key);
  };

  cleanup = (): void => {
    KeyEvent.removeKeyDownListener();
    this.listeners.clear();
    this.eventEmitter.all.clear();
    isInitialized = false;
  };
}

export default new RemoteControlManager();