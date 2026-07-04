import 'dart:async';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show shouldUseSidebar;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureSystemUi();
  // MediaKit (libmpv) is used on desktop and iOS. tvOS uses AVKit exclusively.
  if (!kIsWeb && !Platform.isAndroid && Platform.operatingSystem != 'tvos') {
    MediaKit.ensureInitialized();
  }
  final appState = await _buildAppState();
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  runApp(MyApp(nativeTelevisionHint: nativeTelevisionHint, appState: appState));
}

Future<void> _configureSystemUi() async {
  if (kIsWeb || !Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

Future<AppStateController> _buildAppState() async {
  if (Platform.isAndroid ||
      Platform.isIOS ||
      Platform.operatingSystem == 'tvos') {
    final dir = await getApplicationDocumentsDirectory();
    final store = PersistentJsonStore(file: File('${dir.path}/app_state.json'));
    return AppStateController(
      persistentStore: store,
      secureStorage: FlutterSecureStorageAdapter(),
    );
  }
  return AppStateController();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.nativeTelevisionHint = false, this.appState});

  final bool nativeTelevisionHint;
  final AppStateController? appState;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = createGoRouter(
    appState: widget.appState ?? AppStateController(),
    nativeTelevisionHint: widget.nativeTelevisionHint,
  );

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4f39f6);
    const secondary = Color(0xFFec003f);
    const background = Color(0xFF09090b);
    const card = Color(0xFF18181b);
    const elevated = Color(0xFF18181b);

    return MaterialApp.router(
      title: 'M3U TV',
      routerConfig: _router,
      builder: (context, child) {
        final deviceType = resolveDeviceType(
          context,
          nativeTelevisionHint: widget.nativeTelevisionHint,
        );
        final isTvOrDesktop = shouldUseSidebar(deviceType);
        return Dpad(
          theme: const DpadThemeData(
            effects: [
              GradientBorderEffect(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ],
          ),
          // restoreFocus keeps focus alive on TV/desktop (needed for D-pad).
          // On phone/tablet it actively harms scroll: when focus drifts to a
          // FocusScopeNode during a fling, _scheduleRestore fires, calls
          // requestFocus(lastFocused), and DpadScroll.ensureVisible kills the
          // fling mid-scroll with an animateTo() counter-animation.
          restoreFocus: isTvOrDesktop,
          // Click sound is D-pad navigation feedback — not wanted on touch.
          onFocusChange: isTvOrDesktop
              ? (node) {
                  if (node != null) {
                    unawaited(SystemSound.play(SystemSoundType.click));
                  }
                }
              : null,
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: primary,
              brightness: Brightness.dark,
            ).copyWith(
              primary: primary,
              error: const Color(0xFFff0033),
              onError: Colors.white,
              onPrimary: Colors.white,
              secondary: secondary,
              surface: background,
              surfaceContainerLowest: background,
              surfaceContainerLow: card,
              surfaceContainer: card,
              surfaceContainerHigh: card,
              surfaceContainerHighest: elevated,
            ),
        tabBarTheme: TabBarThemeData(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.focused) ||
                states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.10);
            }
            return null;
          }),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: primary,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      themeMode: ThemeMode.dark,
    );
  }
}
