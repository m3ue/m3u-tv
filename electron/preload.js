const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  platform: process.platform,
  isElectron: true,

  // Title-bar metrics for the custom drag region (height, side insets for native
  // window controls, etc). Resolves once from the main process.
  getTitleBarInfo: () => ipcRenderer.invoke('titleBar:getInfo'),

  // Open a stream in an independent floating mpv window (preferred path)
  openFloating: (streamUrl, options) => ipcRenderer.invoke('mpv:open-floating', streamUrl, options),

  // Legacy external player API (fallback when embedded mpv unavailable)
  openExternal: (url, startPosition) => ipcRenderer.invoke('open-external', url, startPosition || 0),
  onExternalPlayerClosed: (callback) => {
    ipcRenderer.on('external-player-closed', () => callback());
    return () => ipcRenderer.removeAllListeners('external-player-closed');
  },

  // Native OS dialog — returns a Promise<number> (index of the clicked button).
  showMessageBox: (options) => ipcRenderer.invoke('dialog:showMessageBox', options),

  // Embedded mpv player API
  mpv: {
    start: (streamUrl, options) => ipcRenderer.invoke('mpv:start', streamUrl, options),
    togglePause: () => ipcRenderer.invoke('mpv:togglePause'),
    seek: (seconds) => ipcRenderer.invoke('mpv:seek', seconds),
    seekTo: (seconds) => ipcRenderer.invoke('mpv:seekTo', seconds),
    setAudioTrack: (id) => ipcRenderer.invoke('mpv:setAudioTrack', id),
    setSubtitleTrack: (id) => ipcRenderer.invoke('mpv:setSubtitleTrack', id),
    stop: () => ipcRenderer.invoke('mpv:stop'),

    // Event subscriptions — each returns an unsubscribe function
    onProgress: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:progress', handler);
      return () => ipcRenderer.removeListener('mpv:progress', handler);
    },
    onPause: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:pause', handler);
      return () => ipcRenderer.removeListener('mpv:pause', handler);
    },
    onTracks: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:tracks', handler);
      return () => ipcRenderer.removeListener('mpv:tracks', handler);
    },
    onBuffering: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:buffering', handler);
      return () => ipcRenderer.removeListener('mpv:buffering', handler);
    },
    onEnd: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:end', handler);
      return () => ipcRenderer.removeListener('mpv:end', handler);
    },
    onEmbeddedMode: (callback) => {
      const handler = (_event, data) => callback(data);
      ipcRenderer.on('mpv:embedded-mode', handler);
      return () => ipcRenderer.removeListener('mpv:embedded-mode', handler);
    },
  },
});
