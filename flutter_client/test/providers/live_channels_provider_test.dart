import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';

void main() {
  group('liveChannelsProvider (bridge)', () {
    test('reflects channels list from AppStateController synchronously', () {
      final controller = AppStateController();
      final container = ProviderContainer(
        overrides: [overrideAppState(controller)],
      );
      addTearDown(container.dispose);
      addTearDown(controller.dispose);

      expect(container.read(liveChannelsProvider), isEmpty);
    });
  });
}
