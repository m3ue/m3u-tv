import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // MediaKit (libmpv) is used on desktop and iOS. tvOS uses AVKit exclusively.
  if (!kIsWeb && !Platform.isAndroid && Platform.operatingSystem != 'tvos') {
    MediaKit.ensureInitialized();
  }
  final appState = await _buildAppState();
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  runApp(MyApp(nativeTelevisionHint: nativeTelevisionHint, appState: appState));
}

Future<AppStateController> _buildAppState() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final store = PersistentJsonStore(
      file: File('${dir.path}/app_state.json'),
    );
    return AppStateController(
      persistentStore: store,
      secureStorage: FlutterSecureStorageAdapter(),
    );
  }
  // Desktop (macOS, Linux, Windows): existing _defaultPath() logic is correct.
  return AppStateController();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.nativeTelevisionHint = false, this.appState});

  final bool nativeTelevisionHint;
  final AppStateController? appState;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4f39f6);
    const secondary = Color(0xFFec003f);
    const background = Color(0xFF18181b);

    return MaterialApp(
      title: 'M3U TV',
      builder: Dpad.wrap(
        theme: const DpadThemeData(
          effects: [
            DpadBorderEffect(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ],
        ),
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
            ),
      ),
      themeMode: ThemeMode.dark,
      home: Builder(
        builder: (context) => AppShell(
          deviceType: resolveDeviceType(
            context,
            nativeTelevisionHint: nativeTelevisionHint,
          ),
          appState: appState,
        ),
      ),
    );
  }
}
