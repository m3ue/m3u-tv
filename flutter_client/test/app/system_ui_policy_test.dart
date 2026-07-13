import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';

void main() {
  test('startup browsing policy keeps system bars available', () async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );

    await policy.applyBrowsing();

    expect(modes, <SystemUiRouteMode>[SystemUiRouteMode.browsing]);
  });

  test('player policy enters immersive fullscreen', () async {
    final modes = <SystemUiRouteMode>[];
    final policy = SystemUiPolicy(
      isAndroid: true,
      applySystemUiRouteMode: (mode) async => modes.add(mode),
    );

    await policy.applyPlayer();

    expect(modes, <SystemUiRouteMode>[SystemUiRouteMode.player]);
  });
}
