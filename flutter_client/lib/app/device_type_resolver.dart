import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:m3u_tv/app/app_shell.dart';

const MethodChannel _deviceInfoChannel = MethodChannel('m3u_tv/device_info');

Future<bool> resolveNativeTelevisionHint({
  MethodChannel channel = _deviceInfoChannel,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) return false;

  try {
    return await channel.invokeMethod<bool>('isTelevision') ?? false;
  } on MissingPluginException {
    return false;
  }
}

DeviceType resolveDeviceType(
  BuildContext context, {
  bool nativeTelevisionHint = false,
}) {
  return deviceTypeForView(
    platform: defaultTargetPlatform,
    size: MediaQuery.sizeOf(context),
    navigationMode:
        MediaQuery.maybeNavigationModeOf(context) ?? NavigationMode.traditional,
    nativeTelevisionHint: nativeTelevisionHint,
  );
}

DeviceType deviceTypeForView({
  required TargetPlatform platform,
  required Size size,
  required NavigationMode navigationMode,
  bool nativeTelevisionHint = false,
}) {
  if (nativeTelevisionHint) {
    return DeviceType.tv;
  }

  // tvOS reports TargetPlatform.iOS at the Dart level; detect it by OS name.
  if (!kIsWeb && Platform.operatingSystem == 'tvos') {
    return DeviceType.tv;
  }

  if (navigationMode == NavigationMode.directional) {
    return DeviceType.tv;
  }

  return switch (platform) {
    TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia =>
      size.shortestSide >= 600 ? DeviceType.tablet : DeviceType.phone,
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => DeviceType.desktop,
  };
}
