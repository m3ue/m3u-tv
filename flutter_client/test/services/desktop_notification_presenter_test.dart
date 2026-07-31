import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/desktop_notification_presenter.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';

void main() {
  group('NativeDesktopNotificationPresenter', () {
    for (final operatingSystem in <String>['linux', 'windows', 'macos']) {
      test(
        '$operatingSystem initializes and presents native content',
        () async {
          final backend = _FakeDesktopNotificationBackend();
          final presenter = NativeDesktopNotificationPresenter(
            operatingSystem: operatingSystem,
            backend: backend,
          );

          await presenter.initialize(
            defaultActionName: 'Open',
            onActivation: (_) async {},
          );
          final presented = await presenter.present(_notification);

          expect(presented, isTrue);
          expect(backend.initializeCalls, 1);
          expect(backend.defaultActionName, 'Open');
          expect(backend.shown, <_ShownNotification>[
            _ShownNotification(
              id: desktopNotificationId(_notification.id),
              title: _notification.title,
              body: _notification.body,
              payload: _notification.id,
            ),
          ]);
        },
      );
    }

    for (final operatingSystem in <String>['android', 'ios', 'tvos', 'web']) {
      test('$operatingSystem is a native presentation no-op', () async {
        final backend = _FakeDesktopNotificationBackend();
        final presenter = NativeDesktopNotificationPresenter(
          operatingSystem: operatingSystem,
          backend: backend,
        );

        await presenter.initialize(
          defaultActionName: 'Open',
          onActivation: (_) async {},
        );

        expect(await presenter.present(_notification), isFalse);
        expect(backend.initializeCalls, 0);
        expect(backend.shown, isEmpty);
      });
    }

    test('initialization failure preserves toast fallback', () async {
      final backend = _FakeDesktopNotificationBackend()..failInitialize = true;
      final fallback = <TvNotificationItem>[];
      final dispatcher = DesktopNotificationDispatcher(
        presenter: NativeDesktopNotificationPresenter(
          operatingSystem: 'linux',
          backend: backend,
        ),
        onFallback: fallback.add,
      );

      await dispatcher.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );
      await dispatcher.dispatch(_notification);

      expect(backend.shown, isEmpty);
      expect(fallback, <TvNotificationItem>[_notification]);
    });

    test('presentation failure preserves toast fallback', () async {
      final backend = _FakeDesktopNotificationBackend()..failShow = true;
      final fallback = <TvNotificationItem>[];
      final dispatcher = DesktopNotificationDispatcher(
        presenter: NativeDesktopNotificationPresenter(
          operatingSystem: 'windows',
          backend: backend,
        ),
        onFallback: fallback.add,
      );

      await dispatcher.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );
      await dispatcher.dispatch(_notification);

      expect(backend.shown, isEmpty);
      expect(fallback, <TvNotificationItem>[_notification]);
    });

    test(
      'successful native presentation suppresses fallback exactly once',
      () async {
        final backend = _FakeDesktopNotificationBackend();
        final fallback = <TvNotificationItem>[];
        final dispatcher = DesktopNotificationDispatcher(
          presenter: NativeDesktopNotificationPresenter(
            operatingSystem: 'linux',
            backend: backend,
          ),
          onFallback: fallback.add,
        );

        await dispatcher.initialize(
          defaultActionName: 'Open',
          onActivation: (_) async {},
        );
        await dispatcher.dispatch(_notification);
        await dispatcher.dispatch(_notification);

        expect(backend.shown, hasLength(1));
        expect(fallback, isEmpty);
      },
    );

    test('non-desktop dispatcher selects toast fallback', () async {
      final fallback = <TvNotificationItem>[];
      final dispatcher = DesktopNotificationDispatcher(
        presenter: NativeDesktopNotificationPresenter(
          operatingSystem: 'android',
          backend: _FakeDesktopNotificationBackend(),
        ),
        onFallback: fallback.add,
      );

      await dispatcher.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );
      await dispatcher.dispatch(_notification);

      expect(fallback, <TvNotificationItem>[_notification]);
    });

    test('activation accepts only a canonical ID payload', () async {
      final backend = _FakeDesktopNotificationBackend();
      final activated = <String>[];
      final presenter = NativeDesktopNotificationPresenter(
        operatingSystem: 'linux',
        backend: backend,
      );
      await presenter.initialize(
        defaultActionName: 'Open',
        onActivation: (id) async => activated.add(id),
      );

      backend
        ..activate(_notification.id.toUpperCase())
        ..activate('not-a-notification-id')
        ..activate(null);
      await Future<void>.delayed(Duration.zero);

      expect(activated, <String>[_notification.id]);
    });

    test('re-initializes the backend when the action name changes', () async {
      final backend = _FakeDesktopNotificationBackend();
      final presenter = NativeDesktopNotificationPresenter(
        operatingSystem: 'linux',
        backend: backend,
      );

      await presenter.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );
      await presenter.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );
      expect(backend.initializeCalls, 1);

      await presenter.initialize(
        defaultActionName: 'Öffnen',
        onActivation: (_) async {},
      );

      expect(backend.initializeCalls, 2);
      expect(backend.defaultActionName, 'Öffnen');
    });

    test('dispose suppresses further presentation and activation', () async {
      final backend = _FakeDesktopNotificationBackend();
      final activated = <String>[];
      final presenter = NativeDesktopNotificationPresenter(
        operatingSystem: 'linux',
        backend: backend,
      );
      await presenter.initialize(
        defaultActionName: 'Open',
        onActivation: (id) async => activated.add(id),
      );

      presenter.dispose();
      backend.activate(_notification.id);
      await Future<void>.delayed(Duration.zero);
      final presented = await presenter.present(_notification);

      expect(activated, isEmpty);
      expect(presented, isFalse);
      expect(backend.shown, isEmpty);
    });

    test('handled ID de-duplication is bounded', () async {
      final backend = _FakeDesktopNotificationBackend();
      final presenter = NativeDesktopNotificationPresenter(
        operatingSystem: 'linux',
        backend: backend,
      );
      await presenter.initialize(
        defaultActionName: 'Open',
        onActivation: (_) async {},
      );

      final overflow = List<TvNotificationItem>.generate(
        501,
        (index) => _notificationWithId(
          'bbbbbbbb-bbbb-4bbb-8bbb-${index.toRadixString(16).padLeft(12, '0')}',
        ),
      );
      for (final item in overflow) {
        await presenter.present(item);
      }
      expect(backend.shown, hasLength(501));

      // The oldest handled ID should have been evicted, so it presents again.
      await presenter.present(overflow.first);

      expect(backend.shown, hasLength(502));
    });

    test('notification ID mapping is stable and bounded', () {
      final first = desktopNotificationId(_notification.id);

      expect(desktopNotificationId(_notification.id), first);
      expect(first, inInclusiveRange(0, 0x7fffffff));
      expect(
        desktopNotificationId('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
        isNot(first),
      );
    });
  });
}

const _notification = TvNotificationItem(
  id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  channel: 'general',
  title: 'Authoritative title',
  body: 'Authoritative body',
  status: 'info',
);

TvNotificationItem _notificationWithId(String id) => TvNotificationItem(
  id: id,
  channel: 'general',
  title: 'Authoritative title',
  body: 'Authoritative body',
  status: 'info',
);

class _ShownNotification {
  const _ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String? body;
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is _ShownNotification &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, title, body, payload);
}

class _FakeDesktopNotificationBackend implements DesktopNotificationBackend {
  int initializeCalls = 0;
  String? defaultActionName;
  bool failInitialize = false;
  bool failShow = false;
  void Function(String? payload)? _onActivation;
  final List<_ShownNotification> shown = <_ShownNotification>[];

  @override
  Future<void> initialize({
    required String defaultActionName,
    required void Function(String? payload) onActivation,
  }) async {
    initializeCalls += 1;
    this.defaultActionName = defaultActionName;
    _onActivation = onActivation;
    if (failInitialize) throw StateError('initialization failed');
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String? body,
    required String payload,
  }) async {
    if (failShow) throw StateError('presentation failed');
    shown.add(
      _ShownNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
      ),
    );
  }

  void activate(String? payload) => _onActivation?.call(payload);
}
