import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:http/http.dart' as http;
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:web/web.dart' as web;

PlayerAdapter createWebVideoBackend() => WebVideoBackend();

// --- hls.js interop (github.com/video-dev/hls.js) ---------------------

@JS('Hls')
extension type _JsHls._(JSObject _) implements JSObject {
  external factory _JsHls([JSAny? config]);
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement video);
  external void on(String event, JSFunction listener);
  external void destroy();
}

@JS('Hls.isSupported')
external bool _hlsIsSupported();

@JS()
extension type _HlsErrorData._(JSObject _) implements JSObject {
  external bool get fatal;
  external String? get details;
}

// --- mpegts.js interop (github.com/xqq/mpegts.js) ----------------------

@JS('mpegts.createPlayer')
external _JsMpegtsPlayer _mpegtsCreatePlayer(JSAny config);

@JS()
extension type _JsMpegtsPlayer._(JSObject _) implements JSObject {
  external void attachMediaElement(web.HTMLVideoElement video);
  external void load();
  external void on(String event, JSFunction listener);
  external void destroy();
}

@JS()
extension type _MpegtsFeatureList._(JSObject _) implements JSObject {
  external bool get mseLivePlayback;
}

@JS('mpegts.getFeatureList')
external _MpegtsFeatureList _mpegtsGetFeatureList();

/// Renders through a browser `<video>` element: hls.js for HLS manifests,
/// mpegts.js for raw MPEG-TS, and the browser's own native playback for
/// everything else (direct-proxied VOD in a browser-playable container, or
/// Safari's built-in HLS). Mirrors the editor's own in-app floating player
/// (`resources/js/vendor/stream-viewer.js`), which drives the same three
/// libraries the same way.
///
/// Every load appends `proxy=true&player=true` to the stream URL so the
/// editor routes it through `M3uProxyApiController::channelPlayer`/
/// `episodePlayer`, applying the admin's In-App Player Transcoding profile
/// (Settings > Proxy) instead of the playlist-level profile meant for
/// external clients (VLC, Kodi, etc.) -- a browser can't decode everything
/// those profiles output, so it needs the same compatibility-first path the
/// editor's own player uses. The resolved format isn't known until the
/// server redirects, so each load first probes the URL's `Content-Type`
/// (reading only the response headers, then cancelling the body) before
/// picking which of the three playback paths above to use.
class WebVideoBackend implements PlayerAdapter, HtmlViewProvider {
  WebVideoBackend() : platformViewType = 'm3u_tv/web_video_view-$_nextViewId' {
    _nextViewId += 1;
    _video
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'contain'
      ..style.backgroundColor = 'transparent'
      ..playsInline = true
      ..controls = false;
    _attachVideoListeners();
    ui_web.platformViewRegistry.registerViewFactory(
      platformViewType,
      (int viewId) => _video,
    );
  }

  static int _nextViewId = 0;

  @override
  final String platformViewType;

  final web.HTMLVideoElement _video =
      web.document.createElement('video') as web.HTMLVideoElement;
  final http.Client _probeClient = http.Client();

