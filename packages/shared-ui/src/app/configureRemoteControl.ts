import { Directions, SpatialNavigation } from 'react-tv-space-navigation';
import { SupportedKeys } from './remote-control/SupportedKeys';
import RemoteControlManager from './remote-control/RemoteControlManager';

SpatialNavigation.configureRemoteControl({
  remoteControlSubscriber: (callback) => {
    console.log("[ConfigureRemoteControl] Setting up remote control subscriber");

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
      console.log(`[ConfigureRemoteControl] Received key: ${keyEvent}, mapped direction: ${mapping[keyEvent]}`);
      const direction = mapping[keyEvent];
      if (direction !== undefined) {
        callback(direction);
      }
    };

    return RemoteControlManager.addKeydownListener(remoteControlListener);
  },

  remoteControlUnsubscriber: (remoteControlListener) => {
    console.log("[ConfigureRemoteControl] Unsubscribing remote control listener");
    RemoteControlManager.removeKeydownListener(remoteControlListener);
  },
});
