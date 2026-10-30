import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

/// [Isolate.run], except on the web, which has no isolates: there
/// [computation] runs inline, as Flutter's `compute` does.
Future<R> runOffMainIsolate<R>(FutureOr<R> Function() computation) =>
    kIsWeb ? Future<R>.sync(computation) : Isolate.run(computation);

/// Below this size, `Isolate.run`'s spawn/copy overhead costs more than the
/// decode itself would ever block a frame for, so we just decode inline.
const int _offloadThresholdBytes = 32 * 1024;

final Converter<List<int>, Object?> _utf8Json = utf8.decoder.fuse(json.decoder);

/// Decodes a UTF-8 JSON body in one pass, never materializing the
/// intermediate String. Safe to call from any isolate.
Object? decodeJsonBytes(Uint8List bytes) => _utf8Json.convert(bytes);

/// Decodes [text] as JSON, hopping off the calling isolate when the payload
/// is large enough that a synchronous decode could visibly steal a frame
/// (catalog dumps with thousands of channels/VOD/series entries).
Future<Object?> decodeJsonOffMainIsolate(String text) {
  if (text.length < _offloadThresholdBytes) {
    return Future.value(jsonDecode(text));
  }
  return runOffMainIsolate(() => jsonDecode(text));
}

/// [decodeJsonOffMainIsolate] for a raw response body: the UTF-8 decode
/// happens on the worker too, so the UI isolate never sees the payload as a
/// String.
Future<Object?> decodeJsonBytesOffMainIsolate(Uint8List bytes) {
  if (bytes.length < _offloadThresholdBytes) {
    return Future.value(decodeJsonBytes(bytes));
  }
  return runOffMainIsolate(() => decodeJsonBytes(bytes));
}

/// Encodes [data] as JSON, hopping off the calling isolate for large maps
/// for the same reason as [decodeJsonOffMainIsolate].
///
/// The key-count check is only a cheap proxy for "big payload". Pass
/// [forceOffload] when the caller already knows the map is large by another
/// measure (e.g. a multi-KB backing file) but holds few top-level keys.
Future<String> encodeJsonOffMainIsolate(
  Map<String, Object?> data, {
  bool forceOffload = false,
}) {
  if (!forceOffload && data.length < 64) {
    return Future.value(jsonEncode(data));
  }
  return runOffMainIsolate(() => jsonEncode(data));
}

/// A reusable background isolate for work that arrives in bursts (the EPG
/// sweep's per-batch parses), where spawning a fresh isolate per job via
/// [runOffMainIsolate] would pay the spawn and teardown every time. The
/// isolate starts on first use and shuts down after [idleTimeout] with no
/// work, so it holds no memory between bursts. Jobs run one at a time, in
/// order. On the web there are no isolates, so jobs run inline.
class BackgroundWorker {
  BackgroundWorker({
    this.debugName = 'BackgroundWorker',
    this.idleTimeout = const Duration(seconds: 30),
  });

  final String debugName;
  final Duration idleTimeout;

  Future<SendPort>? _sendPort;
  Isolate? _isolate;
  Timer? _idleTimer;
  int _pending = 0;

  Future<R> run<R>(FutureOr<R> Function() computation) async {
    if (kIsWeb) return computation();
    _idleTimer?.cancel();
    _pending++;
    final reply = RawReceivePort();
    try {
      final completer = Completer<Object?>();
      reply.handler = completer.complete;
      final port = await (_sendPort ??= _spawn());
      port.send((computation, reply.sendPort));
      final result = await completer.future;
      if (result is RemoteError) throw result;
      return result as R;
    } finally {
      reply.close();
      _pending--;
      if (_pending == 0) _idleTimer = Timer(idleTimeout, shutdown);
    }
  }

  /// Stops the isolate now. Any later [run] starts a fresh one.
  void shutdown() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_pending > 0) return;
    _isolate?.kill();
    _isolate = null;
    _sendPort = null;
  }

  Future<SendPort> _spawn() async {
    final ready = RawReceivePort();
    final completer = Completer<SendPort>();
    void onReady(Object? port) => completer.complete(port! as SendPort);
    ready.handler = onReady;
    try {
      _isolate = await Isolate.spawn(
        _workerMain,
        ready.sendPort,
        debugName: debugName,
      );
      return await completer.future;
    } on Object {
      _sendPort = null;
      rethrow;
    } finally {
      ready.close();
    }
  }

  static void _workerMain(SendPort ready) {
    final jobs = ReceivePort();
    ready.send(jobs.sendPort);
    // Serialized so jobs finish (and reply) in the order they arrived.
    var queue = Future<void>.value();
    jobs.listen((message) {
      final (computation, reply) =
          message! as (FutureOr<Object?> Function(), SendPort);
      queue = queue.then((_) async {
        try {
          reply.send(await computation());
        } on Object catch (error, stackTrace) {
          reply.send(RemoteError('$error', '$stackTrace'));
        }
      });
    });
  }
}
