import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:http/http.dart' as http;
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/playback/web_stream_kind.dart';
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
external _JsMpegtsPlayer _mpegtsCreatePlayer(
  JSAny mediaDataSource, [
  JSAny? config,
]);

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

@JS()
extension type _MpegtsErrorInfo._(JSObject _) implements JSObject {
  external int? get code;
}

// --- web/live_audio_filter.mjs interop (live AC-3/E-AC-3 -> AAC) ----------

@JS('M3uLiveAudioFilter.loader')
external JSAny get _liveAudioLoader;

// --- web/mkv_player.mjs interop (Mediabunny MKV -> fragmented MP4) --------

@JS('M3uMkvPlayer.open')
external JSPromise<_JsMkvHandle> _mkvOpen(
  web.HTMLVideoElement video,
  String url,
  double startSeconds,
  JSFunction onError,
);

@JS()
extension type _JsMkvHandle._(JSObject _) implements JSObject {
  external _JsMkvError? get error;
  external String? get videoCodec;
  external String? get audioCodec;
  external bool? get audioConverted;
  external void destroy();
}

@JS()
extension type _JsMkvError._(JSObject _) implements JSObject {
  external String? get code;
  external String? get message;
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

  static const String _transcodeHint =
      'An In-App Player Transcoding profile (Settings > Proxy in M3U '
      'Editor) can convert it.';

  /// DOMException's legacy code for NotSupportedError.
  static const int _notSupportedErrorCode = 9;

  @override
  final String platformViewType;

  final web.HTMLVideoElement _video =
      web.document.createElement('video') as web.HTMLVideoElement;
  final http.Client _probeClient = http.Client();

  _JsHls? _hls;
  _JsMpegtsPlayer? _mpegts;
  _JsMkvHandle? _mkv;

  /// Pending while [load] waits on a direct `<video>` source, so its first
  /// `loadedmetadata`/`error` resolves the load instead of reaching
  /// [onError]. An error there would start the orchestrator's mid-playback
  /// retry, whose own repeat of the error is dropped while it's still
  /// inside load(), leaving a stopped player with no message.
  Completer<web.MediaError?>? _pendingNativeLoad;

