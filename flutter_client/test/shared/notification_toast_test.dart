import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/shared/notification_toast.dart';

void main() {
  const item = TvNotificationItem(
    id: 'toast-1',
    channel: 'general',
    title: 'Hello',
    status: 'info',
  );

  Future<void> pump(WidgetTester tester, {required bool swipeToDismiss}) {
    return tester.pumpWidget(
      MaterialApp(
        home: NotificationToastOverlay(
          swipeToDismiss: swipeToDismiss,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  testWidgets(
    'swiping the toast down dismisses it when swipeToDismiss is true',
    (
      tester,
    ) async {
      await pump(tester, swipeToDismiss: true);
      final key =
          find.byType(NotificationToastOverlay).evaluate().single.widget
              as NotificationToastOverlay;
      tester
          .state<NotificationToastOverlayState>(
            find.byWidget(key),
          )
          .enqueue(item);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Hello'), findsOneWidget);

      await tester.drag(find.text('Hello'), const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(find.text('Hello'), findsNothing);
    },
  );

  testWidgets('swipe down does not dismiss when swipeToDismiss is false', (
    tester,
  ) async {
    await pump(tester, swipeToDismiss: false);
    final key =
        find.byType(NotificationToastOverlay).evaluate().single.widget
            as NotificationToastOverlay;
    tester
        .state<NotificationToastOverlayState>(
          find.byWidget(key),
        )
        .enqueue(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(find.text('Hello'), const Offset(0, 300));
    await tester.pump();

    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('toast stack steps above a showing snackbar', (tester) async {
    final scaffoldKey = GlobalKey();
    final overlayKey = GlobalKey<NotificationToastOverlayState>();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SnackBarTrackingMessenger(child: child!),
        home: NotificationToastOverlay(
          key: overlayKey,
          child: Scaffold(key: scaffoldKey, body: const SizedBox.expand()),
        ),
      ),
    );
    overlayKey.currentState!.enqueue(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final restingBottom = tester.getBottomLeft(find.text('Hello')).dy;

    final controller = ScaffoldMessenger.of(
      scaffoldKey.currentContext!,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Hello')).dy,
      lessThan(restingBottom),
    );
    expect(
      tester.getBottomLeft(find.text('Hello')).dy,
      lessThan(tester.getTopLeft(find.text('Saved')).dy),
    );

    controller.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // `closed` completes after the hide animation; the stack then slides back
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getBottomLeft(find.text('Hello')).dy, restingBottom);
  });
}
