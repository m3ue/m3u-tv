import 'package:flutter/services.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:material_ui/material_ui.dart';

/// Whether [event] is a lone Backspace press on desktop with no text field
/// focused: there, Backspace does what Escape does. In a field it stays
/// delete, so everything binding it must go through here.
bool isDesktopBackspaceBack(KeyEvent event, HardwareKeyboard keyboard) {
  if (!HostPlatform.isDesktop ||
      event is! KeyDownEvent ||
      event.logicalKey != LogicalKeyboardKey.backspace ||
      keyboard.logicalKeysPressed.length > 1) {
    return false;
  }
  final focused = FocusManager.instance.primaryFocus?.context;
  return focused?.findAncestorWidgetOfExactType<EditableText>() == null;
}

/// Binds [isDesktopBackspaceBack] in a [Shortcuts] map, next to Escape.
class DesktopBackspaceActivator extends ShortcutActivator {
  const DesktopBackspaceActivator();

  @override
  Iterable<LogicalKeyboardKey> get triggers => const [
    LogicalKeyboardKey.backspace,
  ];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      isDesktopBackspaceBack(event, state);

  @override
  String debugDescribeKeys() => 'Backspace (desktop, outside text fields)';
}
