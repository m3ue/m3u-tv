import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_screen.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

class _RecordingWakelock implements WakelockController {
  final List<String> calls = <String>[];

  @override
  Future<void> enable() async => calls.add('enable');

  @override
  Future<void> disable() async => calls.add('disable');
}

void main() {
  testWidgets('Multiview holds the wakelock for as long as it is on screen', (
    tester,
  ) async {
    final wakelock = _RecordingWakelock();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No tiles, so no native players are needed: this only exercises
          // the screen's own lifecycle.
          multiviewChannelsProvider.overrideWith((_) => const <Channel>[]),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiviewScreen(wakelockController: wakelock),
        ),
      ),
    );
    await tester.pump();

    expect(wakelock.calls, ['enable']);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(wakelock.calls, ['enable', 'disable']);
  });
}
