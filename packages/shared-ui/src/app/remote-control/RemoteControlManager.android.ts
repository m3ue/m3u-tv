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
      this.eventEmitter.emit('keyDown', mappedKey);
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    // Support multiple listeners - don't remove existing ones
    if (this.listeners.has(listener)) {
      console.log('[Android Remote] Listener already registered, skipping');
      return listener;
    }
    this.listeners.add(listener);
    this.eventEmitter.on('keyDown', listener);
    console.log(`[Android Remote] Listener added, total: ${this.listeners.size}`);
    return listener;
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    this.eventEmitter.off('keyDown', listener);
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