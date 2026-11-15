import 'package:flutter/widgets.dart';

/// Runs one frame now when the app is in the background, where Flutter
/// schedules none: state changed from outside the UI there (a lock screen or
/// media notification button) otherwise only reaches widgets once the app is
/// back in front. Build and layout run; nothing is drawn while backgrounded.
void runFrameIfBackgrounded() {
  final binding = WidgetsBinding.instance;
  if (binding.lifecycleState == AppLifecycleState.resumed) return;
  binding.scheduleWarmUpFrame();
}
