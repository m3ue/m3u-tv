import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/resume_modal.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// Pumps a host with a button that opens the resume modal and records its
/// result. Returns a getter for the captured result (null until the modal is
/// dismissed).
Future<ResumeModalResult? Function()> _host(
  WidgetTester tester, {
  required bool showManageActions,
}) async {
  ResumeModalResult? captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showResumeModal(
                  context,
                  title: 'Murderbot - S1E4',
                  positionSeconds: 120,
                  showManageActions: showManageActions,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => captured;
}

void main() {
  testWidgets(
    'offers Clear progress and Mark watched when managing is enabled',
    (
      tester,
    ) async {
      await _host(tester, showManageActions: true);

      expect(find.text('Resume Watching'), findsOneWidget);
      expect(find.text('Start from Beginning'), findsOneWidget);
      expect(find.text('Clear progress'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
    },
  );

  testWidgets('hides the manage actions by default', (tester) async {
    await _host(tester, showManageActions: false);

    expect(find.text('Start from Beginning'), findsOneWidget);
    expect(find.text('Clear progress'), findsNothing);
    expect(find.text('Mark watched'), findsNothing);
  });

  testWidgets('Clear progress resolves with the clearProgress action', (
    tester,
  ) async {
    final result = await _host(tester, showManageActions: true);

    await tester.tap(find.text('Clear progress'));
    await tester.pumpAndSettle();

    expect(result()?.action, ResumeAction.clearProgress);
    expect(result()?.startPositionSeconds, 0);
  });

  testWidgets('Mark watched resolves with the markWatched action', (
    tester,
  ) async {
    final result = await _host(tester, showManageActions: true);

    await tester.tap(find.text('Mark watched'));
    await tester.pumpAndSettle();

    expect(result()?.action, ResumeAction.markWatched);
  });

  testWidgets('Start from Beginning resolves with the startOver action', (
    tester,
  ) async {
    final result = await _host(tester, showManageActions: true);

    await tester.tap(find.text('Start from Beginning'));
    await tester.pumpAndSettle();

    expect(result()?.action, ResumeAction.startOver);
  });
}
