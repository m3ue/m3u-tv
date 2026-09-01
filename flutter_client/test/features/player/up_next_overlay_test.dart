import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/up_next_overlay.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('renders the episode title, subtitle and plot', (tester) async {
    await tester.pumpWidget(
      _host(
        UpNextOverlay(
          eyebrowLabel: 'Up next',
          title: 'The One After',
          subtitle: 'S2 · E1',
          plot: 'A brand new chapter begins.',
          playLabel: 'Play next',
          dismissLabel: 'Dismiss',
          onPlay: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.text('The One After'), findsOneWidget);
    expect(find.text('S2 · E1'), findsOneWidget);
    expect(find.text('A brand new chapter begins.'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget); // eyebrow is upper-cased
  });

  testWidgets('Play and Dismiss fire their callbacks', (tester) async {
    var played = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _host(
        UpNextOverlay(
          eyebrowLabel: 'Up next',
          title: 'Next',
          playLabel: 'Play next',
          dismissLabel: 'Dismiss',
          onPlay: () => played++,
          onDismiss: () => dismissed++,
        ),
      ),
    );

    await tester.tap(find.text('Play next'));
    await tester.tap(find.text('Dismiss'));
    await tester.pump();

    expect(played, 1);
    expect(dismissed, 1);
  });

  testWidgets('play button adopts the supplied focus node', (tester) async {
    final node = FocusNode(debugLabel: 'upNextPlay');
    addTearDown(node.dispose);

    await tester.pumpWidget(
      _host(
        UpNextOverlay(
          eyebrowLabel: 'Up next',
          title: 'Next',
          playLabel: 'Play next',
          dismissLabel: 'Dismiss',
          playFocusNode: node,
          onPlay: () {},
          onDismiss: () {},
        ),
      ),
    );

    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
