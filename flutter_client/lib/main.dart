import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  runApp(MyApp(nativeTelevisionHint: nativeTelevisionHint));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.nativeTelevisionHint = false});

  final bool nativeTelevisionHint;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF4f39f6);
    const secondary = Color(0xFFec003f);
    const background = Color(0xFF18181b);

    return MaterialApp(
      title: 'M3U TV',
      builder: Dpad.wrap(
        debugOverlay: kDebugMode,
        theme: const DpadThemeData(
          effects: [DpadBorderEffect(), DpadScaleEffect(scale: 1.04)],
          scrollPadding: 48,
        ),
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: primary,
              brightness: Brightness.dark,
            ).copyWith(
              primary: primary,
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
        ),
      ),
    );
  }
}
