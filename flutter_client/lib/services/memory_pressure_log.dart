import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Logs what the process held when the OS reported memory pressure.
///
/// The framework's own handler runs first: [PaintingBinding.handleMemoryPressure]
/// empties the image cache before any `didHaveMemoryPressure` observer is
/// called, so an observer only ever sees an empty cache and can't say what was
/// resident before a low-memory kill. This wraps the whole dispatch instead:
/// RSS and the image cache are read before it, and the cache again once every
/// observer has run.
///
/// iOS delivers warnings in bursts, so at most one line is logged per
/// [interval]; the next one counts the warnings folded into it as
/// `suppressed`. Every value read here is an in-process counter, never a
/// platform-channel round trip.
///
/// Ported from the open-source Plezy player's `MemoryPressureBreadcrumbs`
/// (github.com/edde746/plezy, GPL-3.0), logging to the console instead of
/// Sentry.
class MemoryPressureLog {
  MemoryPressureLog({
    DateTime Function()? clock,
    int Function()? currentRss,
    int Function()? maxRss,
    void Function(String message)? log,
  }) : _clock = clock ?? DateTime.now,
       _currentRss = currentRss ?? (() => ProcessInfo.currentRss),
       _maxRss = maxRss ?? (() => ProcessInfo.maxRss),
       _log = log ?? debugPrint;

  static const Duration interval = Duration(seconds: 30);

  final DateTime Function() _clock;
  final int Function() _currentRss;
  final int Function() _maxRss;
  final void Function(String message) _log;

  DateTime? _lastLogged;
  int _suppressed = 0;

  /// Runs [dispatch] (the binding's own memory-pressure handling), logging
  /// [cache] and RSS around it unless a line was logged within [interval].
  void handle(ImageCache cache, VoidCallback dispatch) {
    final now = _clock();
    final last = _lastLogged;
    // A wall clock set backwards must not silence the log until it catches
    // up again.
    if (last != null &&
        !now.isBefore(last) &&
        now.difference(last) < interval) {
      _suppressed++;
      dispatch();
      return;
    }
    _lastLogged = now;

    final fields = <String>[
      ?_megabytes('rss', _currentRss),
      ?_megabytes('maxRss', _maxRss),
      'cache=${cache.currentSize}img/${cache.currentSizeBytes >> 20}MB',
      'live=${cache.liveImageCount}',
    ];
    dispatch();
    fields.addAll([
      'cacheAfter=${cache.currentSize}img/${cache.currentSizeBytes >> 20}MB',
      'liveAfter=${cache.liveImageCount}',
      if (_suppressed > 0) 'suppressed=$_suppressed',
    ]);
    _suppressed = 0;
    _log('[MemoryPressure] ${fields.join(' ')}');
  }

  /// RSS reads are syscalls that can fail; a failed read drops its field
  /// rather than the platform's memory-pressure handling behind it.
  static String? _megabytes(String name, int Function() readBytes) {
    try {
      return '$name=${readBytes() >> 20}MB';
    } on Object {
      return null;
    }
  }
}

/// Routes the binding's memory-pressure dispatch through [MemoryPressureLog].
mixin MemoryPressureLogging on PaintingBinding {
  final MemoryPressureLog _memoryPressureLog = MemoryPressureLog();

  @override
  void handleMemoryPressure() =>
      _memoryPressureLog.handle(imageCache, super.handleMemoryPressure);
}