  /// How long [load] waits for a direct source's metadata before handing
  /// over to the normal buffering/error events.
  static const Duration _nativeLoadTimeout = Duration(seconds: 30);
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
        engine: null,
        source: source,
        position: source.startPosition,
      ),
    );

    _teardownActivePlayer();

    final uri = _withInAppPlayerParams(source.uri);
    final kind = await _probeStreamKind(uri, isLive: source.isLive);
    if (generation != _generation) return; // superseded by a newer load()

    try {
      switch (kind) {
        case WebStreamKind.hls:
          await _loadHls(uri);
        case WebStreamKind.mpegTs:
          await _loadMpegTs(uri, isLive: source.isLive);
        case WebStreamKind.matroska:
          await _loadMkv(uri, source.startPosition, generation);
        case WebStreamKind.native:
          _setEngine('native <video>');
          _video.src = uri.toString();
          await _awaitNativeLoad(generation);
      }
    } on PlaybackException {
      rethrow;
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
    // already satisfied. Not awaited: the promise stays pending until frames
    // arrive, and a load() stuck on it makes the orchestrator drop the error
    // when its retry fails too, leaving an endless spinner.
    unawaited(play());
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
    _settlePendingNativeLoad();
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
    _settlePendingNativeLoad();
    _teardownActivePlayer();
    for (final entry in _videoListeners) {
      _video.removeEventListener(entry.type, entry.listener);
    }
    _videoListeners.clear();
    _probeClient.close();
    await _stateController.close();
    await _errorController.close();
  }

  /// Waits for the direct source just assigned to [_video] to either load
  /// its metadata or fail, and turns a failure into a [PlaybackException]
  /// like the native backends throw for a file they can't open (e.g. an MKV
  /// the In-App Player Transcoding profile didn't convert).
  Future<void> _awaitNativeLoad(int generation) async {
    final pending = Completer<web.MediaError?>();
    _pendingNativeLoad = pending;
    final web.MediaError? error;
    try {
      error = await pending.future.timeout(
        _nativeLoadTimeout,
        onTimeout: () => null,
      );
    } finally {
      if (identical(_pendingNativeLoad, pending)) _pendingNativeLoad = null;
    }
    if (error == null || generation != _generation) return;
    final isNetworkError = error.code == web.MediaError.MEDIA_ERR_NETWORK;
    throw PlaybackException(
      message: isNetworkError
          ? "The video couldn't be loaded from the server."
          : "This browser can't play this video format. $_transcodeHint",
      backend: PlaybackBackend.webVideo,
      code: isNetworkError ? 'web_video_network' : 'web_video_unsupported',
      recoverable: true,
    );
  }

  void _settlePendingNativeLoad([web.MediaError? error]) {
    final pending = _pendingNativeLoad;
    if (pending == null || pending.isCompleted) return;
    _pendingNativeLoad = null;
    pending.complete(error);
  }

  // --- Format probing -----------------------------------------------------

  /// Resolves [uri]'s format by reading only the response headers, then
  /// cancelling the body -- avoids buffering a live stream's unbounded body
  /// just to learn its format. A failed request falls back to [uri]'s
  /// extension; the chosen player surfaces its own error if the URL genuinely
  /// doesn't work.
  Future<WebStreamKind> _probeStreamKind(
    Uri uri, {
    required bool isLive,
  }) async {
    var contentType = '';
    Uri? resolvedUri;
    try {
      final streamed = await _probeClient.send(http.Request('GET', uri));
      contentType = streamed.headers['content-type'] ?? '';
      if (streamed case http.BaseResponseWithUrl(:final url)) {
        resolvedUri = url;
      }
      unawaited(streamed.stream.listen((_) {}).cancel());
    } on Object {
      // Falls back to the requested URL.
    }
    return webStreamKind(
      contentType: contentType,
      requestedUri: uri,
      resolvedUri: resolvedUri,
      isLive: isLive,
    );
  }

  Uri _withInAppPlayerParams(String rawUri) {
    final parsed = Uri.parse(rawUri);
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return parsed;
    final params = Map<String, String>.from(parsed.queryParameters)
      ..putIfAbsent('proxy', () => 'true')
      ..putIfAbsent('player', () => 'true');
    return parsed.replace(queryParameters: params);
  }

  // --- MKV (web/mkv_player.mjs) ------------------------------------------

  /// Plays an MKV the server passed through unconverted by copying its
  /// packets into fragmented MP4 in the browser (Mediabunny + MSE), so it
  /// seeks like any direct file. Throws [PlaybackException] when the file's
  /// codecs can't play in this browser, the same way [_awaitNativeLoad] does.
  Future<void> _loadMkv(
    Uri uri,
    Duration startPosition,
    int generation,
  ) async {
    await _ensureScriptLoaded(
      _mkvScriptUrl,
      globalName: 'M3uMkvPlayer',
      isModule: true,
    );
    if (generation != _generation) return;
    final handle = await _mkvOpen(
      _video,
      uri.toString(),
      startPosition.inMilliseconds / 1000,
      _onMkvError.toJS,
    ).toDart;
    final error = handle.error;
    if (error != null) throw _mkvException(error);
    if (generation != _generation) {
      handle.destroy();
      return;
    }
    _mkv = handle;
    _setEngine(_mkvEngineLabel(handle));
  }

  /// "Mediabunny MKV: H.264, E-AC-3 to AAC", for the player diagnostics.
  String _mkvEngineLabel(_JsMkvHandle handle) {
    final video = _codecName(handle.videoCodec);
    final audioCodec = handle.audioCodec;
    final audio = audioCodec == null
        ? 'no audio'
        : handle.audioConverted ?? false
        ? '${_codecName(audioCodec)} to AAC'
        : _codecName(audioCodec);
    return 'Mediabunny MKV: $video, $audio';
  }

  static String _codecName(String? codec) => switch (codec) {
    'avc' => 'H.264',
    'hevc' => 'HEVC',
    'vp8' => 'VP8',
    'vp9' => 'VP9',
    'av1' => 'AV1',
    'aac' => 'AAC',
    'ac3' => 'AC-3',
    'eac3' => 'E-AC-3',
    'dts' => 'DTS',
    'truehd' => 'TrueHD',
    'opus' => 'Opus',
    'flac' => 'FLAC',
    'mp3' => 'MP3',
    'vorbis' => 'Vorbis',
    null => 'unknown',
    _ => codec.toUpperCase(),
  };

  void _setEngine(String engine) {
    _emit(_state.copyWith(engine: engine));
  }

  void _onMkvError(JSString message) {
    _errorController.add(
      PlaybackError(
        backend: PlaybackBackend.webVideo,
        message: 'MKV playback failed: ${message.toDart}',
        code: 'mkv_playback_error',
        recoverable: true,
      ),
    );
  }

  PlaybackException _mkvException(_JsMkvError error) {
    final detail = error.message ?? '';
    final message = switch (error.code) {
      'unsupported_audio' =>
        "This video's audio ($detail) can't play in this browser. "
            '$_transcodeHint',
      'unsupported_video' =>
        "This video's format ($detail) can't play in this browser. "
            '$_transcodeHint',
      'no_video' => 'This MKV file has no video track.',
      'unreadable' =>
        "The server didn't return a playable video file. The provider may be "
            "down, or this title's link may be broken.",
      _ => 'MKV playback failed: $detail',
    };
    return PlaybackException(
      message: message,
      backend: PlaybackBackend.webVideo,
      code: switch (error.code) {
        null => 'mkv_load_failed',
        'unreadable' => 'web_video_unreadable',
        _ => 'web_video_unsupported',
      },
      recoverable: true,
    );
  }

  // --- hls.js ---------------------------------------------------------

  Future<void> _loadHls(Uri uri) async {
    await _ensureScriptLoaded(_hlsScriptUrl, globalName: 'Hls');
    if (!_hlsIsSupported()) {
      // Safari and other browsers with built-in HLS support.
      _setEngine('native HLS');
      _video.src = uri.toString();
      return;
    }
    final hls = _JsHls(
      <String, Object?>{'enableWorker': true, 'lowLatencyMode': true}.jsify(),
    );
    _hls = hls;
    _setEngine('hls.js');
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

  /// [convertAudio] rewrites AC-3/E-AC-3 audio to AAC on its way into
  /// mpegts.js (web/live_audio_filter.mjs). Only used once the browser has
  /// turned the stream's own audio down, see [_onMpegtsError].
  Future<void> _loadMpegTs(
    Uri uri, {
    required bool isLive,
    bool convertAudio = false,
  }) async {
    final generation = _generation;
    await _ensureScriptLoaded(_mpegtsScriptUrl, globalName: 'mpegts');
    if (convertAudio) {
      await _ensureScriptLoaded(
        _liveAudioFilterScriptUrl,
        globalName: 'M3uLiveAudioFilter',
        isModule: true,
      );
    }
    if (generation != _generation) return;
    if (!_mpegtsGetFeatureList().mseLivePlayback) {
      _setEngine('native <video>');
      _video.src = uri.toString();
      return;
    }
    final source = <String, Object?>{
      'type': 'mpegts',
      'url': uri.toString(),
      'isLive': isLive,
      'enableWorker': true,
      'cors': true,
      'liveBufferLatencyChasing': false,
    }.jsify()!;
    final _JsMpegtsPlayer player;
    if (convertAudio) {
      final config = JSObject()
        ..['enableWorker'] = false.toJS
        ..['lazyLoad'] = false.toJS
        ..['customLoader'] = _liveAudioLoader;
      player = _mpegtsCreatePlayer(source, config);
    } else {
      player = _mpegtsCreatePlayer(source);
    }
    _mpegts = player;
    _setEngine(convertAudio ? 'mpegts.js: AC-3 to AAC' : 'mpegts.js');
    player
      ..on(
        'error',
        (JSString type, JSString details, JSAny? info) {
          if (generation != _generation || !identical(_mpegts, player)) return;
          _onMpegtsError(
            type.toDart,
            details.toDart,
            info,
            uri: uri,
            canConvertAudio: isLive && !convertAudio,
          );
        }.toJS,
      )
      ..attachMediaElement(_video)
      ..load();
  }

  void _onMpegtsError(
    String type,
    String details,
    JSAny? info, {
    required Uri uri,
    required bool canConvertAudio,
  }) {
    // The browser turned a track's codec down. That doesn't say which one
    // (Firefox leaves it out), but AC-3 audio is the usual reason.
    final isUnsupportedCodec =
        details == 'MediaMSEError' &&
        (info as _MpegtsErrorInfo?)?.code == _notSupportedErrorCode;
    if (isUnsupportedCodec && canConvertAudio) {
      unawaited(_restartWithConvertedAudio(uri));
      return;
    }
    _errorController.add(
      PlaybackError(
        backend: PlaybackBackend.webVideo,
        message: isUnsupportedCodec
            ? "This browser can't play this channel's format. $_transcodeHint"
            : 'MPEG-TS playback failed: $type: $details',
        code: isUnsupportedCodec ? 'web_video_unsupported' : 'mpegts_error',
        recoverable: true,
      ),
    );
  }

  Future<void> _restartWithConvertedAudio(Uri uri) async {
    final generation = _generation;
    // mpegts.js is still inside the error event it reported this from.
    await Future<void>.delayed(Duration.zero);
    if (generation != _generation) return;
    _teardownActivePlayer();
    try {
      await _loadMpegTs(uri, isLive: true, convertAudio: true);
    } on Object catch (error) {
      if (generation != _generation) return;
      _errorController.add(
        PlaybackError(
          backend: PlaybackBackend.webVideo,
          message: 'Audio conversion failed: $error',
          code: 'web_video_load_failed',
          recoverable: true,
        ),
      );
      return;
    }
    if (generation == _generation) unawaited(play());
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
    final mkv = _mkv;
    if (mkv != null) {
      try {
        mkv.destroy();
      } on Object {
        // Best effort, like the hls.js/mpegts.js teardown above.
      }
      _mkv = null;
    }
  }

  // --- <video> element events ---------------------------------------------

  void _attachVideoListeners() {
    void add(String type, void Function(web.Event event) handler) {
      final listener = handler.toJS;
      _video.addEventListener(type, listener);
      _videoListeners.add((type: type, listener: listener));
    }

    add('loadedmetadata', (_) {
      _settlePendingNativeLoad();
      _emitFromVideo(PlaybackStatus.ready);
    });
    add('playing', (_) => _emitFromVideo(PlaybackStatus.playing));
    add('pause', (_) => _emitFromVideo(PlaybackStatus.paused));
    add('waiting', (_) => _emitFromVideo(PlaybackStatus.buffering));
    add('timeupdate', (_) => _emitFromVideo(_state.status));
    add('ended', (_) => _emitFromVideo(PlaybackStatus.completed));
    add('error', (_) {
      final error = _video.error;
      if (_pendingNativeLoad != null) {
        _settlePendingNativeLoad(error);
        return;
      }
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
String get _liveAudioFilterScriptUrl => _assetUrl('live_audio_filter.mjs');
String get _mkvScriptUrl => _assetUrl('mkv_player.mjs');

String _assetUrl(String name) =>
    Uri.parse(web.document.baseURI).resolve(name).toString();

final Map<String, Future<void>> _scriptLoads = <String, Future<void>>{};

/// Injects `<script src=[url]>` once per [url] and waits for it to finish
/// executing, so [globalName] (`Hls`/`mpegts`/`M3uMkvPlayer`) is defined
/// before the caller touches it. [isModule] loads it as an ES module (its
/// `load` event fires after its imports have run too). Cached per URL:
/// concurrent/repeated loads of the same library share one `<script>` tag
/// and one wait.
Future<void> _ensureScriptLoaded(
  String url, {
  required String globalName,
  bool isModule = false,
}) {
  if (globalContext.has(globalName)) return Future<void>.value();
  return _scriptLoads.putIfAbsent(url, () async {
    final completer = Completer<void>();
    final script = web.document.createElement('script') as web.HTMLScriptElement
      ..src = url
      ..type = isModule ? 'module' : ''
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
