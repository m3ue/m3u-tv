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
  longSelect: SupportedKeys.Enter,  // Long press on center button
  playPause: SupportedKeys.PlayPause,
  menu: SupportedKeys.Back,
  swipeLeft: SupportedKeys.Left,
  swipeRight: SupportedKeys.Right,
  swipeUp: SupportedKeys.Up,
  swipeDown: SupportedKeys.Down
};

class RemoteControlManager implements RemoteControlManagerInterface {
  private eventEmitter = mitt<{ keyDown: SupportedKeys }>();
  private tvEventSubscription: EventSubscription;
  private currentListener: ((event: SupportedKeys) => void) | null = null;

  constructor() {
    this.tvEventSubscription = TVEventHandler.addListener(this.handleKeyDown);
  }

  private handleKeyDown = (evt: HWEvent): void => {
    if (!evt) return;

    const eventKeyAction = (evt as any).eventKeyAction;

    // Log ALL incoming events to debug what the remote is sending
    console.log(`[iOS Remote] Raw event received: eventType="${evt.eventType}", eventKeyAction=${eventKeyAction}`);

    // Only process keyUp events (eventKeyAction=1) for more reliable detection
    // Some events like directional presses fire both keyDown (0) and keyUp (1)
    // For select/enter, we only want to trigger once per press
    if (eventKeyAction !== undefined && eventKeyAction !== 1) {
      console.log(`[iOS Remote] Skipping keyDown event (action=${eventKeyAction}), waiting for keyUp`);
      return;
    }

    const mappedKey = KEY_MAPPING[evt.eventType];
    if (mappedKey) {
      console.log(`[iOS Remote] Mapped to: ${mappedKey}, emitting event`);
      this.eventEmitter.emit('keyDown', mappedKey);
    } else {
      console.log(`[iOS Remote] No mapping found for eventType: "${evt.eventType}"`);
    }
  };

  addKeydownListener = (listener: (event: SupportedKeys) => void): ((event: SupportedKeys) => void) => {
    console.log(`[iOS Remote] addKeydownListener called, had existing: ${!!this.currentListener}`);
    // Remove any existing listener first to ensure only one is active
    if (this.currentListener) {
      this.eventEmitter.off('keyDown', this.currentListener);
    }
    this.currentListener = listener;
    this.eventEmitter.on('keyDown', listener);
    console.log(`[iOS Remote] Listener registered successfully`);
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
    this.tvEventSubscription.remove();
  };
}

export default new RemoteControlManager();