const { app, BrowserWindow, globalShortcut, protocol, net, session, ipcMain, shell } = require('electron');
const path = require('path');
const url = require('url');
const fs = require('fs');
const { spawn } = require('child_process');
const { MpvController } = require('./mpvController');

// Tell the native libmpv addon where to find libmpv (packaged builds and dev-mode bundles).
// The addon uses dlopen and respects this env var; without it it searches /opt/homebrew/lib.
if (process.platform === 'darwin' && !process.env.M3U_TV_LIBMPV_DYLIB) {
  const arch = process.arch === 'arm64' ? 'arm64' : 'x64';
  for (const candidate of [
    process.resourcesPath && path.join(process.resourcesPath, 'mpv', 'libmpv.2.dylib'),
    path.join(__dirname, '..', 'binaries', 'mac', arch, 'libmpv.2.dylib'),
  ].filter(Boolean)) {
    if (fs.existsSync(candidate)) { process.env.M3U_TV_LIBMPV_DYLIB = candidate; break; }
  }
}

const DIST_DIR = path.join(__dirname, '..', 'dist');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 800,
    minHeight: 600,
    backgroundColor: '#0a0a0f',
    icon: path.join(__dirname, '..', 'logo.png'),
    titleBarStyle: 'default',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      webSecurity: false,
    },
  });

  const isDev = process.env.ELECTRON_DEV === '1';
  if (isDev) {
    mainWindow.loadURL('http://0.0.0.0:8081');
  } else {
    mainWindow.loadURL('app://bundle/index.html');
  }

  // Always open DevTools during testing — remove for production
  mainWindow.webContents.openDevTools();

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// Register the custom scheme as privileged before app is ready
protocol.registerSchemesAsPrivileged([
  {
    scheme: 'app',
    privileges: {
      standard: true,
      secure: true,
      supportFetchAPI: true,
      corsEnabled: true,
    },
  },
]);

app.whenReady().then(() => {
  // Serve dist/ files via custom protocol so absolute paths (/_expo/...) resolve correctly
  protocol.handle('app', (request) => {
    const reqUrl = new URL(request.url);
    const filePath = path.join(DIST_DIR, decodeURIComponent(reqUrl.pathname));
    return net.fetch(url.pathToFileURL(filePath).toString());
  });

  // Set Content-Security-Policy only for our own app:// pages, not external requests
  session.defaultSession.webRequest.onHeadersReceived((details, callback) => {
    if (details.url.startsWith('app://')) {
      callback({
        responseHeaders: {
          ...details.responseHeaders,
          'Content-Security-Policy': ["default-src 'self' app:; script-src 'self' 'unsafe-inline' 'unsafe-eval' app:; style-src 'self' 'unsafe-inline' app:; img-src 'self' app: data: blob: http: https:; media-src * blob:; connect-src * ws: wss:; worker-src 'self' app: blob:;"],
        },
      });
    } else {
      callback({ responseHeaders: details.responseHeaders });
    }
  });

  createWindow();

  // Track the active external player process to prevent duplicates
  let activePlayerProcess = null;

  // Handle request to open a stream URL in an external player (mpv, vlc, or system default)
  ipcMain.handle('open-external', async (_event, streamUrl, startPosition) => {
    // Prevent spawning multiple players
    if (activePlayerProcess) {
      return { success: true, player: 'already-running' };
    }

    // Validate URL to prevent command injection
    try {
      const parsed = new URL(streamUrl);
      if (!['http:', 'https:', 'rtmp:', 'rtsp:'].includes(parsed.protocol)) {
        return { success: false, error: 'Invalid URL protocol' };
      }
    } catch {
      return { success: false, error: 'Invalid URL' };
    }

    // Try mpv first, then vlc, then flatpak mpv
    const players = [
      { cmd: 'mpv', args: ['--force-window=yes', '--no-terminal', ...(startPosition > 0 ? [`--start=${Math.floor(startPosition)}`] : []), streamUrl] },
      { cmd: 'vlc', args: ['--play-and-exit', ...(startPosition > 0 ? [`--start-time=${Math.floor(startPosition)}`] : []), streamUrl] },
      { cmd: 'flatpak', args: ['run', 'io.mpv.Mpv', '--force-window=yes', '--no-terminal', ...(startPosition > 0 ? [`--start=${Math.floor(startPosition)}`] : []), streamUrl] },
    ];

    for (const player of players) {
      try {
        const launched = await new Promise((resolve, reject) => {
          const child = spawn(player.cmd, player.args, {
            stdio: 'ignore',
            detached: false,
          });
          child.on('error', reject);
          child.on('close', () => {
            activePlayerProcess = null;
            mainWindow?.webContents?.send('external-player-closed');
          });
          // If it hasn't errored after 200ms, it launched successfully
          setTimeout(() => {
            activePlayerProcess = child;
            resolve(player.cmd);
          }, 200);
        });
        return { success: true, player: launched };
      } catch {
        continue;
      }
    }

    // Fallback: open with system default handler
    try {
      await shell.openExternal(streamUrl);
      return { success: true, player: 'system' };
    } catch (err) {
      return { success: false, error: 'No compatible player found. Install mpv or VLC.' };
    }
  });

  // ── Embedded mpv player (renders inside the Electron window) ──────
  let mpvController = null;

  ipcMain.handle('mpv:start', async (_event, streamUrl, options) => {
    // Validate URL to prevent command injection
    try {
      const parsed = new URL(streamUrl);
      if (!['http:', 'https:', 'rtmp:', 'rtsp:'].includes(parsed.protocol)) {
        return { success: false, error: 'Invalid URL protocol' };
      }
    } catch {
      return { success: false, error: 'Invalid URL' };
    }

    // Stop any existing embedded player
    if (mpvController) {
      await mpvController.stop();
      mpvController = null;
    }

    mpvController = new MpvController(mainWindow);
    try {
      const result = await mpvController.start(streamUrl, options || {});
      console.log('[mpv:start] Embedded mpv started successfully');
      return { success: true, ...result };
    } catch (err) {
      console.error('[mpv:start] Failed to start embedded mpv:', err.message);
      mpvController = null;
      return { success: false, error: err.message };
    }
  });

  ipcMain.handle('mpv:togglePause', () => mpvController?.togglePause());
  ipcMain.handle('mpv:seek', (_event, seconds) => mpvController?.seek(seconds));
  ipcMain.handle('mpv:seekTo', (_event, seconds) => mpvController?.seekTo(seconds));
  ipcMain.handle('mpv:setAudioTrack', (_event, id) => mpvController?.setAudioTrack(id));
  ipcMain.handle('mpv:setSubtitleTrack', (_event, id) => mpvController?.setSubtitleTrack(id));

  ipcMain.handle('mpv:stop', async () => {
    const controller = mpvController;
    mpvController = null;
    await controller?.stop();
  });

  // Clean up embedded mpv when the window closes
  mainWindow.on('closed', () => {
    if (mpvController) {
      mpvController.stop();
      mpvController = null;
    }
  });

  // Register keyboard shortcuts
  globalShortcut.register('F11', () => {
    if (mainWindow) {
      mainWindow.setFullScreen(!mainWindow.isFullScreen());
    }
  });

  globalShortcut.register('CommandOrControl+Q', () => {
    app.quit();
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
});
