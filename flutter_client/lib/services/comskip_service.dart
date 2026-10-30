import 'package:flutter/foundation.dart' show debugPrint;
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// One detected commercial break, in seconds from the start of the
/// recording.
typedef ComskipSegment = ({double start, double end});

/// Fetches a DVR recording's comskip EDL (commercial-break) segments for the
/// player.
class ComskipService {
  ComskipService({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient(timeout: const Duration(seconds: 8));

  final ApiClient _api;

  /// The segments for a recording, or an empty list when there are none.
  /// Fire-and-forget safe: an older server, a recording with comskip
  /// disabled, or any fetch failure yields an empty list rather than an
  /// error, so the player behaves exactly as if there were no EDL at all.
  ///
  /// [edlUrl] comes from the player args when the play path carried it. When
  /// it's absent and [canLookUp] is set, it is resolved through
  /// [xtreamService] from [type], [streamId] and [seriesId] (see
  /// [_resolveEdlUrl]).
  Future<List<ComskipSegment>> segmentsFor({
    required String? edlUrl,
    required String type,
    int? streamId,
    int? seriesId,
    XtreamService? xtreamService,
    bool canLookUp = false,
  }) async {
    var url = edlUrl;
    if (url == null || url.isEmpty) {
      if (!canLookUp || xtreamService == null) return const [];
      url = await _resolveEdlUrl(xtreamService, type, streamId, seriesId);
      if (url == null || url.isEmpty) return const [];
    }

    try {
      final response = await _api.send(
        'GET',
        _resolveEdlUri(Uri.parse(url), xtreamService),
      );
      if (response.statusCode != 200) return const [];
      final decoded = await response.json();
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map((segment) {
            final start = segment['start'];
            final end = segment['end'];
            if (start is! num || end is! num) return null;
            return (start: start.toDouble(), end: end.toDouble());
          })
          .whereType<ComskipSegment>()
          .toList(growable: false);
    } on Object catch (error) {
      debugPrint('Comskip: failed to fetch EDL: $error');
      return const [];
    }
  }

  /// Lazily resolves an `edl_url` for play paths that don't carry the field
  /// on the originating `PlayerArgs` - notably Continue Watching for series
  /// episodes, which only holds a `Progress` and a `Series` summary. Callers
  /// gate this on the DVR feature to keep non-DVR accounts off the extra
  /// call (the series branch fetches the full `get_series_info` payload).
  Future<String?> _resolveEdlUrl(
    XtreamService service,
    String type,
    int? streamId,
    int? seriesId,
  ) async {
    try {
      if (type == 'vod' && streamId != null) {
        final info = await service.getVodInfo(streamId);
        return info.edlUrl;
      }
      if (type == 'series' && seriesId != null) {
        final info = await service.getSeriesInfo(seriesId);
        final episode = info.episodesBySeason.values
            .expand((eps) => eps)
            .where((e) => e.id == '$streamId')
            .firstOrNull;
        return episode?.edlUrl;
      }
    } on Object catch (error) {
      debugPrint('Comskip: failed to resolve EDL: $error');
    }
    return null;
  }

  /// Rewrites a localhost/127.0.0.1 EDL host to the connected Xtream server's
  /// real scheme/host/port. The m3u-editor backend occasionally returns an
  /// edl_url pointing at its own loopback (e.g. `http://localhost/dvr/...`)
  /// instead of the public host, which makes the client hit the user's own
  /// machine. Only rewrites when the parsed host is loopback AND we have
  /// configured credentials; otherwise returns the input unchanged so the
  /// existing failure path runs untouched.
  Uri _resolveEdlUri(Uri edlUri, XtreamService? service) {
    final host = edlUri.host.toLowerCase();
    if (host != 'localhost' && host != '127.0.0.1') return edlUri;
    final server = service?.credentials?.server;
    if (server == null) return edlUri;
    final serverUri = Uri.tryParse(server);
    if (serverUri == null) return edlUri;
    return edlUri.replace(
      scheme: serverUri.scheme,
      host: serverUri.host,
      port: serverUri.port,
    );
  }
}
