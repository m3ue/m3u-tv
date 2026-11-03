import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// The design language the shared widgets in `lib/shared` render in.
///
/// Screens never branch on this themselves: they build from the shared
/// widgets (`AppButton`, `AppSwitch`, `appPageRoute`, ...), which read it
/// from [AppDesignScope] and pick the Material or Cupertino rendering.
enum AppDesign { material, cupertino }

/// `--dart-define=M3U_TV_DESIGN=material|cupertino` forces one design on
/// every platform, e.g. to review Material on a Mac or Cupertino on Android.
/// Unset (or any other value) uses the platform default.
const String _kDesignOverride = String.fromEnvironment('M3U_TV_DESIGN');

/// Cupertino on iPhone, iPad and macOS; Material everywhere else, including
/// Apple TV, which keeps the TV look (and reports [TargetPlatform.iOS], so
/// it has to be ruled out by OS name first).
AppDesign resolveAppDesign({
  String override = _kDesignOverride,
  TargetPlatform? platform,
  bool? isTvOS,
  bool isWeb = kIsWeb,
}) {
  switch (override) {
    case 'material':
      return AppDesign.material;
    case 'cupertino':
      return AppDesign.cupertino;
  }
  if (isWeb || (isTvOS ?? HostPlatform.isTvOS)) return AppDesign.material;
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => AppDesign.cupertino,
    TargetPlatform.android ||
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.windows => AppDesign.material,
  };
}

/// Provides the app's [AppDesign] to the shared widgets. Installed once in
/// `MaterialApp.builder` with [resolveAppDesign].
class AppDesignScope extends InheritedWidget {
  const AppDesignScope({super.key, required this.design, required super.child});

  final AppDesign design;

  /// Material when no scope is installed, so a widget test only renders
  /// Cupertino when it asks for it, never because of the host it runs on.
  static AppDesign of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppDesignScope>()?.design ??
      AppDesign.material;

  static bool isCupertino(BuildContext context) =>
      of(context) == AppDesign.cupertino;

  @override
  bool updateShouldNotify(AppDesignScope oldWidget) =>
      design != oldWidget.design;
}
