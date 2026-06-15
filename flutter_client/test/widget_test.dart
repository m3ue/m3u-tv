import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/main.dart';

void main() {
  testWidgets('renders the app shell', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    // The app shell should render with the Home placeholder
    expect(find.text('Home'), findsAtLeast(1));
  });
}
