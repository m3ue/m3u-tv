import mitt from 'mitt';
import { Platform } from 'react-native';
import { SupportedKeys } from './SupportedKeys';
import { RemoteControlManagerInterface } from './RemoteControlManager.interface';

const KEY_MAPPING: Record<string, SupportedKeys> = {
  ArrowRight: SupportedKeys.Right,
  ArrowLeft: SupportedKeys.Left,
  ArrowUp: SupportedKeys.Up,
  ArrowDown: SupportedKeys.Down,
  Enter: SupportedKeys.Enter,
  Backspace: SupportedKeys.Back,
  GoBack: SupportedKeys.Back, // For LG WebOS Magic Remote
};

// Track if we've already set up the event listener to prevent duplicates on hot reload
let isInitialized = false;

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private listeners = new Set<(event: SupportedKeys) => void>();

  constructor() {
    this.initialize();
  }

  private initialize(): void {
    if (Platform.OS === 'web' && !isInitialized) {
      isInitialized = true;
      window.addEventListener('keydown', this.handleKeyDown);
      console.log('[Web Remote] Keyboard event listener initialized');
    }
  }

  private handleKeyDown = (event: KeyboardEvent): void => {
    const mappedKey = KEY_MAPPING[event.code] || KEY_MAPPING[event.key];
    if (mappedKey) {
      this.eventEmitter.emit('keyDown', mappedKey);
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): () => void => {
    // Support multiple listeners - don't remove existing ones
    if (this.listeners.has(listener)) {
      return () => this.removeKeydownListener(listener);
    }
    this.listeners.add(listener);
    this.eventEmitter.on('keyDown', listener);
    console.log(`[Web Remote] Listener added, total: ${this.listeners.size}`);
    return () => this.removeKeydownListener(listener);
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    this.eventEmitter.off('keyDown', listener);
    this.listeners.delete(listener);
    console.log(`[Web Remote] Listener removed, total: ${this.listeners.size}`);
  };

  emitKeyDown = (key: SupportedKeys): void => {
    this.eventEmitter.emit('keyDown', key);
  };

  cleanup = (): void => {
    if (Platform.OS === 'web') {
      window.removeEventListener('keydown', this.handleKeyDown);
    }
    this.listeners.clear();
    this.eventEmitter.all.clear();
    isInitialized = false;
  };
}

export default new RemoteControlManager();
