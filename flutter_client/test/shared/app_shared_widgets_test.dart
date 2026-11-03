import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/app_alert_dialog.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_menu_dialog.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:m3u_tv/shared/app_top_bar.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('AppTopBar is an AppBar with the app back button', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppTopBar(
            title: const Text('Page'),
            scale: 1.5,
            onBack: () => backs++,
          ),
        ),
      ),
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 84);
    await tester.tap(find.byType(AppIconButton));
    expect(backs, 1);
  });

  testWidgets('AppAlertDialog lays its actions out as AppButtons', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _host(
        AppAlertDialog(
          title: 'Delete?',
          message: 'Gone for good.',
          actions: [
            AppDialogAction(label: 'Cancel', onPressed: () => picked = 'no'),
            AppDialogAction(
              label: 'Delete',
              variant: AppButtonVariant.destructive,
              onPressed: () => picked = 'yes',
            ),
          ],
        ),
      ),
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Gone for good.'), findsOneWidget);
    expect(find.byType(AppButton), findsNWidgets(2));
    await tester.tap(find.text('Delete'));
    expect(picked, 'yes');
  });

  testWidgets('AppMenuDialog is a SimpleDialog of AppMenuOptions', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppMenuDialog(
          title: const Text('Channel'),
          children: [
            AppMenuOption(
              icon: Icons.star,
              label: 'Favorite',
              subtitle: 'Pin to the top',
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.text('Pin to the top'), findsOneWidget);
    await tester.tap(find.text('Favorite'));
    expect(taps, 1);
  });

  testWidgets('AppSwitch and AppLoadingIndicator wrap the Material controls', (
    tester,
  ) async {
    bool? changedTo;
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSwitch(value: false, onChanged: (v) => changedTo = v),
            const AppLoadingIndicator(strokeWidth: 2),
          ],
        ),
      ),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .strokeWidth,
      2,
    );
    await tester.tap(find.byType(Switch));
    expect(changedTo, isTrue);
  });

  testWidgets('appPageRoute slides an opaque page in from the right', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            homeContext = context;
            return const Text('Home');
          },
        ),
      ),
    );
    Navigator.of(
      homeContext,
    ).push(appPageRoute<void>(builder: (context) => const Text('Detail')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.text('Detail'),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    expect(slide.position.value.dx, greaterThan(0));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == kAppPageBackground,
      ),
      findsOneWidget,
    );
  });

  testWidgets('showAppDialog and showAppModalSheet open their builders', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    showAppDialog<void>(context: context, builder: (_) => const Text('Dlg'));
    await tester.pumpAndSettle();
    expect(find.text('Dlg'), findsOneWidget);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();

    showAppModalSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const Text('Sheet'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);
  });
}
