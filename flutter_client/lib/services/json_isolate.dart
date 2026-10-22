import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

/// [Isolate.run], except on the web, which has no isolates: there
/// [computation] runs inline, as Flutter's `compute` does.
Future<R> runOffMainIsolate<R>(FutureOr<R> Function() computation) =>
    kIsWeb ? Future<R>.sync(computation) : Isolate.run(computation);

/// Below this size, `Isolate.run`'s spawn/copy overhead costs more than the
/// decode itself would ever block a frame for, so we just decode inline.
const int _offloadThresholdBytes = 32 * 1024;

/// Decodes [text] as JSON, hopping off the calling isolate when the payload
/// is large enough that a synchronous decode could visibly steal a frame
/// (catalog dumps with thousands of channels/VOD/series entries).
Future<Object?> decodeJsonOffMainIsolate(String text) {
  if (text.length < _offloadThresholdBytes) {
    return Future.value(jsonDecode(text));
  }
  return runOffMainIsolate(() => jsonDecode(text));
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
