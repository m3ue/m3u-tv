import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/notifications/notifications_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:material_ui/material_ui.dart';

Widget _screen(AppUpdateNotice? notice, {Future<void> Function()? onRead}) =>
    ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => true),
        notificationStoreProvider.overrideWith((_) => TvNotificationStore()),
        tvNotificationsStreamProvider.overrideWith(
          (_) => const Stream<TvNotificationItem>.empty(),
        ),
        appUpdateNoticeProvider.overrideWith((_) => notice),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NotificationsScreen(
          onMarkRead: (_) async {},
          onMarkAllRead: () async {},
          onSetChannels: (_) async {},
          onMarkAppUpdateRead: onRead,
        ),
      ),
    );

void main() {
  testWidgets('pins an unread app update above notifications', (
    tester,
  ) async {
    var markedRead = false;
    await tester.pumpWidget(
      _screen(
        const AppUpdateNotice(version: '9.9.9', isRead: false),
        onRead: () async => markedRead = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('App update available'), findsOneWidget);
    expect(find.text('Version 9.9.9 is ready to install.'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);
    expect(find.text('No notifications yet'), findsNothing);

    await tester.tap(find.text('App update available'));
    expect(markedRead, isTrue);
  });

  testWidgets('shows no update tile when up to date', (tester) async {
    await tester.pumpWidget(_screen(null));
    await tester.pumpAndSettle();

    expect(find.text('App update available'), findsNothing);
  });
}
