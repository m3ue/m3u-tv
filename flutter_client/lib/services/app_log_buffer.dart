import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AppLogLevel { info, error }

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String message;

  /// Rough in-memory cost, used only to bound the ring buffer.
  int get estimatedBytes => 32 + message.length * 2;

  String format() {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = timestamp;
    final millis = t.millisecond.toString().padLeft(3, '0');
    final time = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.$millis';
    return '[$time] [${level.name.toUpperCase()}] $message';
  }
}

/// In-memory ring buffer of this run's log lines for the Logs & Diagnostics
/// screen, so a user can upload what happened without adb or Xcode.
///
/// [install] tees every `debugPrint` (what the app already logs with) plus
/// uncaught framework and platform errors into the buffer; the original
/// console output is unchanged. Everything is redacted on the way in, so
/// credentials never sit in memory or reach an upload.
class AppLogBuffer {
  AppLogBuffer({this.maxBytes = 2 * 1024 * 1024});

  static final AppLogBuffer instance = AppLogBuffer();

  final int maxBytes;
  final ListQueue<AppLogEntry> _entries = ListQueue<AppLogEntry>();
  final Set<String> _secrets = <String>{};
  int _bytes = 0;
  bool _installed = false;

  /// Oldest first.
  List<AppLogEntry> get entries => List.unmodifiable(_entries);

  void add(AppLogLevel level, String message, {DateTime? at}) {
    final entry = AppLogEntry(
      timestamp: at ?? DateTime.now(),
      level: level,
      message: redact(message),
    );
    _entries.addLast(entry);
    _bytes += entry.estimatedBytes;
    while (_bytes > maxBytes && _entries.isNotEmpty) {
      _bytes -= _entries.removeFirst().estimatedBytes;
    }
  }

  void clear() {
    _entries.clear();
    _bytes = 0;
  }

  /// Exact values (the active username/password) scrubbed from every line
  /// from now on, on top of the generic URL/query patterns in [redact].
  void registerSecret(String? value) {
    if (value == null || value.length < 3) return;
    _secrets.add(value);
  }

  // Xtream-style paths carry credentials as path segments
  // (`/live/<user>/<pass>/...`, `/api/tv/<user>/<pass>/...`).
  static final RegExp _credentialPath = RegExp(
    r'(/(?:live|movie|series|timeshift|api/tv)/)[^/\s?#]+/[^/\s?#]+',
  );
  static final RegExp _secretQuery = RegExp(
    r'\b(username|password|api_key|apikey|token|access_token|X-Plex-Token|signature)=[^&\s"]+',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(
    r'(Bearer\s+)[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );

  String redact(String message) {
    var redacted = message
        .replaceAllMapped(
          _credentialPath,
          (m) => '${m.group(1)}[redacted]/[redacted]',
        )
        .replaceAllMapped(_secretQuery, (m) => '${m.group(1)}=[redacted]')
        .replaceAllMapped(_bearer, (m) => '${m.group(1)}[redacted]');
    for (final secret in _secrets) {
      redacted = redacted.replaceAll(secret, '[redacted]');
    }
    return redacted;
  }

  /// [header] followed by every line oldest first. With [maxBytes], drops the
  /// oldest lines until the UTF-8 payload fits, keeping the header and the
  /// newest lines (what led up to the problem being reported).
  String export({String header = '', int? maxBytes}) {
    final head = header.isEmpty ? '' : '${redact(header)}\n---\n';
    final lines = _entries.map((e) => e.format()).toList();
    if (maxBytes == null) return '$head${lines.join('\n')}';

    var budget = maxBytes - utf8.encode(head).length;
    final kept = <String>[];
    for (final line in lines.reversed) {
      final cost = utf8.encode(line).length + 1;
      if (cost > budget) break;
      budget -= cost;
      kept.add(line);
    }
    return '$head${kept.reversed.join('\n')}';
  }

  /// Starts capturing. Idempotent; chains to whatever handlers were already
  /// installed so console output and crash reporting behave exactly as
  /// before.
  void install() {
    if (_installed) return;
    _installed = true;

    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) add(AppLogLevel.info, message);
      previousPrint(message, wrapWidth: wrapWidth);
    };

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      add(
        AppLogLevel.error,
        '${details.exceptionAsString()}\n${details.stack ?? ''}'.trimRight(),
      );
      previousFlutterError?.call(details);
    };

    final dispatcher = PlatformDispatcher.instance;
    final previousPlatformError = dispatcher.onError;
    dispatcher.onError = (error, stack) {
      add(AppLogLevel.error, '$error\n$stack'.trimRight());
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }
}
