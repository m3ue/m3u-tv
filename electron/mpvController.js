/**
 * MpvController — manages mpv as a seamless takeover player with JSON IPC.
 *
 * Since Electron cannot embed native video frames (libmpv render API requires
 * a native toolkit like Flutter/Qt), we use a "takeover" approach:
 *
 * 1. Record the Electron window's position, size, and fullscreen state
 * 2. Hide the Electron window
 * 3. mpv opens at the exact same geometry (or fullscreen if Electron was)
 * 4. Progress, tracks, and state are tracked via JSON IPC socket so the
 *    renderer can continue updating watch progress to the server
 * 5. When mpv closes (user presses q, or stream ends), Electron reappears
 *
 * This works on X11, Wayland, and Windows without any native addons.
 */
const { spawn } = require('child_process');
const net = require('net');
const path = require('path');
const os = require('os');
const fs = require('fs');

const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

class MpvController {
  constructor(mainWindow) {
    this.mainWindow = mainWindow;
    this.process = null;
    this.socket = null;
    this.requestId = 0;
    this.pendingRequests = new Map();
    this.buffer = '';
    this.destroyed = false;
    this.windowWasFullscreen = false;

    // Platform-specific socket path
    if (process.platform === 'win32') {
      this.socketPath = `\\\\.\\pipe\\m3u-tv-mpv-${process.pid}`;
    } else {
      this.socketPath = path.join(os.tmpdir(), `m3u-tv-mpv-${process.pid}.sock`);
    }
  }

  /**
   * Locate the mpv binary. Search order:
   *   1. Bundled binary (electron-builder extraResources — production)
   *   2. Dev-mode binaries from scripts/download-binaries.sh
   *   3. Homebrew paths on macOS (Electron does not inherit shell PATH)
   *   4. PATH via `which`
   *   5. Flatpak on Linux
   */
  static findMpvCommand() {
    const { execSync } = require('child_process');
    const bin = process.platform === 'win32' ? 'mpv.exe' : 'mpv';
    const arch = process.arch === 'arm64' ? 'arm64' : 'x64';

    // 1. Packaged build — electron-builder puts extraResources here
    if (process.resourcesPath) {
      const p = path.join(process.resourcesPath, 'mpv', bin);
      if (fs.existsSync(p)) return { cmd: p, args: [], isFlatpak: false };
    }

    // 2. Dev-mode bundle (scripts/download-binaries.sh output)
    const devPaths = process.platform === 'darwin'
      ? [path.join(__dirname, '..', 'binaries', 'mac', arch, bin)]
      : process.platform === 'win32'
        ? [path.join(__dirname, '..', 'binaries', 'win', 'x64', bin)]
        : [];
    for (const p of devPaths) {
      if (fs.existsSync(p)) return { cmd: p, args: [], isFlatpak: false };
    }

    // 3. Homebrew on macOS (Electron inherits a minimal PATH, not the shell one)
    if (process.platform === 'darwin') {
      for (const p of ['/opt/homebrew/bin/mpv', '/usr/local/bin/mpv']) {
        if (fs.existsSync(p)) return { cmd: p, args: [], isFlatpak: false };
      }
    }

    // 4. Generic PATH
    try {
      execSync('which mpv', { stdio: 'ignore' });
      return { cmd: 'mpv', args: [], isFlatpak: false };
    } catch {}

    // 5. Flatpak (Linux only)
    if (process.platform === 'linux') {
      try {
        execSync('flatpak info io.mpv.Mpv', { stdio: 'ignore' });
        return { cmd: 'flatpak', args: ['run', 'io.mpv.Mpv'], isFlatpak: true };
      } catch {}
    }

    return null;
  }

