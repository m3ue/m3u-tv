// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart' hide Category;
import 'package:m3u_tv/services/app_state_controller.dart'
    show MediaRequestOwner;
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// The requesting guest's media requests list and the request search,
/// submit, dismiss and refresh calls, split out of `AppStateController`.
/// Like `DvrCoordinator`, every async path re-checks the ownership closure the
/// controller hands it.
class RequestsCoordinator {
  RequestsCoordinator({
    required this.xtreamService,
    required UserCredentials? Function() credentials,
    required bool Function() Function(
      UserCredentials credentials, {
      MediaRequestOwner? owner,
    })
    captureOwnership,
    required bool Function() hasRequestsFeature,
    required VoidCallback notifyListeners,
  }) : _credentials = credentials,
       _captureOwnership = captureOwnership,
       _hasRequestsFeature = hasRequestsFeature,
       _notifyListeners = notifyListeners;

  final XtreamService xtreamService;
  final UserCredentials? Function() _credentials;
  final bool Function() Function(
    UserCredentials credentials, {
    MediaRequestOwner? owner,
  })
  _captureOwnership;
  final bool Function() _hasRequestsFeature;
  final VoidCallback _notifyListeners;

  List<MediaRequestSummary> _mediaRequests = const <MediaRequestSummary>[];
  List<MediaRequestSummary> get requests => _mediaRequests;

  /// Drops the list (a source switch or sign-out). The caller notifies.
  void reset() => _mediaRequests = const <MediaRequestSummary>[];

  /// Applies the list fetched alongside a content load. The caller notifies.
  void applyFetched(List<MediaRequestSummary> requests) =>
      _mediaRequests = requests;

  /// Mirrors `DvrCoordinator.onStatusPush`: updates the local requests list
  /// in place  /// from the lightweight `request.status` push (approved/rejected/completed
  /// by MediaRequestStatusEvent on the server) instead of re-polling
  /// request_history.
  void onStatusPush(
    MediaRequestSummary request,
    bool Function() ownsWork,
  ) {
    if (!ownsWork()) return;
    final next = [..._mediaRequests];
    final index = next.indexWhere((r) => r.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.insert(0, request);
    }
    if (!ownsWork()) return;
    _mediaRequests = next;
    if (!ownsWork()) return;
    _notifyListeners();
  }

  /// Searches guest-enabled Arr integrations via `request_search`. Thin
  /// pass-through — the Requests screen owns its own search-in-flight/error
  /// state since results aren't part of the app's persistent state.
  Future<List<ContentRequestSearchResult>> searchContentRequests(
    String query, {
    String? type,
  }) async {
    final credentials = _credentials();
    if (credentials == null) return const <ContentRequestSearchResult>[];
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return const <ContentRequestSearchResult>[];
    final results = await xtreamService.searchContentRequestsFor(
      credentials,
      query,
      type: type,
    );
    if (!ownsWork()) return const <ContentRequestSearchResult>[];
    return results;
  }

  /// Submits a content request and adds it to the local requests list so it
  /// shows up immediately, without waiting for a `request.status` push.
  Future<MediaRequestSummary> submitContentRequest({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
    MediaRequestOwner? requestOwner,
  }) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(
      credentials,
      owner: requestOwner,
    );
    if (!ownsWork()) {
      throw StateError('Xtream credentials not configured');
    }
    final request = await xtreamService.submitContentRequestFor(
      credentials,
      type: type,
      integrationId: integrationId,
      externalId: externalId,
      seasons: seasons,
    );
    if (!ownsWork()) return request;
    final next = [request, ..._mediaRequests];
    if (!ownsWork()) return request;
    _mediaRequests = next;
    if (!ownsWork()) return request;
    _notifyListeners();
    return request;
  }

  /// Dismisses a completed or rejected request and removes it locally.
  Future<void> dismissMediaRequest(int requestId) async {
    final credentials = _credentials();
    if (credentials == null) {
      throw StateError('Xtream credentials not configured');
    }
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    await xtreamService.dismissMediaRequest(requestId);
    if (!ownsWork()) return;
    final next = _mediaRequests
        .where((request) => request.id != requestId)
        .toList(growable: false);
    if (!ownsWork()) return;
    _mediaRequests = next;
    if (!ownsWork()) return;
    _notifyListeners();
  }

  /// Refreshes the requesting guest's request history from the server. Used
  /// when the Requests screen becomes visible, since a push can be missed
  /// while the app is backgrounded and no other screen holds this list warm.
  Future<void> refreshMediaRequests() async {
    final credentials = _credentials();
    if (credentials == null || !_hasRequestsFeature()) return;
    final ownsWork = _captureOwnership(credentials);
    if (!ownsWork()) return;
    try {
      final requests = await xtreamService.getMediaRequests();
      if (!ownsWork()) return;
      _mediaRequests = requests;
      if (!ownsWork()) return;
      _notifyListeners();
    } on Object catch (error) {
      debugPrint('Requests: refresh failed: $error');
    }
  }
}
