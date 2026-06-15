import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:m3u_tv/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches the Flutter client shell', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('M3U TV'), findsOneWidget);
    expect(find.text('Flutter rewrite foundation ready'), findsOneWidget);
  });
}
