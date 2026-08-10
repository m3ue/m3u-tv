import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/features/epg/program_recording_indicator.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  group('ProgramRecordingIndicator', () {
    testWidgets('scheduled renders schedule icon with scheduled label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ProgramRecordingIndicator(state: EpgRecordingState.scheduled),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );

      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(
        find.bySemanticsLabel(l10n.epgProgramScheduledToRecord),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    });

    testWidgets('recording renders record icon with recording label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ProgramRecordingIndicator(state: EpgRecordingState.recording),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );

      expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
      expect(
        find.bySemanticsLabel(l10n.epgProgramCurrentlyRecording),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('none renders nothing and reports zero size', (tester) async {
      await tester.pumpWidget(
        host(const ProgramRecordingIndicator(state: EpgRecordingState.none)),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold)),
      );

      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
      expect(
        find.bySemanticsLabel(l10n.epgProgramScheduledToRecord),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(l10n.epgProgramCurrentlyRecording),
        findsNothing,
      );
      expect(
        tester.getSize(find.byType(ProgramRecordingIndicator)),
        Size.zero,
      );
    });
  });
}
