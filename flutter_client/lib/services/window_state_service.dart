import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:window_manager/window_manager.dart';

/// Remembers the desktop window's size, position and maximized state across
/// launches (Windows, macOS and Linux). Restore is applied while the window is
/// still hidden; afterwards this object registers as a [WindowListener] and
/// writes the geometry back whenever the user finishes moving/resizing or
/// toggles maximize.
class WindowStateService with WindowListener {
  WindowStateService(this._viewSettings);

  final ViewSettingsService _viewSettings;

  bool _maximized = false;
  Timer? _debounce;

  /// Applies the saved geometry to the (still hidden) window. Call inside
  /// `windowManager.waitUntilReadyToShow(...)` before `show()`.
  Future<void> restore() async {
    final saved = await _viewSettings.windowBounds();
    if (saved == null) return;
    await windowManager.setBounds(
      Rect.fromLTWH(saved.x, saved.y, saved.width, saved.height),
    );
    // A window restored fully off-screen (monitor unplugged, resolution
    // change) is unreachable - pull it back to the primary display.
    if (!await windowManager.isVisible() || !await _isOnScreen()) {
      await windowManager.center();
    }
    if (saved.maximized) {
      _maximized = true;
      await windowManager.maximize();
    }
  }

  Future<bool> _isOnScreen() async {
    final bounds = await windowManager.getBounds();
    // Require at least a sliver of the frame to sit at non-negative coords and
    // within a generous virtual-desktop span; good enough without pulling in
    // screen_retriever for exact monitor rects.
    return bounds.left > -bounds.width + 80 &&
        bounds.top >= 0 &&
        bounds.left < 20000 &&
        bounds.top < 20000;
  }

  // `onWindowResized` / `onWindowMoved` fire once at drag-end on macOS and
  // Windows. Linux only emits the live `onWindowResize` / `onWindowMove`, so
  // debounce those to get a single write there too.
  @override
  void onWindowResized() => unawaited(_persist());

  @override
  void onWindowMoved() => unawaited(_persist());

  @override
  void onWindowResize() => _persistDebounced();

  @override
  void onWindowMove() => _persistDebounced();

  @override
  void onWindowMaximize() {
    _maximized = true;
    unawaited(_persist());
  }

  @override
  void onWindowUnmaximize() {
    _maximized = false;
    unawaited(_persist());
  }

  // Leaving fullscreen animates back through intermediate sizes, and on macOS
  // that programmatic resize doesn't end with `onWindowResized`; record the
  // settled normal bounds once it lands.
  @override
  void onWindowLeaveFullScreen() => _persistDebounced();

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
    windowManager.removeListener(this);
  }

  Future<void> _persist() async {
    try {
      // A fullscreen window's bounds are the monitor's, not a size the user
      // chose. macOS sets the fullscreen style at the start of its transition
      // animation, so this also skips the resizes fired mid-animation.
      if (await windowManager.isFullScreen()) return;
      // While maximized, getBounds() returns the maximized rect; keep the last
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
      final bounds = await windowManager.getBounds();
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
