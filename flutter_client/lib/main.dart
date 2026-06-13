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
    return MaterialApp(
      title: 'M3U TV',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
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
