import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Window manager calls the service needs, so tests can drive it without the
/// platform channel.
abstract class FullscreenWindow {
  Future<bool> isFullScreen();
  Future<void> setFullScreen({required bool fullscreen});
}

class _WindowManagerFullscreenWindow implements FullscreenWindow {
  const _WindowManagerFullscreenWindow();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen({required bool fullscreen}) =>
      windowManager.setFullScreen(fullscreen);
}

/// Desktop (macOS/Windows/Linux) fullscreen state and shortcuts.
///
/// State follows the window manager's enter/leave events, so the macOS green
/// button and View > Enter Full Screen (Ctrl+Cmd+F) stay in sync with the
/// in-app toggle. Shortcuts: F11 everywhere, Alt+Enter on Windows/Linux, and
/// Escape leaves fullscreen before it is treated as Back.
///
/// Toggles are ignored while a transition is in flight. macOS animates into
/// its own Space for most of a second, and a second `toggleFullScreen` during
/// that animation leaves the window (and the mpv surface inside it) mid-resize.
class DesktopFullscreenService extends ChangeNotifier with WindowListener {
  DesktopFullscreenService({
    this.window = const _WindowManagerFullscreenWindow(),
    bool? altEnterToggles,
    this.transitionTimeout = const Duration(seconds: 3),
  }) : _altEnterToggles =
           altEnterToggles ??
           (!kIsWeb && (Platform.isWindows || Platform.isLinux));

  static DesktopFullscreenService? _instance;

  /// The installed app-wide instance, or null off desktop.
  static DesktopFullscreenService? get instance => _instance;

  final FullscreenWindow window;
  final bool _altEnterToggles;

  /// Fallback for a transition whose enter/leave event never arrives (e.g.
  /// the OS refused it): state is re-read from the window after this.
  final Duration transitionTimeout;

  bool _isFullscreen = false;
  bool _transitioning = false;
  Timer? _transitionTimer;
  final Set<PhysicalKeyboardKey> _swallowedKeys = <PhysicalKeyboardKey>{};

  bool get isFullscreen => _isFullscreen;

  /// True between a toggle request and the window confirming it.
  bool get isTransitioning => _transitioning;

  /// Registers the window listener and key handler and makes this the app-wide
  /// [instance]. Call once after `windowManager.ensureInitialized()`.
  Future<void> install() async {
    _instance = this;
    windowManager.addListener(this);
    FocusManager.instance.addEarlyKeyEventHandler(handleKeyEvent);
    _setFullscreen(await window.isFullScreen());
  }

  Future<void> toggle() => setFullscreen(fullscreen: !_isFullscreen);

  Future<void> setFullscreen({required bool fullscreen}) async {
    if (_transitioning || fullscreen == _isFullscreen) return;
    _transitioning = true;
    notifyListeners();
    _transitionTimer?.cancel();
    _transitionTimer = Timer(transitionTimeout, () {
      unawaited(_resyncFromWindow());
    });
    try {
      await window.setFullScreen(fullscreen: fullscreen);
    } on Object catch (error) {
      debugPrint('Fullscreen toggle failed: $error');
      await _resyncFromWindow();
    }
  }

  Future<void> _resyncFromWindow() async {
    bool actual;
    try {
      actual = await window.isFullScreen();
    } on Object catch (_) {
      actual = _isFullscreen;
    }
    _finishTransition(actual);
  }

  void _finishTransition(bool fullscreen) {
    _transitionTimer?.cancel();
    _transitionTimer = null;
    final changed = _transitioning || fullscreen != _isFullscreen;
    _transitioning = false;
    _isFullscreen = fullscreen;
    if (changed) notifyListeners();
  }

  void _setFullscreen(bool value) {
    if (value == _isFullscreen) return;
    _isFullscreen = value;
    notifyListeners();
  }

  @override
  void onWindowEnterFullScreen() => _finishTransition(true);

  @override
  void onWindowLeaveFullScreen() => _finishTransition(false);

  /// Early key handler, so a handled key never reaches the focus tree. A
  /// plain `HardwareKeyboard` handler can't do that (every handler runs), which
  /// let Escape both leave fullscreen and pop the player mid-transition.
  @visibleForTesting
  KeyEventResult handleKeyEvent(KeyEvent event) {
    final key = event.physicalKey;
    if (event is! KeyDownEvent) {
      // Swallow the repeat/up of a key whose down we consumed, so nothing
      // downstream sees half a key press.
      if (!_swallowedKeys.contains(key)) return KeyEventResult.ignored;
      if (event is KeyUpEvent) _swallowedKeys.remove(key);
      return KeyEventResult.handled;
    }

    final logical = event.logicalKey;
    final bool consume;
    if (logical == LogicalKeyboardKey.f11) {
      unawaited(toggle());
      consume = true;
    } else if (_altEnterToggles &&
        (logical == LogicalKeyboardKey.enter ||
            logical == LogicalKeyboardKey.numpadEnter) &&
        HardwareKeyboard.instance.isAltPressed) {
      unawaited(toggle());
      consume = true;
    } else if (logical == LogicalKeyboardKey.escape &&
        (_isFullscreen || _transitioning) &&
        !_dialogHasFocus()) {
      unawaited(setFullscreen(fullscreen: false));
      consume = true;
    } else {
      consume = false;
    }
    if (!consume) return KeyEventResult.ignored;
    _swallowedKeys.add(key);
    return KeyEventResult.handled;
  }

  /// Escape still closes an open dialog or popup first; fullscreen only
  /// claims it on a regular page.
  bool _dialogHasFocus() {
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null || !focusContext.mounted) return false;
    return ModalRoute.of(focusContext) is PopupRoute;
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    windowManager.removeListener(this);
    FocusManager.instance.removeEarlyKeyEventHandler(handleKeyEvent);
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }
}

/// Exposes [DesktopFullscreenService] state to the widget tree, so layout that
/// only exists for a windowed frame (the macOS titlebar strip and the
/// traffic-light inset) can drop it while fullscreen.
class DesktopFullscreenScope
    extends InheritedNotifier<DesktopFullscreenService> {
  const DesktopFullscreenScope({
    super.key,
    required DesktopFullscreenService service,
    required super.child,
  }) : super(notifier: service);

  /// False when there is no scope (TV, mobile, tests).
  static bool isFullscreenOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DesktopFullscreenScope>()
          ?.notifier
          ?.isFullscreen ??
      false;

  /// The service, or null when there is no scope.
  static DesktopFullscreenService? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopFullscreenScope>()
      ?.notifier;
}