  /**
   * Start mpv in takeover mode: hide Electron, mpv plays at same geometry.
   */
  async start(streamUrl, options = {}) {
    if (this.destroyed) throw new Error('Controller was destroyed');

    // Clean up any stale socket
    if (process.platform !== 'win32') {
      try { fs.unlinkSync(this.socketPath); } catch {}
    }

    const mpvInfo = MpvController.findMpvCommand();
    if (!mpvInfo) {
      throw new Error('mpv not found. Install mpv to use embedded playback.');
    }

    // Remember window state and capture geometry before hiding
    this.windowWasFullscreen = this.mainWindow.isFullScreen();
    this.windowWasMaximized = this.mainWindow.isMaximized();
    const bounds = this.mainWindow.getBounds();

    const mpvArgs = [
      ...mpvInfo.args,
      '--force-window=yes',
      '--hwdec=auto',
      '--keep-open=no',
      '--idle=no',
      `--input-ipc-server=${this.socketPath}`,
      `--user-agent=${options.userAgent || USER_AGENT}`,
      `--title=${options.title || 'm3u-tv'}`,
    ];

    // Match Electron window state
    if (this.windowWasFullscreen) {
      mpvArgs.push('--fullscreen=yes');
    } else {
      // Open at same position and size as Electron window
      mpvArgs.push(`--geometry=${bounds.width}x${bounds.height}+${bounds.x}+${bounds.y}`);
      mpvArgs.push('--no-border');
    }

    if (options.startPosition > 0) {
      mpvArgs.push(`--start=${Math.floor(options.startPosition)}`);
    }

    // '--' separates options from the URL to prevent URL injection
    mpvArgs.push('--', streamUrl);

    return new Promise((resolve, reject) => {
      console.log('[mpvController] Spawning:', mpvInfo.cmd, mpvArgs.join(' '));
      this.process = spawn(mpvInfo.cmd, mpvArgs, {
        stdio: 'ignore',
        detached: false,
      });

      this.process.on('error', (err) => {
        this._showWindow();
        this._cleanup();
        reject(err);
      });

      this.process.on('close', (code) => {
        console.log('[mpvController] mpv exited with code', code);
        this._sendToRenderer('mpv:end', { code, reason: code === 0 ? 'quit' : 'error' });
        this._showWindow();
        this._cleanup();
      });

      // Hide Electron and connect to IPC
      this._hideWindow();
      this._connectSocket(0)
        .then(() => {
          this._observeProperty('time-pos');
          this._observeProperty('duration');
          this._observeProperty('pause');
          this._observeProperty('eof-reached');
          this._observeProperty('track-list');
          this._observeProperty('paused-for-cache');
          resolve({ embedded: true });
        })
        .catch((err) => {
          // IPC connect failed but mpv may still be running — that's OK
          console.warn('[mpvController] IPC connect failed:', err.message);
          resolve({ embedded: true, ipc: false });
        });
    });
  }

  /** Hide the Electron window. */
  _hideWindow() {
    try {
      this.mainWindow?.hide();
    } catch {}
  }

  /** Show the Electron window, restoring its previous state. */
  _showWindow() {
    try {
      if (!this.mainWindow || this.mainWindow.isDestroyed()) return;
      this.mainWindow.show();
      if (this.windowWasMaximized) {
        this.mainWindow.maximize();
      }
      this.mainWindow.focus();
    } catch {}
  }

  /** Connect to mpv's IPC socket with retries. */
  _connectSocket(attempt) {
    return new Promise((resolve, reject) => {
      if (attempt > 30) {
        reject(new Error('Failed to connect to mpv IPC socket'));
        return;
      }

      setTimeout(() => {
        if (this.destroyed) {
          reject(new Error('Controller destroyed'));
          return;
        }

        if (process.platform !== 'win32' && !fs.existsSync(this.socketPath)) {
          this._connectSocket(attempt + 1).then(resolve).catch(reject);
          return;
        }

        const socket = net.createConnection(this.socketPath);

        socket.on('connect', () => {
          this.socket = socket;
          resolve();
        });

        socket.on('data', (data) => {
          this.buffer += data.toString();
          const lines = this.buffer.split('\n');
          this.buffer = lines.pop() || '';

          for (const line of lines) {
            if (!line.trim()) continue;
            try {
              this._handleMessage(JSON.parse(line));
            } catch {}
          }
        });

        socket.on('error', () => {
          socket.destroy();
          this._connectSocket(attempt + 1).then(resolve).catch(reject);
        });

        socket.on('close', () => {
          this.socket = null;
        });
      }, 100);
    });
  }

