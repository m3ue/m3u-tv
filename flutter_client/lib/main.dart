import 'dart:async';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show shouldUseSidebar;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/production_storage.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  final systemUiPolicy = SystemUiPolicy();
  await systemUiPolicy.applyBrowsing();
  // MediaKit (libmpv) is used on desktop and iOS. tvOS uses AVKit exclusively.
  if (!kIsWeb && !Platform.isAndroid && Platform.operatingSystem != 'tvos') {
    MediaKit.ensureInitialized();
  }
  final appState = await _buildAppState();
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  runApp(
    ProviderScope(
      overrides: [overrideAppState(appState)],
      child: MyApp(
        nativeTelevisionHint: nativeTelevisionHint,
        appState: appState,
        systemUiPolicy: systemUiPolicy,
      ),
    ),
  );
}

Future<AppStateController> _buildAppState() async {
  final operatingSystem = Platform.operatingSystem;
  final store = await _createAppStateStore(operatingSystem);
  final storage = createProductionStorage(
    operatingSystem: operatingSystem,
    persistentStore: store,
  );
  if (shouldMigrateLegacyCredentials(operatingSystem)) {
    await migrateLegacyCredentials(
      appStateStore: storage.appStateStore,
      credentialStorage: storage.credentialStorage,
    );
  }
  return AppStateController(
    persistentStore: storage.appStateStore,
    secureStorage: storage.credentialStorage,
  );
}

Future<PersistentJsonStore> _createAppStateStore(
  String operatingSystem,
) async {
  if (operatingSystem == 'android' ||
      operatingSystem == 'ios' ||
      operatingSystem == 'tvos') {
    final dir = await getApplicationDocumentsDirectory();
    return PersistentJsonStore(file: File('${dir.path}/app_state.json'));
  }
  return PersistentJsonStore();
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.nativeTelevisionHint = false,
    this.appState,
    this.systemUiPolicy,
  });

  final bool nativeTelevisionHint;
  final AppStateController? appState;
  final SystemUiPolicy? systemUiPolicy;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = createGoRouter(
    appState: widget.appState ?? AppStateController(),
    nativeTelevisionHint: widget.nativeTelevisionHint,
    systemUiPolicy: widget.systemUiPolicy,
  );

  @override
  void initState() {
    super.initState();
    widget.appState?.addListener(_onAppStateChanged);
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState?.removeListener(_onAppStateChanged);
      widget.appState?.addListener(_onAppStateChanged);
    }
  }

  @override
  void dispose() {
    widget.appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    // boot() calls notifyListeners() synchronously from AppShellState.initState,
    // which fires mid-build. Deferring to post-frame avoids the setState-during-
    // build assertion in all phases (idle mount, persistent-callbacks frame, etc.)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: widget.appState?.locale,
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
          // Click sound is D-pad navigation feedback, not wanted on touch.
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
