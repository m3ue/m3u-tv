import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/desktop_back_key.dart';
import 'package:material_ui/material_ui.dart';

class _BackIntent extends Intent {
  const _BackIntent();
}

void main() {
  // Test hosts are desktops, so HostPlatform.isDesktop holds here.
  Future<ValueNotifier<int>> pumpPage(
    WidgetTester tester, {
    TextEditingController? field,
  }) async {
    final backs = ValueNotifier<int>(0);
    addTearDown(backs.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            DesktopBackspaceActivator(): _BackIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  backs.value++;
                  return null;
                },
              ),
            },
            child: Scaffold(
              body: field != null
                  ? TextField(controller: field, autofocus: true)
                  : const Focus(autofocus: true, child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return backs;
  }

  testWidgets('Backspace goes back outside a text field', (tester) async {
    final backs = await pumpPage(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);

    expect(backs.value, 1);
  });

  testWidgets('Backspace still deletes in a text field', (tester) async {
    final field = TextEditingController(text: 'abc');
    addTearDown(field.dispose);
    final backs = await pumpPage(tester, field: field);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(backs.value, 0);
    expect(field.text, 'ab');
  });

  testWidgets('a held or modified Backspace does not go back', (tester) async {
    final backs = await pumpPage(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
    expect(backs.value, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    expect(backs.value, 1);
  });

  testWidgets('Backspace closes a dialog through the app-wide binding', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: <ShortcutActivator, Intent>{
          ...WidgetsApp.defaultShortcuts,
          const DesktopBackspaceActivator(): const DismissIntent(),
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(
                  content: Focus(autofocus: true, child: Text('Dialog')),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    expect(find.text('Dialog'), findsNothing);
  });
}
