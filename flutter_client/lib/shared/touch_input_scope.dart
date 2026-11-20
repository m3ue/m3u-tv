import 'package:flutter/widgets.dart';

/// Whether the app is running as a touch device (phone or tablet), set once
/// at the app root from the resolved `DeviceType`.
///
/// Shared widgets can't import `DeviceType` (it lives in `app_shell.dart`,
/// an import-cycle risk), and Android TV can't be told apart from an Android
/// tablet by platform alone: it only shows up through the native television
/// hint the root resolves. This carries that answer down as a plain bool.
class TouchInputScope extends InheritedWidget {
  const TouchInputScope({
    required this.isTouch,
    required super.child,
    super.key,
  });

  final bool isTouch;

  /// False when no scope is present, so widgets keep their D-pad behavior.
  static bool isTouchOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TouchInputScope>()?.isTouch ??
      false;

  @override
  bool updateShouldNotify(TouchInputScope oldWidget) =>
      isTouch != oldWidget.isTouch;
}
