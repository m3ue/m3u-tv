import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/app_shell.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';

void main() {
  group('deviceTypeForView', () {
    test('uses phone layout for Android handsets', () {
      expect(
        deviceTypeForView(
          platform: TargetPlatform.android,
          size: const Size(393, 852),
          navigationMode: NavigationMode.traditional,
        ),
        DeviceType.phone,
      );
    });

    test('uses tablet layout for mobile platforms with tablet width', () {
      expect(
        deviceTypeForView(
          platform: TargetPlatform.iOS,
          size: const Size(820, 1180),
          navigationMode: NavigationMode.traditional,
        ),
        DeviceType.tablet,
      );
    });

    test('uses sidebar layout for directional TV navigation', () {
      expect(
        deviceTypeForView(
          platform: TargetPlatform.android,
          size: const Size(1920, 1080),
          navigationMode: NavigationMode.directional,
        ),
        DeviceType.tv,
      );
    });

    test('uses sidebar layout for native Android TV hint', () {
      expect(
        deviceTypeForView(
          platform: TargetPlatform.android,
          size: const Size(1920, 1080),
          navigationMode: NavigationMode.traditional,
          nativeTelevisionHint: true,
        ),
        DeviceType.tv,
      );
    });

    test('uses desktop layout for desktop platforms', () {
      expect(
        deviceTypeForView(
          platform: TargetPlatform.linux,
          size: const Size(1440, 900),
          navigationMode: NavigationMode.traditional,
        ),
        DeviceType.desktop,
      );
    });
  });
}
