import 'dart:async';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show DeviceType, shouldUseSidebar;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/go_router_config.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/production_storage.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_image_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  final systemUiPolicy = SystemUiPolicy();
  await systemUiPolicy.applyBrowsing();
  if (!kIsWeb && Platform.isMacOS) {
    await _configureMacOSWindow();
  }
  final appState = await _buildAppState();
  final nativeTelevisionHint = await resolveNativeTelevisionHint();
  if (_isMobilePushCapable(nativeTelevisionHint)) {
    unawaited(_initPushNotifications(appState));
  }
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

/// Hides the native titlebar and lets app content extend under the traffic
/// lights (macOS "hidden inline titlebar" look). AppShell paints the app's
/// background color (0xFF09090b) into a DragToMoveArea + top inset for
/// macOS desktop so the window stays draggable, the titlebar reads as a
/// solid bar, and the sidebar logo doesn't sit under the traffic lights.
Future<void> _configureMacOSWindow() async {
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setTitle('');
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Push is mobile-only: TV builds (Android TV, tvOS) rely on the existing
/// Reverb pipeline instead. tvOS reports `Platform.operatingSystem == 'tvos'`
/// (not 'ios'), so `Platform.isIOS` alone already excludes it.
bool _isMobilePushCapable(bool nativeTelevisionHint) =>
    (Platform.isAndroid && !nativeTelevisionHint) || Platform.isIOS;

Future<void> _initPushNotifications(AppStateController appState) async {
  try {
    await appState.initPushNotifications();
  } on Object catch (_) {
    // Best-effort: e.g. Firebase config not yet installed on this build.
    debugPrint('Push notification init failed');
  }
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
  if (operatingSystem == 'tvos') {
    // Documents exists but is read-only on a physical Apple TV; only
    // Library/Caches and tmp are writable there. See path_provider_tvos's
    // PathProviderPlugin.swift for the on-device sandbox measurements.
    final dir = await getApplicationCacheDirectory();
    // MediaImageCacheManager's flutter_cache_manager Config has no explicit
    // `repo`, so on tvOS (not Android/iOS/macOS by flutter_cache_manager's
    // own platform check) it defaults to JsonCacheInfoRepository, which
    // lazily resolves its storage directory via getApplicationSupportDirectory
    // - a directory that cannot be created on a physical Apple TV. That threw
    // on every image cache write, so posters/logos silently failed to load on
    // device while working fine in the simulator. Resolving Caches here,
    // before any image widget builds, lets the manager use a writable
    // directory instead.
    MediaImageCacheManager.tvosCacheDirectory = dir;
    return PersistentJsonStore(file: File('${dir.path}/app_state.json'));
  }
  if (operatingSystem == 'android' || operatingSystem == 'ios') {
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
          child: _TvZoom(
            deviceType: deviceType,
            child: child ?? const SizedBox.shrink(),
          ),
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

/// Renders the app on a smaller virtual canvas and stretches it to fill the
/// real screen, so text/icons/nav read clearly from a couch-length distance.
/// TV-only: on the couch, physical viewing distance is far larger than a
/// desktop/tablet/phone, so the same logical layout reads too small.
class _TvZoom extends StatelessWidget {
  const _TvZoom({required this.deviceType, required this.child});

  static const double _scale = 1.6;

  final DeviceType deviceType;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (deviceType != DeviceType.tv) return child;

    final mediaQuery = MediaQuery.of(context);
    final realSize = mediaQuery.size;
    final virtualSize = realSize / _scale;

    return SizedBox.fromSize(
      size: realSize,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox.fromSize(
          size: virtualSize,
          child: MediaQuery(
            // padding/viewPadding/viewInsets/systemGestureInsets are all
            // calibrated for the real screen -- FittedBox stretches the
            // virtual canvas back up by _scale, so anything computed from
            // these in the virtual coordinate space (SafeArea, manual
            // Positioned offsets) must divide by _scale too, or it consumes
            // a _scale-times-too-large share of the smaller virtual canvas.
            data: mediaQuery.copyWith(
              size: virtualSize,
              padding: mediaQuery.padding / _scale,
              viewPadding: mediaQuery.viewPadding / _scale,
              viewInsets: mediaQuery.viewInsets / _scale,
              systemGestureInsets: mediaQuery.systemGestureInsets / _scale,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
