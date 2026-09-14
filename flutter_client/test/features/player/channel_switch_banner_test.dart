import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/channel_switch_banner.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';

const _cnn = Channel(
  id: 1,
  name: 'CNN',
  streamUrl: 'https://example.com/cnn.m3u8',
);

const _espn = Channel(
  id: 2,
  name: 'ESPN',
  streamUrl: 'https://example.com/espn.m3u8',
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('renders the channel name', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChannelSwitchBanner(
          channel: _cnn,
          direction: ChannelSwitchDirection.up,
        ),
      ),
    );

    expect(find.text('CNN'), findsOneWidget);
  });

  testWidgets('up direction draws the keyboard_arrow_up icon', (tester) async {
    await tester.pumpWidget(
      _host(
        const ChannelSwitchBanner(
          channel: _cnn,
          direction: ChannelSwitchDirection.up,
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
  });

  testWidgets('down direction draws the keyboard_arrow_down icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ChannelSwitchBanner(
          channel: _espn,
          direction: ChannelSwitchDirection.down,
        ),
      ),
    );

    expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up), findsNothing);
  });

  testWidgets('does not steal focus from siblings', (tester) async {
    final node = FocusNode(debugLabel: 'bannerHost');
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Focus(
              focusNode: node,
              autofocus: true,
              child: const ChannelSwitchBanner(
                channel: _cnn,
                direction: ChannelSwitchDirection.up,
              ),
            ),
          ),
        ),
      ),
    );

    expect(node.hasFocus, isTrue);
  });
}
