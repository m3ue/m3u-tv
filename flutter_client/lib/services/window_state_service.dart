import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:window_manager/window_manager.dart';

/// Remembers the desktop window's size, position and maximized state across
/// launches (Windows, macOS and Linux). [restore] applies the saved geometry
/// before the window is shown; [attach] then listens to the window and writes
/// the geometry back whenever the user moves, resizes or toggles maximize.
class WindowStateService {
  WindowStateService(this._viewSettings);

  final ViewSettingsService _viewSettings;

  Window? _window;
  ListenerId? _listenerId;
  bool _maximized = false;
  Timer? _debounce;

  /// Applies the saved geometry to [window]. Call before `window.show()`.
  Future<void> restore(Window window) async {
    final saved = await _viewSettings.windowBounds();
    if (saved == null) return;
    window.bounds = Rect.fromLTWH(
      saved.x,
      saved.y,
      saved.width,
      saved.height,
    ).toNative();
    // A window restored fully off-screen (monitor unplugged, resolution
    // change) is unreachable - pull it back to the primary display.
    if (!window.isVisible || !_isOnScreen(window.bounds.toRect())) {
      window.center();
    }
    if (saved.maximized) {
      _maximized = true;
      window.maximize();
    }
  }

  /// Starts persisting [window]'s geometry as it changes.
  void attach(Window window) {
    _window = window;
    _listenerId = window.addListener(_onWindowEvent);
  }

  bool _isOnScreen(Rect bounds) {
    // Require at least a sliver of the frame to sit at non-negative coords and
    // within a generous virtual-desktop span; good enough without querying
    // exact monitor rects.
    return bounds.left > -bounds.width + 80 &&
        bounds.top >= 0 &&
        bounds.left < 20000 &&
        bounds.top < 20000;
  }

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowMaximizedEvent():
        _maximized = true;
        unawaited(_persist());
      // One restored event covers both "no longer maximized" and "no longer
      // minimized"; only the former changes what is saved.
      case WindowRestoredEvent():
        if (_maximized && !(_window?.isMaximized ?? false)) {
          _maximized = false;
          unawaited(_persist());
        }
      // nativeapi reports every step of a drag, not just its end. Leaving
      // fullscreen also animates back through intermediate sizes. Debounce
      // both to a single write of the settled bounds.
      case WindowResizedEvent() ||
          WindowMovedEvent() ||
          WindowExitedFullScreenEvent():
        _persistDebounced();
      default:
        break;
    }
  }

  void _persistDebounced() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persist()),
    );
  }

  /// Stops the listener and cancels any pending write. The app has no desktop
  /// teardown path today, but this keeps the service safe to dispose in tests.
  void dispose() {
    _debounce?.cancel();
    final listenerId = _listenerId;
    if (listenerId != null) _window?.removeListener(listenerId);
    _listenerId = null;
  }

  Future<void> _persist() async {
    final window = _window;
    if (window == null) return;
    try {
      // A fullscreen window's bounds are the monitor's, not a size the user
      // chose. macOS sets the fullscreen style at the start of its transition
      // animation, so this also skips the resizes fired mid-animation.
      if (window.isFullScreen) return;
      // While maximized the bounds are the maximized rect; keep the last
      // restored/normal rect by only recording size+position when not maximized.
      if (_maximized) {
        final current = await _viewSettings.windowBounds();
        if (current != null) {
          await _viewSettings.setWindowBounds(
            WindowBounds(
              x: current.x,
              y: current.y,
              width: current.width,
              height: current.height,
              maximized: true,
            ),
          );
        }
        return;
      }
      final bounds = window.bounds.toRect();
      await _viewSettings.setWindowBounds(
        WindowBounds(
          x: bounds.left,
          y: bounds.top,
          width: bounds.width,
          height: bounds.height,
          maximized: false,
        ),
      );
    } on Object catch (error) {
      debugPrint('Failed to persist window bounds: $error');
    }
  }
}
