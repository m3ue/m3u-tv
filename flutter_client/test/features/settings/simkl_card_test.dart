import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/simkl_card.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/simkl_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  SimklService service({SimklTransport? transport, String clientId = 'id'}) {
    final simkl = SimklService(
      storage: InMemorySecureStorage(),
      clientId: clientId,
      transport: transport ?? (_) async => const SimklResponse(200, {}),
    );
    addTearDown(simkl.dispose);
    return simkl;
  }

  Future<AppLocalizations> pump(
    WidgetTester tester,
    SimklService simkl, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ListenableBuilder(
            listenable: simkl,
            builder: (_, _) => SimklCard(simklService: simkl),
          ),
        ),
      ),
    );
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(SimklCard)));
  }

  Future<SimklResponse> deviceCode(SimklRequest _) async => const SimklResponse(
    200,
    {
      'device_code': 'device-secret',
      'user_code': 'BDWP-HQPK',
      'verification_uri': 'https://simkl.com/pin',
      'verification_uri_complete': 'https://simkl.com/pin?user_code=BDWP-HQPK',
      'expires_in': 900,
      'interval': 3600,
    },
  );

  testWidgets('explains itself without a client id', (tester) async {
    final simkl = service(clientId: '');
    final l = await pump(tester, simkl);

    expect(find.text(l.simklNotConfigured), findsOneWidget);
    expect(find.text(l.simklConnectButton), findsNothing);
  });

  testWidgets('offers to connect', (tester) async {
    final simkl = service();
    final l = await pump(tester, simkl);

    expect(find.text(l.simklName), findsOneWidget);
    expect(find.byKey(const ValueKey('simkl-logo')), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text(l.simklConnectPrompt), findsOneWidget);
    expect(find.text(l.simklConnectButton), findsOneWidget);
  });

  for (final size in const [Size(1280, 720), Size(360, 700)]) {
    testWidgets('shows the code without overflowing at $size', (tester) async {
      final simkl = service(transport: deviceCode);
      await simkl.startDeviceAuth();
      await pump(tester, simkl, size: size);

      expect(tester.takeException(), isNull);
      expect(find.text('BDWP-HQPK'), findsOneWidget);
      expect(find.text('https://simkl.com/pin'), findsOneWidget);
      expect(find.text('device-secret'), findsNothing);
      expect(
        find.byType(QrImageView),
        size.width >= 600 ? findsOneWidget : findsNothing,
      );

      simkl.cancelAuth();
    });
  }

  testWidgets('cancel returns to the connect button', (tester) async {
    final simkl = service(transport: deviceCode);
    await simkl.startDeviceAuth();
    final l = await pump(tester, simkl);

    await tester.tap(find.text(l.cancel));
    await tester.pump();

    expect(simkl.status, SimklAuthStatus.disconnected);
    expect(find.text(l.simklConnectButton), findsOneWidget);
  });

  testWidgets('connected shows the account state and disconnects', (
    tester,
  ) async {
    final storage = InMemorySecureStorage();
    await storage.write('simkl_access_token', 'simkl_at');
    await storage.write(
      'simkl_token_expiry',
      '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}',
    );
    final simkl = SimklService(
      storage: storage,
      clientId: 'id',
      transport: (_) async => const SimklResponse(200, {}),
    );
    addTearDown(simkl.dispose);
    await simkl.init();
    final l = await pump(tester, simkl);

    expect(find.text(l.simklConnected), findsOneWidget);

    await tester.tap(find.text(l.simklDisconnectButton));
    await tester.pump();

    expect(simkl.isConnected, isFalse);
    expect(find.text(l.simklConnectButton), findsOneWidget);
  });
}
