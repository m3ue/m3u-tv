import mitt from 'mitt';
import type { HWEvent } from 'react-native';
import { SupportedKeys } from './SupportedKeys';
import { RemoteControlManagerInterface } from './RemoteControlManager.interface';

// Map Vega/Kepler HWEvent eventType to SupportedKeys
const EVENT_TYPE_MAPPING: Record<string, SupportedKeys> = {
  left: SupportedKeys.Left,
  right: SupportedKeys.Right,
  down: SupportedKeys.Down,
  up: SupportedKeys.Up,
  select: SupportedKeys.Enter,
  back: SupportedKeys.Back,
  playpause: SupportedKeys.PlayPause,
  skip_backward: SupportedKeys.Rewind,
  skip_forward: SupportedKeys.FastForward,
};

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private tvEventHandler: any;

  constructor() {
    // Initialize TVEventHandler for Vega/Kepler platform
    // Import dynamically to avoid issues with types
    const { TVEventHandler } = require('react-native');
    this.tvEventHandler = new TVEventHandler();
    this.tvEventHandler.enable(this, this.handleHWEvent);
    console.log('[RemoteControlManager.kepler] TVEventHandler enabled');
  }

  private handleHWEvent = (_component: any, event: HWEvent): void => {
    // Only handle KEY_DOWN events (eventKeyAction = 0)
    // eventKeyAction: 0 = KEY_DOWN, 1 = KEY_UP, -1 = default
    if (event.eventKeyAction === 0 || event.eventKeyAction === undefined) {
      const mappedKey = EVENT_TYPE_MAPPING[event.eventType];
      if (mappedKey) {
        console.log(`[Kepler] Key pressed: ${mappedKey} (eventType: ${event.eventType})`);
        this.eventEmitter.emit('keyDown', mappedKey);
      }
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    this.eventEmitter.on('keyDown', listener);
    console.log('[RemoteControlManager.kepler] Key listener added');
    return listener;
  };

  removeKeydownListener = (listener: (event: SupportedKeys) => void): void => {
    this.eventEmitter.off('keyDown', listener);
    console.log('[RemoteControlManager.kepler] Key listener removed');
  };

  emitKeyDown = (key: SupportedKeys): void => {
    this.eventEmitter.emit('keyDown', key);
  };

  cleanup = (): void => {
    this.tvEventHandler.disable();
    console.log('[RemoteControlManager.kepler] TVEventHandler disabled');
  };
}

// Ensure the manager is a global singleton so it survives Fast Refresh and
// we don't lose native listener state when modules are reloaded.
const GLOBAL_KEY = '__keplerRemoteControlManager';
const _global = global as any;
let keplerRemoteControlManager: RemoteControlManager;
if (_global[GLOBAL_KEY]) {
  keplerRemoteControlManager = _global[GLOBAL_KEY];
  console.log('[RemoteControlManager.kepler] Reusing existing global RemoteControlManager instance');
} else {
  keplerRemoteControlManager = new RemoteControlManager();
  _global[GLOBAL_KEY] = keplerRemoteControlManager;
  console.log('[RemoteControlManager.kepler] Created new global RemoteControlManager instance');
}

// On HMR dispose, don't destroy the global singleton (preserve native hooks for the
// running app). Log for visibility.
if ((module as any).hot) {
  (module as any).hot.dispose(() => {
    try {
      console.log('[RemoteControlManager.kepler] HMR dispose - leaving singleton intact');
    } catch (err) {
      console.error('[RemoteControlManager.kepler] HMR dispose handler failed:', err);
    }
  });
}

export default keplerRemoteControlManager;
