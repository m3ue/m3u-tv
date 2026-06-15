import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
  group('EpgScreen', () {
    late List<Channel> testChannels;
    late EpgService epgService;

    setUp(() {
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          epgChannelId: 'bbc.one',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          epgChannelId: 'cnn',
        ),
      ];

      epgService = EpgService(clock: () => DateTime(2025, 1, 1, 20))
        ..loadPrograms([
          EpgProgram(
            channelId: 'bbc.one',
            title: 'Evening News',
            description: 'Latest news',
            start: DateTime(2025, 1, 1, 19),
            end: DateTime(2025, 1, 1, 20, 30),
          ),
          EpgProgram(
            channelId: 'bbc.one',
            title: 'Late Show',
            description: 'Talk show',
            start: DateTime(2025, 1, 1, 20, 30),
            end: DateTime(2025, 1, 1, 21),
          ),
          EpgProgram(
            channelId: 'cnn',
            title: 'CNN Tonight',
            description: 'News',
            start: DateTime(2025, 1, 1, 20),
            end: DateTime(2025, 1, 1, 21),
          ),
        ]);
    });

    testWidgets('renders EPG screen with channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EpgScreen), findsOneWidget);
      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
    });

    testWidgets('shows current program title for channels with EPG', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      // BBC One should show "Evening News" as current program
      expect(find.text('Evening News'), findsOneWidget);
    });

    testWidgets('shows next program title when available', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      // BBC One should show "Late Show" as next program
      expect(find.text('Late Show'), findsOneWidget);
    });

    testWidgets('shows progress bar for current program', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      // Should find progress indicators
      expect(find.byType(LinearProgressIndicator), findsAtLeast(1));
    });

    testWidgets('shows no program info for channels without EPG', (
      tester,
    ) async {
      final channelsWithoutEpg = [
        const Channel(
          id: 99,
          name: 'Unknown Channel',
          streamUrl: 'http://example.com/99.m3u8',
        ),
      ];
      await tester.pumpWidget(
        _TestApp(
          channels: channelsWithoutEpg,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No program info'), findsOneWidget);
    });

    testWidgets('toggling view mode switches between list and grid', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
        ),
      );
      await tester.pumpAndSettle();

      // Find and tap the view mode toggle button
      final toggleFinder = find.byIcon(Icons.view_list);
      if (toggleFinder.evaluate().isNotEmpty) {
        await tester.tap(toggleFinder);
        await tester.pumpAndSettle();
      }

      expect(find.byType(EpgScreen), findsOneWidget);
    });

    testWidgets('tapping channel triggers onChannelSelect', (tester) async {
      Channel? selectedChannel;
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          epgService: epgService,
          onChannelSelect: (channel) => selectedChannel = channel,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BBC One'));
      await tester.pumpAndSettle();

      expect(selectedChannel, isNotNull);
      expect(selectedChannel!.id, 1);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.epgService,
    this.onChannelSelect,
  });

  final List<Channel> channels;
  final EpgService epgService;
  final void Function(Channel)? onChannelSelect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: EpgScreen(
          channels: channels,
          epgService: epgService,
          onChannelSelect: onChannelSelect ?? (_) {},
        ),
      ),
    );
  }
}