  _JsHls? _hls;
  _JsMpegtsPlayer? _mpegts;
  final List<({String type, JSFunction listener})> _videoListeners =
      <({String type, JSFunction listener})>[];

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.webVideo,
  );
  int _generation = 0;

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities.webVideo;

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    final generation = ++_generation;
    _emit(
      _state.copyWith(
        backend: PlaybackBackend.webVideo,
        status: PlaybackStatus.loading,
        source: source,
        position: source.startPosition,
      ),
    );

    _teardownActivePlayer();

    final uri = _withInAppPlayerParams(source.uri);
    final contentType = await _probeContentType(uri);
    if (generation != _generation) return; // superseded by a newer load()

    try {
      if (_looksLikeHls(contentType, uri)) {
        await _loadHls(uri);
      } else if (_looksLikeMpegTs(contentType, uri)) {
        await _loadMpegTs(uri, isLive: source.isLive);
      } else {
        _video.src = uri.toString();
      }
    } on Object catch (error) {
      throw PlaybackException(
        message: 'Web video load failed: $error',
        backend: PlaybackBackend.webVideo,
        code: 'web_video_load_failed',
        recoverable: true,
      );
    }

    if (source.startPosition > Duration.zero) {
      _video.currentTime = source.startPosition.inMilliseconds / 1000;
    }

    // Every other backend autoplays once loaded (mpv/ExoPlayer default to
    // playing on load) -- PlayerScreen only calls orchestrator.play() from
    // its own manual play/pause toggle, never after a load completes, so
    // this backend has to start itself the same way. Safe to call this
    // unprompted: load() only ever runs as a result of the user picking
    // something to watch, so the browser's autoplay gesture requirement is
    // already satisfied.
    await play();
  }

  @override
  Future<void> play() async {
    try {
      await _video.play().toDart;
    } on Object {
      // Autoplay can be rejected (no user gesture yet); the player screen's
      // own play/pause control is the user gesture that normally follows.
    }
  }

  @override
  Future<void> pause() async => _video.pause();

  @override
  Future<void> seek(Duration position) async {
    _video.currentTime = position.inMilliseconds / 1000;
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    ++_generation;
    _teardownActivePlayer();
    _video.removeAttribute('src');
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {}

  @override
  Future<void> setSubtitleTrack(String? trackId) async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    _video.playbackRate = speed;
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  @override
  Future<void> dispose() async {
    ++_generation;
    _teardownActivePlayer();
    for (final entry in _videoListeners) {
      _video.removeEventListener(entry.type, entry.listener);
    }
    _videoListeners.clear();
    _probeClient.close();
    await _stateController.close();
    await _errorController.close();
  }

  // --- Format probing -----------------------------------------------------

  /// Resolves [uri]'s `Content-Type` by reading only the response headers,
  /// then cancelling the body -- avoids buffering a live stream's unbounded
  /// body just to learn its format. Empty when the request itself fails;
  /// the caller falls through to native `<video>` playback, which will
  /// surface its own error if the URL genuinely doesn't work.
  Future<String> _probeContentType(Uri uri) async {
    try {
      final streamed = await _probeClient.send(http.Request('GET', uri));
      final contentType = (streamed.headers['content-type'] ?? '')
          .toLowerCase();
      unawaited(streamed.stream.listen((_) {}).cancel());
      return contentType;
    } on Object {
      return '';
    }
  }

  bool _looksLikeHls(String contentType, Uri uri) =>
      contentType.contains('mpegurl') || uri.path.endsWith('.m3u8');

  bool _looksLikeMpegTs(String contentType, Uri uri) =>
      contentType.contains('mp2t') || uri.path.endsWith('.ts');

  Uri _withInAppPlayerParams(String rawUri) {
    final parsed = Uri.parse(rawUri);
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return parsed;
    final params = Map<String, String>.from(parsed.queryParameters)
      ..putIfAbsent('proxy', () => 'true')
      ..putIfAbsent('player', () => 'true');
    return parsed.replace(queryParameters: params);
  }

  // --- hls.js ---------------------------------------------------------

  Future<void> _loadHls(Uri uri) async {
    await _ensureScriptLoaded(_hlsScriptUrl, globalName: 'Hls');
    if (!_hlsIsSupported()) {
      // Safari and other browsers with built-in HLS support.
      _video.src = uri.toString();
      return;
    }
    final hls = _JsHls(
      <String, Object?>{'enableWorker': true, 'lowLatencyMode': true}.jsify(),
    );
    _hls = hls;
    hls
      ..on('hlsError', _onHlsError.toJS)
      ..loadSource(uri.toString())
      ..attachMedia(_video);
  }

  void _onHlsError(JSString eventName, _HlsErrorData data) {
    if (!data.fatal) return;
    _errorController.add(
      PlaybackError(
        backend: PlaybackBackend.webVideo,
        message: 'HLS playback failed: ${data.details ?? 'unknown error'}',
        code: 'hls_fatal_error',
        recoverable: true,
      ),
    );
  }

  // --- mpegts.js --------------------------------------------------------

  Future<void> _loadMpegTs(Uri uri, {required bool isLive}) async {
    await _ensureScriptLoaded(_mpegtsScriptUrl, globalName: 'mpegts');
    if (!_mpegtsGetFeatureList().mseLivePlayback) {
      _video.src = uri.toString();
      return;
    }
    final player = _mpegtsCreatePlayer(
      <String, Object?>{
        'type': 'mpegts',
        'url': uri.toString(),
        'isLive': isLive,
        'enableWorker': true,
        'cors': true,
        'liveBufferLatencyChasing': false,
      }.jsify()!,
    );
    _mpegts = player;
    player
      ..on('error', _onMpegtsError.toJS)
      ..attachMediaElement(_video)
      ..load();
  }

  void _onMpegtsError(JSString type, JSString details, JSAny? info) {
    _errorController.add(
      PlaybackError(
        backend: PlaybackBackend.webVideo,
        message: 'MPEG-TS playback failed: ${type.toDart}: ${details.toDart}',
        code: 'mpegts_error',
        recoverable: true,
      ),
    );
  }

  void _teardownActivePlayer() {
    final hls = _hls;
    if (hls != null) {
      try {
        hls.destroy();
      } on Object {
        // Best effort, mirrors stream-viewer.js's own cleanup().
      }
      _hls = null;
    }
    final mpegts = _mpegts;
    if (mpegts != null) {
      try {
        mpegts.destroy();
      } on Object {
        // Best effort, mirrors stream-viewer.js's own cleanup().
      }
      _mpegts = null;
    }
  }

  // --- <video> element events ---------------------------------------------

  void _attachVideoListeners() {
    void add(String type, void Function(web.Event event) handler) {
      final listener = handler.toJS;
      _video.addEventListener(type, listener);
      _videoListeners.add((type: type, listener: listener));
    }

    add('loadedmetadata', (_) => _emitFromVideo(PlaybackStatus.ready));
    add('playing', (_) => _emitFromVideo(PlaybackStatus.playing));
    add('pause', (_) => _emitFromVideo(PlaybackStatus.paused));
    add('waiting', (_) => _emitFromVideo(PlaybackStatus.buffering));
    add('timeupdate', (_) => _emitFromVideo(_state.status));
    add('ended', (_) => _emitFromVideo(PlaybackStatus.completed));
    add('error', (_) {
      final error = _video.error;
      _errorController.add(
        PlaybackError(
          backend: PlaybackBackend.webVideo,
          message: error?.message.isNotEmpty == true
              ? error!.message
              : 'Video playback failed',
          code: 'video_element_error',
          recoverable: true,
        ),
      );
    });
  }

  void _emitFromVideo(PlaybackStatus status) {
    final durationSeconds = _video.duration;
    _emit(
      _state.copyWith(
        status: status,
        position: Duration(
          milliseconds: (_video.currentTime * 1000).round(),
        ),
        duration: durationSeconds.isFinite
            ? Duration(milliseconds: (durationSeconds * 1000).round())
            : null,
      ),
    );
  }

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }
}

String get _hlsScriptUrl => _assetUrl('js/hls.min.js');
String get _mpegtsScriptUrl => _assetUrl('js/mpegts.min.js');

String _assetUrl(String name) =>
    Uri.parse(web.document.baseURI).resolve(name).toString();

final Map<String, Future<void>> _scriptLoads = <String, Future<void>>{};

/// Injects `<script src=[url]>` once per [url] and waits for it to finish
/// executing, so [globalName] (`Hls`/`mpegts`) is defined before the caller
/// touches it. Cached per URL: concurrent/repeated loads of the same library
/// share one `<script>` tag and one wait.
Future<void> _ensureScriptLoaded(String url, {required String globalName}) {
  if (globalContext.has(globalName)) return Future<void>.value();
  return _scriptLoads.putIfAbsent(url, () async {
    final completer = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..src = url
      ..async = false
      ..addEventListener(
        'load',
        (JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }.toJS,
      )
      ..addEventListener(
        'error',
        (JSAny? _) {
          if (!completer.isCompleted) {
            completer.completeError(
              StateError(
                'Failed to load $url -- run scripts/fetch-web-assets.sh.',
              ),
            );
          }
        }.toJS,
      );
    web.document.head!.appendChild(script);
    return completer.future;
  });
}
