import { Directions, SpatialNavigation } from 'react-tv-space-navigation';
import { SupportedKeys } from './remote-control/SupportedKeys';
import RemoteControlManager from './remote-control/RemoteControlManager';

// Prevent duplicate configuration across hot reloads by storing the flag on the global object
const GLOBAL_KEY = '__spatialRemoteConfigured';
const _global = global as any;
let isConfigured = _global[GLOBAL_KEY] ?? false;

if (!isConfigured) {
  isConfigured = true;
  _global[GLOBAL_KEY] = true;
  console.log('[ConfigureRemoteControl] Configuring spatial navigation remote control');

  SpatialNavigation.configureRemoteControl({
    remoteControlSubscriber: (callback) => {
      console.log('[ConfigureRemoteControl] Setting up remote control subscriber');

      const mapping: { [key in SupportedKeys]?: Directions | null } = {
        [SupportedKeys.Right]: Directions.RIGHT,
        [SupportedKeys.Left]: Directions.LEFT,
        [SupportedKeys.Up]: Directions.UP,
        [SupportedKeys.Down]: Directions.DOWN,
        [SupportedKeys.Enter]: Directions.ENTER,
        [SupportedKeys.Back]: null,
        [SupportedKeys.PlayPause]: null,
        [SupportedKeys.Rewind]: null,
        [SupportedKeys.FastForward]: null,
      };

      const remoteControlListener = (keyEvent: SupportedKeys) => {
        const direction = mapping[keyEvent];
        try {
          // Only forward non-null directions to SpatialNavigation. Mapping values may be
          // `null` for keys we intentionally ignore (e.g., Back, PlayPause). Calling the
          // callback with `null` can lead to exceptions inside SpatialNavigation and stop
          // future input handling, so guard against that here.
          if (direction !== undefined && direction !== null) {
            callback(direction);
          }
        } catch (err) {
          // Log and swallow errors to avoid breaking the remote control subscription
          console.error('[ConfigureRemoteControl] Error delivering remote control event:', err);
        }
      };

      return RemoteControlManager.addKeydownListener(remoteControlListener);
    },

    remoteControlUnsubscriber: (remoteControlListener) => {
      console.log('[ConfigureRemoteControl] Unsubscribing remote control listener');
      RemoteControlManager.removeKeydownListener(remoteControlListener);
    },
  });
} else {
  console.log('[ConfigureRemoteControl] Already configured, skipping');
}
