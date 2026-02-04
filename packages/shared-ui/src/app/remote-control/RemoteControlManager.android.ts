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

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private currentListener: ((event: SupportedKeys) => void) | null = null;

  constructor() {
    KeyEvent.onKeyDownListener(this.handleKeyDown);
  }

  private handleKeyDown = (keyEvent: { keyCode: number }): void => {
    // Log ALL incoming key codes to debug what the remote is sending
    console.log(`[Android Remote] Raw keyCode received: ${keyEvent.keyCode}`);

    const mappedKey = KEY_CODE_MAPPING[keyEvent.keyCode];
    if (mappedKey) {
      console.log(`[Android Remote] Mapped to: ${mappedKey}`);
      this.eventEmitter.emit('keyDown', mappedKey);
    } else {
      console.log(`[Android Remote] No mapping found for keyCode: ${keyEvent.keyCode}`);
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    // Remove any existing listener first to ensure only one is active
    if (this.currentListener) {
      this.eventEmitter.off('keyDown', this.currentListener);
    }
    this.currentListener = listener;
    this.eventEmitter.on('keyDown', listener);
    return listener;
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    this.eventEmitter.off('keyDown', listener);
    if (this.currentListener === listener) {
      this.currentListener = null;
    }
  };

  emitKeyDown = (key: SupportedKeys): void => {
    this.eventEmitter.emit('keyDown', key);
  };

  cleanup = (): void => {
    KeyEvent.removeKeyDownListener();
  };
}

export default new RemoteControlManager();