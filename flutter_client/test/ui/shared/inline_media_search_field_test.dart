import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

void main() {
  testWidgets(
    'InlineMediaSearchField Clear button works after d-pad navigating '
    'onto it from the TextField',
    (tester) async {
      var query = 'abc';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                body: InlineMediaSearchField(
                  query: query,
                  onChanged: (value) => setState(() => query = value),
                  activateOnSelect: true,
                  autofocus: true,
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Facade is focused; select opens the real editing TextField+Clear
      // button row.
      expect(find.byType(TextField), findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // D-pad from the TextField onto the adjacent Clear button. Left/Right
      // are consumed by EditableText for cursor movement, so Down is the
      // dedicated escape hatch to the Clear button (see _handleEditingKey).
      // Before the fix, any focus move off the TextField's own node -
      // including onto this sibling button - collapsed the field back to
      // its inactive facade and tore the Clear button down before Select
      // could reach it.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason:
            'navigating onto the Clear button must not deactivate the '
            'field',
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(query, '');
    },
  );

  testWidgets(
    'InlineMediaSearchField Escape deactivates the field while the Clear '
    'button has focus, not just the TextField',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: InlineMediaSearchField(
              query: 'abc',
              onChanged: (_) {},
              activateOnSelect: true,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.clear), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('abc'), findsOneWidget);
    },
  );

  testWidgets(
    'InlineMediaSearchField Clear button works on a mouse click, not just a '
    'synthetic tap',
    (tester) async {
      var query = 'abc';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData.dark(useMaterial3: true),
              home: Scaffold(
                body: InlineMediaSearchField(
                  query: query,
                  onChanged: (value) => setState(() => query = value),
                  activateOnSelect: true,
                  autofocus: true,
                ),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.clear), findsOneWidget);

      // A real mouse click is a separate pointer-down then pointer-up, with
      // a rebuild able to happen in between - unlike tester.tap(), which
      // synthesizes both as one atomic call and does not reproduce this bug.
      // TextField's default onTapOutside unfocuses on mouse pointer-down for
      // any point outside itself, including this sibling Clear button.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.clear)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(
        find.byIcon(Icons.clear),
        findsOneWidget,
        reason:
            'mouse pointer-down on Clear must not deactivate the field '
            'before pointer-up',
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(query, '');
    },
  );
}
