const { app, BrowserWindow, globalShortcut, protocol, net, session, ipcMain, shell } = require('electron');
const path = require('path');
const url = require('url');
const fs = require('fs');
const nodeNet = require('net');
const os = require('os');
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
  const iconFile = process.platform === 'darwin'
    ? path.join(__dirname, 'images', 'icon.icns')
    : path.join(__dirname, 'images', 'icon.png');

  mainWindow = new BrowserWindow({
    width: 1280,
    height: 720,
    minWidth: 800,
    minHeight: 600,
    backgroundColor: '#0a0a0f',
    icon: iconFile,
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
  app.setName('M3U TV');

  // Set dock icon explicitly on macOS (required in dev mode; packaged builds use the .icns in the bundle)
  if (process.platform === 'darwin' && app.dock) {
    app.dock.setIcon(path.join(__dirname, 'images', 'icon.png'));
  }

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

  // ── Floating mpv windows — one per stream, independent of the main window ──
  // Each call spawns a new mpv window. The main Electron window is never hidden.
  // The IPC promise resolves only once mpv's socket connects, so the renderer's
  // loading spinner stays visible until mpv's window is actually on screen.
  ipcMain.handle('mpv:open-floating', async (_event, streamUrl, options) => {
    // Validate URL to prevent command injection
    try {
      const parsed = new URL(streamUrl);
      if (!['http:', 'https:', 'rtmp:', 'rtsp:'].includes(parsed.protocol)) {
        return { success: false, error: 'Invalid URL protocol' };
      }
    } catch {
      return { success: false, error: 'Invalid URL' };
    }

    const mpvInfo = MpvController.findMpvCommand();
    if (!mpvInfo) {
      return { success: false, error: 'mpv not found. Install mpv to use the player.' };
    }

    const startPosition = options?.startPosition || 0;
    const title = options?.title || 'm3u-tv';

    // Unique socket path so we can detect when mpv is ready
    const socketPath = process.platform === 'win32'
      ? `\\\\.\\pipe\\m3u-tv-float-${Date.now()}`
      : path.join(os.tmpdir(), `m3u-tv-float-${Date.now()}.sock`);

    const mpvConfigDir = path.join(__dirname, 'mpv');

    const mpvArgs = [
      ...mpvInfo.args,
      `--config-dir=${mpvConfigDir}`,
      '--force-window=yes',
      '--hwdec=auto',
      '--keep-open=no',
      '--idle=no',
      '--osc=no',
      '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      `--title=${title}`,
      '--geometry=960x540',
      `--input-ipc-server=${socketPath}`,
      ...(startPosition > 0 ? [`--start=${Math.floor(startPosition)}`] : []),
      '--', streamUrl,
    ];

    const child = spawn(mpvInfo.cmd, mpvArgs, { stdio: 'ignore', detached: false });
    child.on('error', (err) => console.error('[mpv:open-floating] Failed to start:', err.message));

    // Wait until mpv's IPC socket connects — this confirms the window is visible.
    // Resolves early on error or after an 8-second safety timeout.
    await new Promise((resolve) => {
      const deadline = setTimeout(resolve, 8000);

      const tryConnect = () => {
        if (process.platform !== 'win32' && !fs.existsSync(socketPath)) {
          setTimeout(tryConnect, 150);
          return;
        }
        const sock = nodeNet.createConnection(socketPath);
        sock.on('connect', () => { sock.destroy(); clearTimeout(deadline); setTimeout(resolve, 1000); });
        sock.on('error', () => setTimeout(tryConnect, 150));
      };
      setTimeout(tryConnect, 200);
    });

    if (process.platform !== 'win32') {
      try { fs.unlinkSync(socketPath); } catch {}
    }

    return { success: true };
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
