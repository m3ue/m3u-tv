import 'package:window_manager/window_manager.dart';

Window? _cachedWindow;

/// The app's native desktop window (macOS, Windows, Linux), or null where
/// there is none.
///
/// Null off desktop and in widget tests: those run in a Dart VM without the
/// nativeapi library, where the FFI symbol lookup throws [ArgumentError].
/// Resolved once and cached, since every `getCurrent()` call wraps a fresh
/// native handle.
Window? currentDesktopWindow() {
  if (_cachedWindow != null) return _cachedWindow;
  try {
    return _cachedWindow = WindowManager.instance.getCurrent();
    // The missing-library lookup failure is an Error, not an Exception.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return null;
  }
}