  /** Handle an incoming JSON message from mpv. */
  _handleMessage(msg) {
    if (msg.request_id !== undefined && this.pendingRequests.has(msg.request_id)) {
      const { resolve, reject } = this.pendingRequests.get(msg.request_id);
      this.pendingRequests.delete(msg.request_id);
      if (msg.error === 'success') {
        resolve(msg.data);
      } else {
        reject(new Error(msg.error));
      }
      return;
    }

    if (msg.event === 'property-change') {
      this._handlePropertyChange(msg);
      return;
    }

    if (msg.event === 'end-file') {
      this._sendToRenderer('mpv:end', { reason: msg.reason || 'eof' });
    }
  }

  /** Forward property changes to the renderer. */
  _handlePropertyChange(msg) {
    const { name, data } = msg;

    switch (name) {
      case 'time-pos':
        if (typeof data === 'number') {
          this._sendToRenderer('mpv:progress', { property: 'time-pos', value: data });
        }
        break;
      case 'duration':
        if (typeof data === 'number') {
          this._sendToRenderer('mpv:progress', { property: 'duration', value: data });
        }
        break;
      case 'pause':
        this._sendToRenderer('mpv:pause', { paused: !!data });
        break;
      case 'eof-reached':
        if (data === true) {
          this._sendToRenderer('mpv:end', { reason: 'eof' });
        }
        break;
      case 'track-list':
        if (Array.isArray(data)) {
          const audioTracks = data
            .filter((t) => t.type === 'audio')
            .map((t) => ({
              id: t.id,
              name: t.title || t.lang || `Audio ${t.id}`,
              language: t.lang || undefined,
            }));
          const textTracks = data
            .filter((t) => t.type === 'sub')
            .map((t) => ({
              id: t.id,
              name: t.title || t.lang || `Subtitle ${t.id}`,
              language: t.lang || undefined,
            }));
          this._sendToRenderer('mpv:tracks', { audioTracks, textTracks });
        }
        break;
      case 'paused-for-cache':
        this._sendToRenderer('mpv:buffering', { isBuffering: !!data });
        break;
    }
  }

  /** Send a JSON command to mpv. */
  _sendCommand(command) {
    return new Promise((resolve, reject) => {
      if (!this.socket || this.socket.destroyed) {
        reject(new Error('Not connected to mpv'));
        return;
      }
      const id = ++this.requestId;
      this.pendingRequests.set(id, { resolve, reject });
      this.socket.write(JSON.stringify({ command, request_id: id }) + '\n');
    });
  }

  /** Observe a mpv property for changes. */
  _observeProperty(name) {
    const id = ++this.requestId;
    if (this.socket && !this.socket.destroyed) {
      this.socket.write(
        JSON.stringify({ command: ['observe_property', id, name], request_id: id }) + '\n',
      );
    }
  }

  /** Send an IPC message to the renderer process. */
  _sendToRenderer(channel, data) {
    try {
      this.mainWindow?.webContents?.send(channel, data);
    } catch {}
  }

  // ── Public API ─────────────────────────────────────────────────

  async togglePause() {
    return this._sendCommand(['cycle', 'pause']);
  }

  async seek(seconds) {
    return this._sendCommand(['seek', seconds, 'relative']);
  }

  async seekTo(seconds) {
    return this._sendCommand(['seek', seconds, 'absolute']);
  }

  async setAudioTrack(id) {
    return this._sendCommand(['set_property', 'aid', id <= 0 ? 'auto' : id]);
  }

  async setSubtitleTrack(id) {
    return this._sendCommand(['set_property', 'sid', id <= 0 ? 'no' : id]);
  }

  async stop() {
    try {
      await this._sendCommand(['quit']);
    } catch {}
    this._cleanup();
  }

  /** Clean up all resources. */
  _cleanup() {
    this.destroyed = true;

    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }

    if (this.process) {
      try { this.process.kill(); } catch {}
      this.process = null;
    }

    if (process.platform !== 'win32') {
      try { fs.unlinkSync(this.socketPath); } catch {}
    }

    this.pendingRequests.forEach(({ reject }) => reject(new Error('Controller stopped')));
    this.pendingRequests.clear();
  }
}

module.exports = { MpvController };
