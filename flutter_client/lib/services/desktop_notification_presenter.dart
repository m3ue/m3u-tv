import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

typedef DesktopNotificationActivation =
    Future<void> Function(String notificationId);

abstract interface class DesktopNotificationPresenter {
  Future<void> initialize({
    required String defaultActionName,
    required DesktopNotificationActivation onActivation,
  });

  Future<bool> present(TvNotificationItem item);

  void dispose();
}

abstract interface class DesktopNotificationBackend {
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  });

  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  });
}

class NativeDesktopNotificationPresenter
    implements DesktopNotificationPresenter {
  factory NativeDesktopNotificationPresenter({
    String? operatingSystem,
    DesktopNotificationBackend? backend,
  }) {
    final resolvedOperatingSystem = operatingSystem ?? _currentOperatingSystem;
    return NativeDesktopNotificationPresenter._(
      operatingSystem: resolvedOperatingSystem,
      backend: backend ?? _defaultBackend(resolvedOperatingSystem),
    );
  }

  NativeDesktopNotificationPresenter._({
    required this._operatingSystem,
    required this._backend,
  });

  static const _maxHandledIds = 500;

  final String _operatingSystem;
  final DesktopNotificationBackend _backend;
  final Queue<String> _handledIdOrder = Queue<String>();
  final Set<String> _handledIds = <String>{};
  Future<bool>? _initialization;
  String? _initializedActionName;
  bool _disposed = false;

  bool get _isSupported =>
      _operatingSystem == 'linux' ||
      _operatingSystem == 'windows' ||
      _operatingSystem == 'macos';

  @override
  Future<void> initialize({
    required String defaultActionName,
    required DesktopNotificationActivation onActivation,
  }) async {
    if (!_isSupported || _disposed) return;
    if (_initialization != null &&
        _initializedActionName == defaultActionName) {
      await _initialization;
      return;
    }
    _initializedActionName = defaultActionName;
    _initialization = _initialize(
      defaultActionName: defaultActionName,
      onActivation: onActivation,
    );
    await _initialization;
  }

  Future<bool> _initialize({
    required String defaultActionName,
    required DesktopNotificationActivation onActivation,
  }) async {
    try {
      await _backend.initialize(
        defaultActionName: defaultActionName,
        onActivation: (payload) {
          if (_disposed) return;
          final id = canonicalNotificationId(payload);
          if (id != null) unawaited(onActivation(id));
        },
      );
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  @override
  Future<bool> present(TvNotificationItem item) async {
    if (!_isSupported || _disposed) return false;
    final initialization = _initialization;
    if (initialization == null || !await initialization) return false;
    if (_disposed) return false;
    if (!_handledIds.add(item.id)) return true;
    _handledIdOrder.addLast(item.id);
    if (_handledIdOrder.length > _maxHandledIds) {
      _handledIds.remove(_handledIdOrder.removeFirst());
    }
    try {
      await _backend.show(
        id: desktopNotificationId(item.id),
        title: item.title,
        body: item.body,
        payload: item.id,
      );
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
  }
}

class DesktopNotificationDispatcher {
  DesktopNotificationDispatcher({
    required this.presenter,
    required this.onFallback,
  });

  final DesktopNotificationPresenter presenter;
  final void Function(TvNotificationItem item) onFallback;

  Future<void> initialize({
    required String defaultActionName,
    required DesktopNotificationActivation onActivation,
  }) => presenter.initialize(
    defaultActionName: defaultActionName,
    onActivation: onActivation,
  );

  Future<void> dispatch(TvNotificationItem item) async {
    if (!await presenter.present(item)) onFallback(item);
  }

  void dispose() => presenter.dispose();
}

class LinuxDesktopNotificationBackend implements DesktopNotificationBackend {
  LinuxDesktopNotificationBackend({
    LinuxFlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? LinuxFlutterLocalNotificationsPlugin();

  final LinuxFlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  }) async {
    final initialized = await _plugin.initialize(
      settings: LinuxInitializationSettings(
        defaultActionName: defaultActionName,
      ),
      onDidReceiveNotificationResponse: (response) {
        onActivation(response.payload);
      },
    );
    if (initialized == false) {
      throw StateError('Linux notification initialization failed');
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  }) => _plugin.show(id: id, title: title, body: body, payload: payload);
}

class WindowsDesktopNotificationBackend implements DesktopNotificationBackend {
  WindowsDesktopNotificationBackend({FlutterLocalNotificationsWindows? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsWindows();

  static const _windowsSettings = WindowsInitializationSettings(
    appName: 'M3U TV',
    appUserModelId: 'dev.sparkison.tv',
    guid: '6d47bd72-7948-4e9a-977b-2df18d38ab8c',
  );

  final FlutterLocalNotificationsWindows _plugin;

  @override
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  }) async {
    final initialized = await _plugin.initialize(
      settings: _windowsSettings,
      onDidReceiveNotificationResponse: (response) {
        onActivation(response.payload);
      },
    );
    if (!initialized) {
      throw StateError('Windows notification initialization failed');
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  }) => _plugin.show(id: id, title: title, body: body, payload: payload);
}

class MacosDesktopNotificationBackend implements DesktopNotificationBackend {
  MacosDesktopNotificationBackend({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _macosSettings = InitializationSettings(
    macOS: DarwinInitializationSettings(),
  );

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  }) async {
    final initialized = await _plugin.initialize(
      settings: _macosSettings,
      onDidReceiveNotificationResponse: (response) {
        onActivation(response.payload);
      },
    );
    if (initialized == false) {
      throw StateError('macOS notification initialization failed');
    }
    // macOS silently drops notifications when the app lacks permission (common
    // for a dev-signed build, Focus mode, or a denied prompt). Treat that as an
    // init failure so the dispatcher falls back to the in-app toast instead of
    // showing nothing.
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    if (granted != true) {
      throw StateError('macOS notification permission not granted');
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      macOS: DarwinNotificationDetails(),
    ),
    payload: payload,
  );
}

DesktopNotificationBackend _defaultBackend(String operatingSystem) =>
    switch (operatingSystem) {
      'linux' => LinuxDesktopNotificationBackend(),
      'windows' => WindowsDesktopNotificationBackend(),
      'macos' => MacosDesktopNotificationBackend(),
      _ => _UnsupportedDesktopNotificationBackend(),
    };

class _UnsupportedDesktopNotificationBackend
    implements DesktopNotificationBackend {
  @override
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  }) => Future<void>.error(UnsupportedError('Desktop notifications'));

  @override
  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  }) => Future<void>.error(UnsupportedError('Desktop notifications'));
}

int desktopNotificationId(String canonicalId) {
  final value = BigInt.parse(canonicalId.replaceAll('-', ''), radix: 16);
  final folded = (value ^ (value >> 64)) & BigInt.from(0x7fffffff);
  return folded.toInt();
}

String get _currentOperatingSystem {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.windows => 'windows',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}
