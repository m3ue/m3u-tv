import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/backend_capabilities.dart';
import 'package:m3u_tv/features/settings/connection_form.dart';
import 'package:m3u_tv/features/settings/diagnostics_screen.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/features/settings/viewer_selector.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/device_pairing_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  // --- SecureStorage ---

  group('SecureStorage', () {
    test('InMemorySecureStorage stores and retrieves credentials', () async {
      final storage = InMemorySecureStorage();
      await storage.write(
        'm3ue_tv_credentials',
        '{"server":"http://x.com","username":"u","password":"p"}',
      );
      expect(await storage.read('m3ue_tv_credentials'), isNotNull);
    });

    test('InMemorySecureStorage returns null for missing key', () async {
      final storage = InMemorySecureStorage();
      expect(await storage.read('nonexistent'), isNull);
    });

    test('InMemorySecureStorage deletes credentials', () async {
      final storage = InMemorySecureStorage();
      await storage.write('m3ue_tv_credentials', 'test');
      await storage.delete('m3ue_tv_credentials');
      expect(await storage.read('m3ue_tv_credentials'), isNull);
    });

    test('InMemorySecureStorage does not log passwords', () async {
      final storage = InMemorySecureStorage();
      await storage.write('m3ue_tv_credentials', '{"password":"secret123"}');
      // Verify the stored value is present but not in any log
      expect(
        await storage.read('m3ue_tv_credentials'),
        '{"password":"secret123"}',
      );
      // InMemorySecureStorage should not expose values through toString
      expect(storage.toString(), isNot(contains('secret123')));
    });
  });

  // --- AuthNotifier ---

  group('AuthNotifier', () {
    test('initial state is unconfigured', () {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );
      expect(notifier.isConfigured, isFalse);
      expect(notifier.authResponse, isNull);
      expect(notifier.error, isNull);
    });

    test('connect with valid credentials sets isConfigured', () async {
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: InMemorySecureStorage(),
      );

      final result = await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'u',
          password: 'p',
        ),
      );

      expect(result, isTrue);
      expect(notifier.isConfigured, isTrue);
      expect(notifier.authResponse, isNotNull);
      expect(notifier.authResponse!.isAuthenticated, isTrue);
    });

    test('connect with invalid credentials sets error', () async {
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 0, status: 'Invalid credentials'),
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: InMemorySecureStorage(),
      );

      final result = await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'u',
          password: 'wrong',
        ),
      );

      expect(result, isFalse);
      expect(notifier.isConfigured, isFalse);
      expect(notifier.error, isNotNull);
    });

    test('connect with expired credentials sets expired error', () async {
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 0, status: 'Expired'),
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: InMemorySecureStorage(),
      );

      final result = await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'u',
          password: 'expired',
        ),
      );

      expect(result, isFalse);
      expect(notifier.error, isNotNull);
    });

    test(
      'connect with non-m3u-editor backend sets notM3UEditor error',
      () async {
        final transport = _FakeTransport({
          'auth': {
            'user_info': {
              'username': 'u',
              'password': 'p',
              'auth': 1,
              'status': 'Active',
            },
            'server_info': {'url': 'x.com', 'port': '443'},
            // No m3u_editor key
          },
        });
        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: transport.call),
          secureStorage: InMemorySecureStorage(),
        );

        final result = await notifier.connect(
          const UserCredentials(
            server: 'http://x.com',
            username: 'u',
            password: 'p',
          ),
        );

        expect(result, isFalse);
        expect(notifier.error, contains('m3u-editor'));
      },
    );

    test('connect with offline server sets error', () async {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(
          transport: (_) async {
            throw Exception('Connection refused');
          },
        ),
        secureStorage: InMemorySecureStorage(),
      );

      final result = await notifier.connect(
        const UserCredentials(
          server: 'http://offline.com',
          username: 'u',
          password: 'p',
        ),
      );

      expect(result, isFalse);
      expect(notifier.error, isNotNull);
    });

    test(
      'connect with unavailable server shows user-facing outage error',
      () async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(
            transport: (_) async {
              throw XtreamHttpException(
                statusCode: 503,
                method: 'GET',
                uri: Uri.parse('http://x.com/player_api.php'),
                reasonPhrase: 'Service Unavailable',
                serverMessage: 'no available server',
              );
            },
          ),
          secureStorage: InMemorySecureStorage(),
        );

        final result = await notifier.connect(
          const UserCredentials(
            server: 'http://x.com',
            username: 'u',
            password: 'p',
          ),
        );

        expect(result, isFalse);
        expect(notifier.error, 'Server is currently unavailable.');
        expect(notifier.error, isNot(contains('Xtream HTTP 503')));
        expect(notifier.error, isNot(contains('player_api.php')));
      },
    );

    test(
      'connect with plaintext server failure hides parser details',
      () async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(
            transport: (_) async {
              throw XtreamResponseException(
                method: 'GET',
                uri: Uri.parse('http://x.com/player_api.php'),
                serverMessage: 'no available server',
              );
            },
          ),
          secureStorage: InMemorySecureStorage(),
        );

        final result = await notifier.connect(
          const UserCredentials(
            server: 'http://x.com',
            username: 'u',
            password: 'p',
          ),
        );

        expect(result, isFalse);
        expect(notifier.error, contains('no available server'));
        expect(notifier.error, isNot(contains('FormatException')));
      },
    );

    test('connect persists credentials to secure storage', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );

      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'u',
          password: 'p',
        ),
      );

      final saved = await storage.read('m3ue_tv_credentials');
      expect(saved, isNotNull);
      expect(saved, contains('http://x.com'));
    });

    test('disconnect clears state and deletes credentials', () async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );

      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'u',
          password: 'p',
        ),
      );
      expect(notifier.isConfigured, isTrue);

      await notifier.disconnect();
      expect(notifier.isConfigured, isFalse);
      expect(notifier.authResponse, isNull);
      expect(await storage.read('m3ue_tv_credentials'), isNull);
    });

    test('loadSavedCredentials restores from storage', () async {
      final storage = InMemorySecureStorage();
      await storage.write(
        'm3ue_tv_credentials',
        '{"server":"http://x.com","username":"u","password":"p"}',
      );
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );

      final result = await notifier.loadSavedCredentials();
      expect(result, isTrue);
      expect(notifier.isConfigured, isTrue);
    });

    test(
      'loadSavedCredentials returns false when no saved credentials',
      () async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );

        final result = await notifier.loadSavedCredentials();
        expect(result, isFalse);
      },
    );
  });

  // --- ConnectionForm widget ---

  group('ConnectionForm', () {
    testWidgets('shows server, username, password fields', (tester) async {
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
    });

    testWidgets('shows error when fields are empty on connect', (tester) async {
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Please fill in all fields'), findsOneWidget);
    });

    testWidgets('calls onConnect with entered credentials', (tester) async {
      UserCredentials? captured;
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (creds) => captured = creds),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'http://x.com');
      await tester.enterText(find.byType(TextFormField).at(1), 'user1');
      await tester.enterText(find.byType(TextFormField).at(2), 'pass1');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.server, 'http://x.com');
      expect(captured!.username, 'user1');
      expect(captured!.password, 'pass1');
    });

    testWidgets('shows loading indicator when isLoading is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (_) {}, isLoading: true),
        ),
      );
      // Use pump instead of pumpAndSettle because CircularProgressIndicator has infinite animation
      await tester.pump();

      // The Connect button should be disabled and show a progress indicator
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // The "Connect" text should not be visible when loading
      expect(find.text('Connect'), findsNothing);
    });

    testWidgets('shows error text when error is provided', (tester) async {
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (_) {}, error: 'Authentication failed'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Authentication failed'), findsOneWidget);
    });

    testWidgets('password field obscures text', (tester) async {
      await tester.pumpWidget(
        _testApp(
          ConnectionForm(onConnect: (_) {}),
        ),
      );
      await tester.pumpAndSettle();

      // Find the password field (3rd TextFormField) and verify its TextField has obscureText
      final passwordField = find.byType(TextFormField).at(2);
      // Find the TextField descendant within this TextFormField
      final textField = find.descendant(
        of: passwordField,
        matching: find.byType(TextField),
      );
      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.obscureText, isTrue);
    });
  });

  // --- SettingsScreen widget ---

  group('SettingsScreen', () {
    testWidgets(
      'shows credential guidance on disconnected first-launch compact viewport',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;

        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );

        await tester.pumpWidget(_settingsApp(notifier));
        await tester.pumpAndSettle();

        expect(find.text('Server URL'), findsOneWidget);
        expect(
          find.textContaining('playlist Xtream connection details'),
          findsOneWidget,
        );
        expect(find.textContaining('server URL'), findsOneWidget);
        expect(find.textContaining('Xtream username'), findsOneWidget);
        expect(find.textContaining('Xtream password'), findsOneWidget);
      },
    );

    testWidgets(
      'shows credential guidance on disconnected TV-sized viewport',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;

        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );

        await tester.pumpWidget(_settingsApp(notifier));
        await tester.pumpAndSettle();

        expect(find.text('Server URL'), findsOneWidget);
        expect(
          find.textContaining('playlist Xtream connection details'),
          findsOneWidget,
        );
        expect(find.textContaining('server URL'), findsOneWidget);
        expect(find.textContaining('Xtream username'), findsOneWidget);
        expect(find.textContaining('Xtream password'), findsOneWidget);
      },
    );

    testWidgets(
      'shows credential guidance on disconnected Settings sign-in tab',
      (tester) async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );
        final pairingService = DevicePairingService();
        addTearDown(pairingService.dispose);

        await tester.pumpWidget(
          _settingsApp(notifier, devicePairingService: pairingService),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sign In'));
        await tester.pumpAndSettle();

        expect(find.text('Server URL'), findsOneWidget);
        expect(
          find.textContaining('playlist Xtream connection details'),
          findsOneWidget,
        );
        expect(find.textContaining('server URL'), findsOneWidget);
        expect(find.textContaining('Xtream username'), findsOneWidget);
        expect(find.textContaining('Xtream password'), findsOneWidget);
      },
    );

    testWidgets(
      'does not show setup guidance when connected or in outage mode',
      (tester) async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );

        await tester.pumpWidget(
          _settingsApp(
            notifier,
            isConfiguredOverride: true,
            sourceError: 'Server is currently unavailable.',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Server is currently unavailable.'), findsOneWidget);
        expect(
          find.textContaining('playlist Xtream connection details'),
          findsNothing,
        );
      },
    );

    testWidgets('shows connection form when not configured', (tester) async {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );

      await tester.pumpWidget(_settingsApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
    });

    testWidgets('shows source error on connection form when content load fails', (
      tester,
    ) async {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );

      await tester.pumpWidget(
        _settingsApp(
          notifier,
          sourceError:
              'Xtream HTTP 401 Unauthorized for GET http://server.test/player_api.php: Unauthorized',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server URL'), findsOneWidget);
      expect(find.textContaining('Xtream HTTP 401'), findsOneWidget);
    });

    testWidgets('shows connection status when configured', (tester) async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );
      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(_settingsApp(notifier));
      await tester.pumpAndSettle();

      // Should show the connected view with status
      expect(find.text('Connection'), findsOneWidget);
      expect(find.text('Connected'), findsWidgets);
    });

    testWidgets('shows outage actions instead of setup copy when configured', (
      tester,
    ) async {
      var retried = false;
      var edited = false;
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );

      await tester.pumpWidget(
        _settingsApp(
          notifier,
          sourceError: 'Server is currently unavailable.',
          isConfiguredOverride: true,
          onClearCache: () => retried = true,
          onDisconnect: () => edited = true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server is currently unavailable.'), findsOneWidget);
      expect(find.text('Retry connection'), findsOneWidget);
      expect(find.text('Edit server settings'), findsOneWidget);
      expect(find.text('Enter your Xtream codes details'), findsNothing);

      await tester.tap(find.text('Retry connection'));
      await tester.pumpAndSettle();
      expect(retried, isTrue);

      await tester.tap(find.text('Edit server settings'));
      await tester.pumpAndSettle();
      expect(find.text('Disconnect?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Disconnect'),
        ),
      );
      await tester.pumpAndSettle();
      expect(edited, isTrue);
    });

    testWidgets('shows disconnect button when configured', (tester) async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );
      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(_settingsApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('shows cache section when configured', (tester) async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );
      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(_settingsApp(notifier));
      await tester.pumpAndSettle();

      expect(find.text('Content Cache'), findsOneWidget);
    });

    testWidgets('shows viewer section when m3u-editor and viewer available', (
      tester,
    ) async {
      final storage = InMemorySecureStorage();
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: storage,
      );
      await notifier.connect(
        const UserCredentials(
          server: 'http://x.com',
          username: 'demo',
          password: 'secret',
        ),
      );

      const viewer = Viewer(id: 1, ulid: 'v1', name: 'Admin', isAdmin: true);
      await tester.pumpWidget(_settingsApp(notifier, activeViewer: viewer));
      await tester.pumpAndSettle();

      // Should show the viewer section with the viewer name
      expect(find.text('Active Viewer'), findsOneWidget);
      expect(find.text('Admin'), findsWidgets);
    });

    testWidgets(
      'hides "Pair with code" when no devicePairingService is supplied',
      (tester) async {
        final notifier = AuthNotifier(
          xtreamService: XtreamService(transport: _FakeTransport({}).call),
          secureStorage: InMemorySecureStorage(),
        );

        await tester.pumpWidget(_settingsApp(notifier));
        await tester.pumpAndSettle();

        expect(find.text('Pair with code'), findsNothing);
      },
    );

    testWidgets('shows validation error when pairing with an empty server', (
      tester,
    ) async {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );
      final pairingService = DevicePairingService();
      addTearDown(pairingService.dispose);

      await tester.pumpWidget(
        _settingsApp(notifier, devicePairingService: pairingService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pair with code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your server URL first'), findsOneWidget);
    });

    testWidgets('shows the pairing code once pairing starts', (tester) async {
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: _FakeTransport({}).call),
        secureStorage: InMemorySecureStorage(),
      );
      final transport = _FakeDevicePairingTransport([
        const DevicePairingResponse(200, <String, Object?>{
          'device_code': 'DEVICE-CODE',
          'user_code': 'ABCD-1234',
          'verification_uri': 'http://x.com/device-pairing?code=ABCD-1234',
          'interval': 3600,
          'expires_in': 600,
        }),
      ]);
      final pairingService = DevicePairingService(transport: transport.call);

      await tester.pumpWidget(
        _settingsApp(notifier, devicePairingService: pairingService),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'x.com');
      await tester.tap(find.text('Pair with code'));
      // Use pump instead of pumpAndSettle because the pending pairing view
      // shows a CircularProgressIndicator with infinite animation.
      await tester.pump();
      await tester.pump();

      expect(find.text('ABCD-1234'), findsOneWidget);

      // Dispose synchronously within the test body (not via addTearDown) so
      // the scheduled poll Timer is cancelled before flutter_test's
      // pending-timer invariant check runs.
      pairingService.dispose();
    });

    testWidgets('connects automatically once pairing is approved', (
      tester,
    ) async {
      final transport = _FakeTransport({
        'auth': _xtreamAuth(auth: 1),
        'get_live_categories': <Map<String, Object?>>[],
        'get_vod_categories': <Map<String, Object?>>[],
        'get_series_categories': <Map<String, Object?>>[],
      });
      final notifier = AuthNotifier(
        xtreamService: XtreamService(transport: transport.call),
        secureStorage: InMemorySecureStorage(),
      );
      final pairingTransport = _FakeDevicePairingTransport([
        const DevicePairingResponse(200, <String, Object?>{
          'device_code': 'DEVICE-CODE',
          'user_code': 'ABCD-1234',
          'verification_uri': 'http://x.com/device-pairing?code=ABCD-1234',
          'interval': 3600,
          'expires_in': 600,
        }),
        const DevicePairingResponse(200, <String, Object?>{
          'status': 'approved',
          'username': 'u',
          'password': 'p',
        }),
      ]);
      final pairingService = DevicePairingService(
        transport: pairingTransport.call,
      );

      await tester.pumpWidget(
        _settingsApp(notifier, devicePairingService: pairingService),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).at(0), 'x.com');
      await tester.tap(find.text('Pair with code'));
      // Use pump instead of pumpAndSettle: both the pending pairing view and
      // the post-approval connecting screen show an infinitely-animating
      // CircularProgressIndicator.
      await tester.pump();
      await tester.pump();

      await pairingService.pollForTesting('http://x.com');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      pairingService.dispose();

      expect(notifier.isConfigured, isTrue);
    });
  });

  // --- ViewerSelector widget ---

  group('ViewerSelector', () {
    testWidgets('shows active viewer name and admin badge', (tester) async {
      final viewers = [
        const Viewer(id: 1, ulid: 'v1', name: 'Admin', isAdmin: true),
        const Viewer(id: 2, ulid: 'v2', name: 'User', isAdmin: false),
      ];

      await tester.pumpWidget(
        _testApp(
          ViewerSelector(
            viewers: viewers,
            activeViewer: viewers[0],
            onSwitch: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Admin name appears in the viewer card
      expect(find.text('Admin'), findsWidgets);
      expect(find.text('Switch Viewer'), findsOneWidget);
    });

    testWidgets('calls onSwitch when a viewer is selected', (tester) async {
      final viewers = [
        const Viewer(id: 1, ulid: 'v1', name: 'Admin', isAdmin: true),
        const Viewer(id: 2, ulid: 'v2', name: 'User', isAdmin: false),
      ];
      Viewer? switchedTo;

      await tester.pumpWidget(
        _testApp(
          ViewerSelector(
            viewers: viewers,
            activeViewer: viewers[0],
            onSwitch: (v) => switchedTo = v,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('User'));
      await tester.pumpAndSettle();

      expect(switchedTo, viewers[1]);
    });
  });

  // --- DiagnosticsScreen ---

  group('DiagnosticsScreen', () {
    testWidgets('shows backend capabilities when available', (tester) async {
      const capabilities = BackendCapabilities(
        m3uEditorVersion: '0.10.0',
        features: ['progress', 'viewers', 'transcode'],
        transcodeAvailable: true,
      );

      await tester.pumpWidget(
        _testApp(
          const DiagnosticsScreen(capabilities: capabilities),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Backend Capabilities'), findsOneWidget);
      expect(find.text('0.10.0'), findsOneWidget);
      expect(find.text('progress'), findsOneWidget);
    });

    testWidgets('shows transcode server status', (tester) async {
      const capabilities = BackendCapabilities(
        m3uEditorVersion: '0.10.0',
        features: ['progress'],
        transcodeAvailable: true,
      );

      await tester.pumpWidget(
        _testApp(
          const DiagnosticsScreen(capabilities: capabilities),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Transcode Server'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
    });

    testWidgets('shows unavailable transcode status', (tester) async {
      const capabilities = BackendCapabilities(
        m3uEditorVersion: '0.10.0',
        features: ['progress'],
        transcodeAvailable: false,
      );

      await tester.pumpWidget(
        _testApp(
          const DiagnosticsScreen(capabilities: capabilities),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('does not expose secrets in diagnostics', (tester) async {
      const capabilities = BackendCapabilities(
        m3uEditorVersion: '0.10.0',
        features: ['progress'],
        transcodeAvailable: true,
      );

      await tester.pumpWidget(
        _testApp(
          const DiagnosticsScreen(capabilities: capabilities),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no password or credential text appears
      final allText = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((s) => s != null)
          .join(' ');
      expect(allText, isNot(contains('password')));
      expect(allText, isNot(contains('secret')));
    });

    testWidgets('shows no capabilities message when null', (tester) async {
      await tester.pumpWidget(
        _testApp(
          const DiagnosticsScreen(capabilities: null),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Not connected'), findsOneWidget);
    });
  });

  // --- M3U source diagnostics ---

  group('M3U source diagnostics', () {
    test('valid M3U URL source parses successfully', () async {
      final parser = M3UParser();
      const m3uContent =
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="ch1" group-title="News",Channel 1\n'
          'http://streams.example/live/1.m3u8\n';
      final result = parser.parse(m3uContent);

      expect(result.channels, hasLength(1));
      expect(result.channels.first.name, 'Channel 1');
      expect(
        result.channels.first.streamUrl,
        'http://streams.example/live/1.m3u8',
      );
    });

    test('malformed M3U source throws parse exception', () {
      final parser = M3UParser();
      // Content without #EXTM3U header
      const malformed = 'just random text\nnot a playlist';

      expect(() => parser.parse(malformed), throwsA(isA<M3UParseException>()));
    });

    test('invalid URL in M3U source is captured in channel', () async {
      final parser = M3UParser();
      const m3uContent =
          '#EXTM3U\n'
          '#EXTINF:-1 tvg-id="ch1",Channel 1\n'
          'not-a-valid-url\n';
      final result = parser.parse(m3uContent);

      // Parser should still capture the entry even with invalid URL
      expect(result.channels, hasLength(1));
      expect(result.channels.first.streamUrl, 'not-a-valid-url');
    });
  });
}

// --- Test helpers ---

Map<String, Object?> _xtreamAuth({
  required int auth,
  String status = 'Active',
}) => {
  'user_info': {
    'username': 'demo',
    'password': 'secret',
    'auth': auth,
    'status': status,
    'message': status,
  },
  'server_info': {'url': 'x.com', 'port': '443', 'server_protocol': 'https'},
  'm3u_editor': {
    'version': '0.10.0',
    'features': <String>['progress'],
  },
};

class _FakeTransport {
  _FakeTransport(this.responses);

  final Map<String, Object?> responses;
  Map<String, String> lastHeaders = const {};

  Future<Object?> call(XtreamRequest request) async {
    lastHeaders = request.headers;
    final action = request.action ?? 'auth';
    final response = responses[action];
    if (response == null) {
      throw StateError('No fixture for ${request.toDebugMap()}');
    }
    return response;
  }
}

Widget _testApp(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

Widget _settingsApp(
  AuthNotifier notifier, {
  Viewer? activeViewer,
  String? sourceError,
  bool? isConfiguredOverride,
  VoidCallback? onClearCache,
  VoidCallback? onDisconnect,
  DevicePairingService? devicePairingService,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SettingsScreen(
        authNotifier: notifier,
        traktService: TraktService(storage: InMemorySecureStorage()),
        devicePairingService: devicePairingService,
        activeViewer: activeViewer,
        sourceError: sourceError,
        isConfiguredOverride: isConfiguredOverride,
        onClearCache: onClearCache,
        onDisconnect: onDisconnect ?? () => notifier.disconnect(),
      ),
    ),
  );
}

class _FakeDevicePairingTransport {
  _FakeDevicePairingTransport(this._responses);

  final List<DevicePairingResponse> _responses;

  Future<DevicePairingResponse> call(DevicePairingRequest request) async {
    if (_responses.isEmpty) {
      return const DevicePairingResponse(500, <String, Object?>{});
    }
    return _responses.removeAt(0);
  }
}
