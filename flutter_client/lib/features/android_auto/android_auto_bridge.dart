import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/features/carplay/car_catalog.dart';
import 'package:m3u_tv/features/carplay/carplay_controller.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

/// Answers Android Auto (`CarMediaService.kt`): the lists it browses, and
/// the stream for a channel picked there, which the service plays itself.
///
/// Media ids: `root`, `favorites`, `live`, `category:<id>`, and for a
/// channel `channel:<id>@<list>`, where `<list>` is the list it was picked
/// from (`favorites` or `category:<id>`), for next/previous channel.
///
/// A channel picked while the app is in front plays in the phone's
/// full-screen player (`playOnPhone`), as with CarPlay; otherwise the
/// service plays it on its own player.
///
/// Runs outside the widget tree, like CarPlay: the car can start the app
/// with no activity, and then no widget is built.
class AndroidAutoBridge {
  AndroidAutoBridge(
    this._catalog, {
    MethodChannel? channel,
    PlaybackStreamSessionGateway? streamSessions,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _streamSessions = streamSessions ?? _catalog.streamSessions();

  static const channelName = 'm3u_tv/android_auto';

  /// The running bridge (Android only), set by `main()`.
  static AndroidAutoBridge? instance;

  /// Set by the phone's shell while it's up: plays a channel in the
  /// full-screen player.
  CarPlayChannelHandler? onPlayChannel;

  // The shell can still be building when the app has just come to the
  // front (the car started the app, and the activity has only now opened).
  static const _phoneShellWait = Duration(seconds: 5);
  static const _phoneShellPoll = Duration(milliseconds: 100);

  /// Android Auto pages long lists itself; the driver never scrolls far.
  static const maxItems = 200;

  final CarCatalog _catalog;
  final MethodChannel _channel;
  final PlaybackStreamSessionGateway _streamSessions;

  ({PlaybackSource source, String clientId})? _activeStream;
  int _clientIdSeq = 0;

  void start() => _channel.setMethodCallHandler(handle);

  @visibleForTesting
  Future<Object?> handle(MethodCall call) async {
    await _catalog.appState.ensureBooted();
    final arguments = call.arguments;
    final mediaId = arguments is Map ? arguments['mediaId'] as String? : null;
    switch (call.method) {
      case 'children':
        return _children(mediaId ?? 'root');
      case 'item':
        return mediaId == null ? null : _item(mediaId);
      case 'resolve':
        return mediaId == null ? null : _resolve(mediaId);
      case 'neighbour':
        final step = arguments is Map ? arguments['step'] as int? : null;
        if (mediaId == null || step == null) return null;
        return _neighbour(mediaId, step);
      case 'metadata':
        return mediaId == null ? null : _metadata(mediaId);
      case 'playOnPhone':
        return mediaId != null && await _playOnPhone(mediaId);
      case 'release':
        await _releaseStream();
        return null;
    }
    throw MissingPluginException(call.method);
  }

  Future<List<Map<String, Object?>>> _children(String parentId) async {
    final l10n = _catalog.l10n;
    if (parentId == 'root') {
      return [
        _folder('favorites', l10n.carPlayFavorites),
        _folder('live', l10n.navLiveTv),
      ];
    }
    if (parentId == 'favorites') {
      final channels = await _catalog.favoriteChannels(maxItems);
      return [for (final c in channels) _channelEntry(c, 'favorites')];
    }
    if (parentId == 'live') {
      return [
        for (final category in _catalog.liveCategories(maxItems))
          _folder('category:${category.id}', category.name),
      ];
    }
    if (parentId.startsWith('category:')) {
      final categoryId = parentId.substring('category:'.length);
      final (:channels, context: _) = await _catalog.categoryChannels(
        categoryId,
        maxItems,
      );
      return [for (final c in channels) _channelEntry(c, parentId)];
    }
    return const [];
  }

  Future<Map<String, Object?>?> _item(String mediaId) async {
    final parsed = _parseChannel(mediaId);
    if (parsed == null) return null;
    final channel = await _catalog.channelById(parsed.channelId);
    return channel == null ? null : _channelEntry(channel, parsed.list);
  }

  Future<Map<String, Object?>?> _metadata(String mediaId) => _item(mediaId);

  /// The stream to play for a channel, as a new stream session; the last
  /// one is released first.
  Future<Map<String, Object?>?> _resolve(String mediaId) async {
    final parsed = _parseChannel(mediaId);
    if (parsed == null) return null;
    final channel = await _catalog.channelById(parsed.channelId);
    if (channel == null) return null;
    await _releaseStream();
    final clientId =
        'm3utv-auto-${DateTime.now().millisecondsSinceEpoch}-${_clientIdSeq++}';
    final source = _streamSessions.attachClientId(
      _catalog.sourceFor(channel),
      clientId,
    );
    _activeStream = (source: source, clientId: clientId);
    return {
      ..._channelEntry(channel, parsed.list),
      'uri': source.uri,
      'headers': source.headers,
      'userAgent': source.userAgent,
    };
  }

  /// Opens a channel in the full-screen player; false when the phone's
  /// shell isn't up to do it.
  Future<bool> _playOnPhone(String mediaId) async {
    final parsed = _parseChannel(mediaId);
    if (parsed == null) return false;
    var handler = onPlayChannel;
    final deadline = DateTime.now().add(_phoneShellWait);
    while (handler == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_phoneShellPoll);
      handler = onPlayChannel;
    }
    if (handler == null) return false;
    final channel = await _catalog.channelById(parsed.channelId);
    if (channel == null) return false;
    handler(channel, await _contextFor(parsed.list));
    return true;
  }

  Future<Map<String, Object?>?> _neighbour(String mediaId, int step) async {
    final parsed = _parseChannel(mediaId);
    if (parsed == null) return null;
    final context = await _contextFor(parsed.list);
    final channels = context.length > 1 ? context : _catalog.allChannels();
    final next = await channels.neighbour(parsed.channelId, step);
    if (next == null) return null;
    return _resolve(_channelId(next, parsed.list));
  }

  Future<ChannelContext> _contextFor(String list) async {
    if (list == 'favorites') {
      return ListChannelContext(await _catalog.favoriteChannels(maxItems));
    }
    if (list.startsWith('category:')) {
      final (channels: _, :context) = await _catalog.categoryChannels(
        list.substring('category:'.length),
        0,
      );
      return context;
    }
    return _catalog.allChannels();
  }

  Future<void> _releaseStream() async {
    final active = _activeStream;
    _activeStream = null;
    if (active == null) return;
    try {
      await _streamSessions.releaseStream(active.source, active.clientId);
    } on Object catch (error) {
      debugPrint('[AndroidAuto] Stream release failed: $error');
    }
  }

  Map<String, Object?> _folder(String id, String title) => {
    'id': id,
    'title': title,
    'playable': false,
  };

  Map<String, Object?> _channelEntry(Channel channel, String list) => {
    'id': _channelId(channel, list),
    'title': channel.name,
    'subtitle': _catalog.currentProgramme(channel),
    'artworkUri': channel.logoUrl,
    'playable': true,
  };

  static String _channelId(Channel channel, String list) =>
      'channel:${channel.id}@$list';

  static ({int channelId, String list})? _parseChannel(String mediaId) {
    if (!mediaId.startsWith('channel:')) return null;
    final rest = mediaId.substring('channel:'.length);
    final at = rest.indexOf('@');
    final id = int.tryParse(at == -1 ? rest : rest.substring(0, at));
    if (id == null) return null;
    return (channelId: id, list: at == -1 ? 'live' : rest.substring(at + 1));
  }
}
