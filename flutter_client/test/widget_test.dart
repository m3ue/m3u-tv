import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/main.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';

void main() {
  testWidgets('renders the app shell', (tester) async {
    final appState = AppStateController();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [overrideAppState(appState)],
        child: MyApp(appState: appState),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('Home'), findsAtLeast(1));
  });
}
