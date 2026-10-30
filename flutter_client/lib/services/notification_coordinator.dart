// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/device_identity_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// The Reverb push handlers that belong to the rest of the app (DVR, media
/// requests, favorites). Built by the controller once a notification session
/// is about to connect, so their ownership checks are captured at that point.
typedef NotificationSessionHandlers = ({
  void Function(DvrRecording) onDvrStatus,
  void Function(MediaRequestSummary) onRequestStatus,
  void Function(FavoriteToggleEvent) onFavoriteToggled,
  void Function() onConnected,
});

/// Whether [first] and [second] are the same non-null login.
bool sameCredentials(UserCredentials? first, UserCredentials? second) =>
    first != null &&
    second != null &&
    first.server == second.server &&
    first.username == second.username &&
    first.password == second.password;

/// TV notifications (the local store, unread count, Reverb WebSocket, push
/// taps) and the mobile push-token lifecycle, split out of
/// `AppStateController`. The controller still decides when a session starts
/// or ends (boot, connect, sign-out) and calls in here; every async path
/// re-checks an ownership closure so a source, viewer or session switch
/// mid-call can't write stale notification state back.
class NotificationCoordinator {
  NotificationCoordinator({
    required TvNotificationService service,
    required this.store,
    required ReverbService reverbService,
    required PushNotificationService pushService,
    required DeviceIdentityService deviceIdentityService,
    required UserCredentials? Function() credentials,
    required bool Function() Function(UserCredentials credentials)
    captureAppOwnership,
    required NotificationSessionHandlers Function(
      UserCredentials credentials,
      int generation,
    )
    sessionHandlers,
    required Future<void> Function() signOut,
    required void Function(Future<Object?> operation) runInBackground,
    required VoidCallback notifyListeners,
  }) : _service = service,
       _reverbService = reverbService,
       _pushService = pushService,
       _deviceIdentityService = deviceIdentityService,
       _credentials = credentials,
       _captureAppOwnership = captureAppOwnership,
       _sessionHandlers = sessionHandlers,
       _signOut = signOut,
       _runInBackground = runInBackground,
       _notifyListeners = notifyListeners;

  final TvNotificationService _service;
  final TvNotificationStore store;
  final ReverbService _reverbService;
  final PushNotificationService _pushService;
  final DeviceIdentityService _deviceIdentityService;
  final UserCredentials? Function() _credentials;
  final bool Function() Function(UserCredentials credentials)
  _captureAppOwnership;
  final NotificationSessionHandlers Function(
    UserCredentials credentials,
    int generation,
  )
  _sessionHandlers;
  final Future<void> Function() _signOut;
  final void Function(Future<Object?> operation) _runInBackground;
  final VoidCallback _notifyListeners;

  /// Advanced by the controller whenever the notification session changes
  /// owner (boot, connect, sign-out). DVR and media-request ownership checks
  /// read it too.
  final Generation sessionGeneration = Generation();

  String? _pushToken;
  bool _pushRegistrationSuspended = false;
  UserCredentials? _registeredPushCredentials;
  String? _registeredPushToken;
  final SerialQueue _pushLifecycleQueue = SerialQueue();
  final Generation _pushLifecycleGeneration = Generation();
  Future<void>? _pushInitialization;
  StreamSubscription<String>? _pushTokenSubscription;
  final Set<String> _pendingActivations = <String>{};
  final StreamController<TvNotificationItem> _notificationController =
      StreamController<TvNotificationItem>.broadcast();
  final StreamController<TvNotificationDestination> _activationController =
      StreamController<TvNotificationDestination>.broadcast();
  static const _maxActivatedNotificationIds = 100;
  final Set<String> _activatedNotificationIds = <String>{};
  int _unreadCount = 0;

  Stream<TvNotificationItem> get notifications =>
      _notificationController.stream;

  Stream<TvNotificationDestination> get activations =>
      _activationController.stream;

  int get unreadCount => _unreadCount;

  /// Drops the store's owner and everything derived from it, ahead of a
  /// session change. The caller notifies.
  void clearOwner() {
    store.clearOwner();
    _unreadCount = 0;
    _activatedNotificationIds.clear();
  }

