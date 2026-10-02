// ignore_for_file: prefer_initializing_formals

import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

/// Signature of the editor call that stops one player session's proxy stream.
typedef StopPlayerStream =
    Future<void> Function({
      required String type,
      required int streamId,
      required String clientId,
    });

/// [PlaybackStreamSessionGateway] for streams played through the connected
/// m3u-editor's Xtream routes. Each session's URL carries a `client_id`,
/// which the editor forwards to its proxy, and ending the session asks the
/// editor to stop that client's proxy stream. The proxy then drops the stream
/// right away (including any transcode) instead of on its idle timeout, unless
/// another viewer is still on it. The same id lets the editor hand a seeking
/// catchup player its own running stream back on every Range request, which
/// matters for ExoPlayer: unlike mpv it never caches the editor's redirect.
///
/// Every editor stream is tracked, whatever this account's own proxy access:
/// the editor decides server-side whether a stream goes through the proxy
/// (playlist or channel proxy setting, provider profiles), and stopping a
/// session that never reached the proxy is a no-op. `serverBase` returns the
/// editor URL stream URLs are built from, or null when signed out. Any other
/// URL (direct provider, AIOStreams) is untouched.
class EditorStreamSessionGateway implements PlaybackStreamSessionGateway {
  EditorStreamSessionGateway({
    required String? Function() serverBase,
    required StopPlayerStream stopPlayerStream,
  }) : _serverBase = serverBase,
       _stopPlayerStream = stopPlayerStream;

  final String? Function() _serverBase;
  final StopPlayerStream _stopPlayerStream;

  /// Xtream route segment -> the editor's stop endpoint `type`, keyed with
  /// the number of path segments that route has.
  static const Map<String, ({String type, int segments})> _routes = {
    'live': (type: 'live', segments: 4),
    'movie': (type: 'vod', segments: 4),
    'series': (type: 'series', segments: 4),
    'timeshift': (type: 'catchup', segments: 6),
  };

  @override
  PlaybackSource attachClientId(PlaybackSource source, String clientId) {
    if (_streamFor(source.uri) == null) return source;
    final separator = source.uri.contains('?') ? '&' : '?';
    return source.copyWith(uri: '${source.uri}${separator}client_id=$clientId');
  }

  @override
  Future<void> releaseStream(PlaybackSource source, String clientId) async {
    final stream = _streamFor(source.uri);
    if (stream == null) return;
    await _stopPlayerStream(
      type: stream.type,
      streamId: stream.id,
      clientId: clientId,
    );
  }

  /// The stop endpoint's type and id for an editor Xtream stream URL
  /// (`/live|movie|series/u/p/{id}.ext` or
  /// `/timeshift/u/p/{duration}/{start}/{id}.ext`), or null.
  ({String type, int id})? _streamFor(String url) {
    final server = _serverBase();
    if (server == null || !url.startsWith(server)) return null;
    final segments = Uri.tryParse(url.substring(server.length))?.pathSegments;
    if (segments == null || segments.isEmpty) return null;
    final route = _routes[segments.first];
    if (route == null || segments.length != route.segments) return null;
    final id = int.tryParse(segments.last.split('.').first);
    if (id == null) return null;
    return (type: route.type, id: id);
  }
}