  /// Ends the current session ahead of a sign-out or account switch: drops
  /// the store's owner, holds push-token registration while the session
  /// changes hands, and invalidates any registration already queued.
  void endSession() {
    clearOwner();
    _pushRegistrationSuspended = true;
    _pushLifecycleGeneration.advance();
  }

  void resumePushRegistration() => _pushRegistrationSuspended = false;

  Future<void> disconnectReverb() => _reverbService.disconnect();

  Future<bool> _refreshUnreadCount({bool Function()? shouldCommit}) async {
    if (shouldCommit != null && !shouldCommit()) return false;
    final subscribed = await store.subscribedChannels();
    if (shouldCommit != null && !shouldCommit()) return false;
    final unreadCount = await store.unreadCount(
      channelFilter: subscribed.isEmpty ? null : subscribed,
    );
    if (shouldCommit != null && !shouldCommit()) return false;
    _unreadCount = unreadCount;
    _notifyListeners();
    return true;
  }

  Future<void> markRead(String id) async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsNotification = _captureOwnership(
      credentials: credentials,
      notificationGeneration: sessionGeneration.current,
    );
    if (!ownsNotification()) return;
    await store.markReadIf(id, ownsNotification);
    if (!ownsNotification()) return;
    if (!await _refreshUnreadCount(shouldCommit: ownsNotification)) {
      return;
    }
    if (!ownsNotification()) return;
    unawaited(_service.markRead(credentials, id).catchError((_) {}));
  }

  Future<void> markAllRead() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsNotification = _captureOwnership(
      credentials: credentials,
      notificationGeneration: sessionGeneration.current,
    );
    if (!ownsNotification()) return;
    final unread = (await store.all()).where((n) => !n.isRead);
    if (!ownsNotification()) return;
    final ids = unread.map((n) => n.item.id).toList(growable: false);
    await store.markAllReadIf(ownsNotification);
    if (!ownsNotification()) return;
    if (!await _refreshUnreadCount(shouldCommit: ownsNotification)) {
      return;
    }
    for (final id in ids) {
      if (!ownsNotification()) return;
      unawaited(_service.markRead(credentials, id).catchError((_) {}));
    }
  }

  Future<void> setChannels(Set<String> channels) async {
    final credentials = _credentials();
    if (credentials == null) return;
    final ownsNotification = _captureOwnership(
      credentials: credentials,
      notificationGeneration: sessionGeneration.current,
    );
    if (!ownsNotification()) return;
    await store.setSubscribedChannels(channels);
    if (!ownsNotification()) return;
    await _refreshUnreadCount(shouldCommit: ownsNotification);
  }

  /// Reconciles unread notifications, drains taps that arrived before
  /// sign-in, then opens the Reverb WebSocket for [credentials].
  Future<void> connect(
    UserCredentials credentials,
    int notificationGeneration,
  ) async {
    try {
      final session = await _reconcileUnread(
        credentials,
        present: _pendingActivations.isEmpty,
        notificationGeneration: notificationGeneration,
      );
      if (sessionGeneration.isStale(notificationGeneration)) {
        return;
      }
      await _drainPendingActivations();
      if (sessionGeneration.isStale(notificationGeneration) ||
          !sameCredentials(_credentials(), credentials)) {
        return;
      }
      // Older server versions don't return Reverb config - skip WebSocket setup
      // rather than hammering a connection that can never succeed.
      if (session == null) return;
      final handlers = _sessionHandlers(credentials, notificationGeneration);

      await _reverbService.connect(
        session: session,
        credentials: credentials,
        onNotification: _onPushNotification,
        onDvrStatus: handlers.onDvrStatus,
        onRequestStatus: handlers.onRequestStatus,
        onFavoriteToggled: handlers.onFavoriteToggled,
        onDeviceDeregister: _onDeviceDeregisterPush,
        // Reconciles any status pushes missed while disconnected (app
        // suspended, network drop) - cheap, status-filtered fetch, not a poll.
        onConnected: handlers.onConnected,
      );
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
  }

  /// Fetches the server's unread notification list. Used on live-stream end so
  /// an eviction notice ("A DVR recording has taken precedence...") can be shown
  /// as a toast even when the Reverb push channel is down - the notification
  /// is persisted server-side and only the push delivery is unreliable.
  Future<List<TvNotificationItem>> fetchUnread() async {
    final credentials = _credentials();
    if (credentials == null) return const [];
    try {
      final (_, unread) = await _service.fetchUnread(credentials);
      return unread;
    } on Object {
      return const [];
    }
  }

  Future<TvPlaylistSession?> _reconcileUnread(
    UserCredentials credentials, {
    String? presentOnlyId,
    bool present = true,
    int? notificationGeneration,
  }) async {
    final accountPrincipal = credentials.username;
    final ownsNotification = _captureOwnership(
      credentials: credentials,
      notificationGeneration: notificationGeneration,
    );
    if (!ownsNotification()) return null;
    final (session, unread) = await _service.fetchUnread(credentials);
    if (!ownsNotification()) return null;
    if (session.deviceRevoked) {
      // An admin revoked this install in the editor. Drop to the pairing
      // screen; the credential itself still works so the user can re-pair.
      unawaited(_signOut());
      return null;
    }
    if (!store.selectOwner(
      server: credentials.server,
      accountPrincipal: accountPrincipal,
      session: session,
    )) {
      clearOwner();
      return null;
    }
    if (session.availableChannels.isNotEmpty) {
      await store.setServerChannels(
        session.availableChannels,
        shouldCommit: ownsNotification,
      );
      if (!ownsNotification()) return null;
    }
    // Sync local store with the server's authoritative unread list: stale
    // local unreads are marked read, new server items are added. Only
    // genuinely new items (not seen before) are surfaced as toasts - this
    // should not replay banners for notifications the user already received.
    final authorizedUnread = session.isAdmin
        ? unread
        : unread.where((item) => !item.adminOnly).toList(growable: false);
    final newItems = await store.syncUnreadWithServer(
      authorizedUnread,
      shouldCommit: ownsNotification,
    );
    if (!ownsNotification()) return null;
    if (!await _refreshUnreadCount(shouldCommit: ownsNotification)) {
      return null;
    }
    if (present) {
      final subscribed = await store.subscribedChannels();
      if (!ownsNotification()) return null;
      for (final item in newItems) {
        if ((presentOnlyId == null || item.id == presentOnlyId) &&
            (subscribed.isEmpty || subscribed.contains(item.channel)) &&
            ownsNotification()) {
          _notificationController.add(item);
        }
      }
    }
    if (!ownsNotification()) return null;
    if (session.channelName.isEmpty || session.reverb.appKey.isEmpty) {
      return null;
    }
    return session;
  }

  Future<void> reconcile() async {
    final credentials = _credentials();
    if (credentials == null) return;
    await _reconcileUnread(credentials);
  }

  /// Suspends the TV notification WebSocket while the app is backgrounded.
  /// Call [resume] when the app returns to the foreground.
  Future<void> suspend() => _reverbService.pause();

  /// Reconnects the TV notification WebSocket after the app returns to the
  /// foreground, and reconciles any notifications (e.g. a push received
  /// while backgrounded) the server delivered while the socket was down.
  /// No-op if there are no stored credentials.
  Future<void> resume() async {
    final credentials = _credentials();
    if (credentials == null) return;
    final notificationGeneration = sessionGeneration.current;
    try {
      await _reconcileUnread(
        credentials,
        present: _pendingActivations.isEmpty,
        notificationGeneration: notificationGeneration,
      );
    } on Object catch (_) {
      // TV notifications are best-effort; a failure here must not crash the app.
    }
    await _drainPendingActivations();
    await _reverbService.resume();
  }

  /// Called by `main.dart` once Firebase hands back an FCM registration
  /// token (mobile only - TV builds never call this). Registers immediately
  /// if credentials are already connected; otherwise the token is held and
  /// registered the next time a session connects.
  Future<void> initPush() => _pushInitialization ??= _initializePush();

  Future<void> _initializePush() async {
    final token = await _pushService.init(
      onForegroundMessage: handleForegroundPush,
      onMessageOpenedApp: handlePushActivation,
    );
    if (token != null) await setPushToken(token);
    _pushTokenSubscription = _pushService.onTokenRefresh.listen(
      (replacement) => unawaited(setPushToken(replacement)),
    );
  }

  Future<void> setPushToken(String token) {
    final generation = _pushLifecycleGeneration.current;
    final registrationSuspended = _pushRegistrationSuspended;
    return _queuePushLifecycle(() async {
      final alreadyRegistered =
          _pushToken == token && _registeredPushToken == token;
      _pushToken = token;
      if (_pushLifecycleGeneration.isStale(generation) ||
          registrationSuspended ||
          _pushRegistrationSuspended ||
          alreadyRegistered) {
        return;
      }
      await _unregisterPushTokenNow();
      if (_pushLifecycleGeneration.isStale(generation) ||
          _pushRegistrationSuspended) {
        return;
      }
      final credentials = _credentials();
      if (credentials != null) {
        await _registerPushTokenNow(credentials, generation);
      }
    });
  }

  Future<void> _queuePushLifecycle(Future<void> Function() operation) =>
      _pushLifecycleQueue.run(operation);

  Future<void> registerPushToken(UserCredentials credentials) {
    final generation = _pushLifecycleGeneration.current;
    return _queuePushLifecycle(
      () => _registerPushTokenNow(credentials, generation),
    );
  }

  Future<void> _registerPushTokenNow(
    UserCredentials credentials,
    int generation,
  ) async {
    if (_pushLifecycleGeneration.isStale(generation) ||
        _pushRegistrationSuspended) {
      return;
    }
    final token = _pushToken;
    if (token == null) return;
    if (_registeredPushToken == token &&
        sameCredentials(_registeredPushCredentials, credentials)) {
      return;
    }
    await _unregisterPushTokenNow();
    if (_pushLifecycleGeneration.isStale(generation) ||
        _pushRegistrationSuspended) {
      return;
    }
    try {
      final identity = await _bestEffortIdentity();
      await _pushService.registerToken(
        credentials,
        token: token,
        platform: HostPlatform.isIOS ? 'ios' : 'android',
        deviceId: identity?.deviceId,
        deviceName: identity?.deviceName,
      );
      _registeredPushCredentials = credentials;
      _registeredPushToken = token;
    } on Object catch (_) {
      // Push registration is best-effort, same as TV notifications above.
    }
  }

  Future<void> unregisterPushToken() =>
      _queuePushLifecycle(_unregisterPushTokenNow);

  Future<void> _unregisterPushTokenNow() async {
    final credentials = _registeredPushCredentials;
    final token = _registeredPushToken;
    _registeredPushCredentials = null;
    _registeredPushToken = null;
    if (credentials == null || token == null) return;
    try {
      await _pushService.unregisterToken(credentials, token: token);
    } on Object catch (_) {
      // Best-effort cleanup; do not retain a stale local association on failure.
    }
  }

  void _onPushNotification(TvNotificationItem item) {
    final ownsNotification = _captureOwnership();
    _runInBackground(receive(item, shouldCommit: ownsNotification));
  }

  bool Function() _captureOwnership({
    UserCredentials? credentials,
    int? notificationGeneration,
  }) {
    final ownedCredentials = credentials ?? _credentials();
    final ownedNotificationGeneration =
        notificationGeneration ?? sessionGeneration.current;
    final ownsApp = ownedCredentials == null
        ? null
        : _captureAppOwnership(ownedCredentials);
    return () =>
        ownsApp != null &&
        !sessionGeneration.isStale(ownedNotificationGeneration) &&
        ownsApp();
  }

  Future<void> handleForegroundPush(PushMessage message) async {
    final id = message.notificationId;
    final credentials = _credentials();
    if (id == null || credentials == null) return;
    final notificationGeneration = sessionGeneration.current;
    try {
      await _reconcileUnread(
        credentials,
        presentOnlyId: id,
        notificationGeneration: notificationGeneration,
      );
    } on Object catch (_) {
      // Push reconciliation is best-effort and never trusts payload content.
    }
  }

  Future<void> handlePushActivation(PushMessage message) =>
      handleActivation(message.notificationId);

  Future<void> handleActivation(String? notificationId) async {
    final id = canonicalNotificationId(notificationId);
    if (id == null) return;
    final credentials = _credentials();
    if (credentials == null) {
      _pendingActivations.add(id);
      return;
    }
    final accountPrincipal = credentials.username;
    final notificationGeneration = sessionGeneration.current;
    final ownsNotification = _captureOwnership(
      credentials: credentials,
      notificationGeneration: notificationGeneration,
    );
    if (!ownsNotification()) return;

    try {
      final (session, unread) = await _service.fetchUnread(credentials);
      if (!ownsNotification()) return;
      if (!store.selectOwner(
        server: credentials.server,
        accountPrincipal: accountPrincipal,
        session: session,
      )) {
        clearOwner();
        return;
      }
      if (session.availableChannels.isNotEmpty) {
        await store.setServerChannels(
          session.availableChannels,
          shouldCommit: ownsNotification,
        );
        if (!ownsNotification()) return;
      }
      final authorizedUnread = session.isAdmin
          ? unread
          : unread.where((item) => !item.adminOnly).toList(growable: false);
      await store.syncUnreadWithServer(
        authorizedUnread,
        shouldCommit: ownsNotification,
      );
      if (!ownsNotification()) return;
      if (!await _refreshUnreadCount(shouldCommit: ownsNotification)) {
        return;
      }
      final matching = authorizedUnread.where((item) => item.id == id);
      if (matching.isEmpty) return;
      final destination = notificationDestinationFor(matching.first.channel);
      if (!ownsNotification() || destination == null || !_markActivated(id)) {
        return;
      }
      _activationController.add(destination);
    } on Object catch (_) {
      // A tap without an authorized REST record is a safe no-op.
    }
  }

  Future<void> _drainPendingActivations() async {
    if (_credentials() == null || _pendingActivations.isEmpty) {
      return;
    }
    final pending = _pendingActivations.toList(growable: false);
    _pendingActivations.clear();
    for (final id in pending) {
      await handleActivation(id);
    }
  }

  /// Handles a `device.deregister` push. The event is broadcast to the whole
  /// playlist channel, so every device sees it - only the one whose id matches
  /// signs out and returns to the pairing screen.
  void _onDeviceDeregisterPush(String deviceId) {
    unawaited(() async {
      final myId = await _bestEffortIdentity().then((i) => i?.deviceId);
      if (myId != null && myId == deviceId) {
        await _signOut();
      }
    }());
  }

  Future<DeviceIdentity?> _bestEffortIdentity() async {
    try {
      return await _deviceIdentityService.resolve();
    } on Object catch (_) {
      return null;
    }
  }

  Future<void> receive(
    TvNotificationItem item, {
    bool Function()? shouldCommit,
  }) async {
    if (shouldCommit != null && !shouldCommit()) return;
    final inserted = await store.add(item, shouldCommit: shouldCommit);
    if (!inserted || (shouldCommit != null && !shouldCommit())) return;
    if (!await _refreshUnreadCount(shouldCommit: shouldCommit)) {
      return;
    }
    // Only surface the notification in the stream (banners/toasts) if the
    // channel passes the user's subscription filter.
    final subscribed = await store.subscribedChannels();
    if (shouldCommit != null && !shouldCommit()) return;
    if (subscribed.isEmpty || subscribed.contains(item.channel)) {
      _notificationController.add(item);
    }
  }

  // Bounded like TvNotificationStore's own cap, so a long-running session
  // can't grow this set without limit.
  bool _markActivated(String id) {
    if (_activatedNotificationIds.contains(id)) return false;
    if (_activatedNotificationIds.length >= _maxActivatedNotificationIds) {
      _activatedNotificationIds.remove(_activatedNotificationIds.first);
    }
    _activatedNotificationIds.add(id);
    return true;
  }

  void dispose() {
    _pushTokenSubscription?.cancel().ignore();
    unawaited(_notificationController.close());
    unawaited(_activationController.close());
    unawaited(_pushService.dispose());
  }
}
