import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';

class PlaybackDiagnosticsPanel extends StatelessWidget {
  const PlaybackDiagnosticsPanel({
    super.key,
    required this.activeBackend,
    required this.diagnostics,
    this.compact = false,
    this.width = 360,
    this.fontScale = 1.0,
  });

  final PlaybackBackend? activeBackend;
  final List<String> diagnostics;

  /// Shrinks padding/fonts/label width for phones/tablets, where the fixed
  /// 360px panel used to run off the edge of the screen in portrait and
  /// collide with the title overlay in the short landscape orientation.
  final bool compact;

  /// Caller-supplied width (see `PlayerScreen`'s `diagnosticsWidth`), so this
  /// panel and the title overlay it sits beside can agree on how much of the
  /// screen each one gets instead of overlapping.
  final double width;

  /// TV display-size scale (see `FontSizeScope`) so the label column and
  /// text keep pace with `width`, which is already scaled by the caller --
  /// without this, larger scale factors squeeze the same fixed label/font
  /// sizes into a wider box and the text still wraps.
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final snapshot = _PlaybackDiagnosticsSnapshot.from(
      activeBackend: activeBackend,
      diagnostics: diagnostics,
    );
    final rows = <Widget>[
      _DiagnosticsRow(
        label: AppLocalizations.of(context).playerDiagBackend,
        value: snapshot.backendLabel,
        compact: compact,
        fontScale: fontScale,
      ),
      if (snapshot.fallbackReason != null)
        _DiagnosticsRow(
          label: AppLocalizations.of(context).playerDiagFallback,
          value: snapshot.fallbackReason!,
          compact: compact,
          fontScale: fontScale,
        ),
      if (snapshot.codecDecision != null)
        _DiagnosticsRow(
          label: AppLocalizations.of(context).playerDiagCodec,
          value: snapshot.codecDecision!,
          compact: compact,
          fontScale: fontScale,
        ),
      if (snapshot.transcodeSession != null)
        _DiagnosticsRow(
          label: AppLocalizations.of(context).playerDiagTranscode,
          value: snapshot.transcodeSession!,
          compact: compact,
          fontScale: fontScale,
        ),
      if (snapshot.cleanupStatus != null)
        _DiagnosticsRow(
          label: AppLocalizations.of(context).playerDiagCleanup,
          value: snapshot.cleanupStatus!,
          compact: compact,
          fontScale: fontScale,
        ),
    ];

    return IgnorePointer(
      child: Container(
        width: width,
        padding: EdgeInsets.all((compact ? 8 : 14) * fontScale),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Colors.black54,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      ),
    );
  }
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({
    required this.label,
    required this.value,
    this.compact = false,
    this.fontScale = 1.0,
  });

  final String label;
  final String value;
  final bool compact;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: (compact ? 2 : 3) * fontScale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: (compact ? 72 : 118) * fontScale,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white60,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 10 : 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackDiagnosticsSnapshot {
  const _PlaybackDiagnosticsSnapshot({
    required this.backendLabel,
    this.fallbackReason,
    this.codecDecision,
    this.transcodeSession,
    this.cleanupStatus,
  });

  final String backendLabel;
  final String? fallbackReason;
  final String? codecDecision;
  final String? transcodeSession;
  final String? cleanupStatus;

  static _PlaybackDiagnosticsSnapshot from({
    required PlaybackBackend? activeBackend,
    required List<String> diagnostics,
  }) {
    var backendLabel = _backendLabel(activeBackend);
    String? fallbackReason;
    String? codecDecision;
    String? transcodeSession;
    String? cleanupStatus;

    for (final item in diagnostics) {
      if (item.startsWith('active-backend:')) {
        final backend = _backendFromDiagnostic(item);
        if (backend != null) backendLabel = _backendLabel(backend);
      } else if (item.startsWith('fallback-reason:')) {
        final parsed = _parseKeyValueDiagnostic(item, 'fallback-reason:');
        codecDecision = parsed.key;
        fallbackReason = parsed.value;
      } else if (item.startsWith('server-transcode:')) {
        final parts = item.split(':');
        final streamId = parts.length > 1 ? parts[1] : 'unknown stream';
        final sessionId = parts.length > 2 ? parts[2] : 'no session';
        transcodeSession = sessionId == 'null'
            ? streamId
            : '$streamId / $sessionId';
      } else if (item.startsWith('cleanup:server-transcode:stopped:')) {
        final payload = item.substring(
          'cleanup:server-transcode:stopped:'.length,
        );
        cleanupStatus = 'server transcode stopped ($payload)';
      }
    }

    return _PlaybackDiagnosticsSnapshot(
      backendLabel: backendLabel,
      fallbackReason: fallbackReason,
      codecDecision: codecDecision,
      transcodeSession: transcodeSession,
      cleanupStatus: cleanupStatus,
    );
  }

  static ({String key, String value}) _parseKeyValueDiagnostic(
    String item,
    String prefix,
  ) {
    final payload = item.substring(prefix.length);
    final separator = payload.indexOf(':');
    if (separator < 0) return (key: payload, value: payload);
    return (
      key: payload.substring(0, separator),
      value: payload.substring(separator + 1),
    );
  }

  static PlaybackBackend? _backendFromDiagnostic(String item) {
    final parts = item.split(':');
    if (parts.length < 2) return null;
    return switch (parts[1]) {
      'androidExoPlayer' => PlaybackBackend.androidExoPlayer,
      'androidMpv' => PlaybackBackend.androidMpv,
      'appleMpvNative' => PlaybackBackend.appleMpvNative,
      'appleAvKit' => PlaybackBackend.appleAvKit,
      'desktopLibmpv' => PlaybackBackend.desktopLibmpv,
      'macMpvNative' => PlaybackBackend.macMpvNative,
      'serverTranscode' => PlaybackBackend.serverTranscode,
      'webVideo' => PlaybackBackend.webVideo,
      _ => null,
    };
  }

  static String _backendLabel(PlaybackBackend? backend) {
    return switch (backend) {
      PlaybackBackend.androidExoPlayer => 'Android ExoPlayer',
      PlaybackBackend.androidMpv => 'Android native mpv',
      PlaybackBackend.appleMpvNative => 'Apple native mpv',
      PlaybackBackend.appleAvKit => 'Apple AVKit fallback',
      PlaybackBackend.desktopLibmpv => 'Desktop libmpv',
      PlaybackBackend.macMpvNative => 'macOS native mpv',
      PlaybackBackend.serverTranscode => 'Server transcode fallback',
      PlaybackBackend.webVideo => 'Web browser video',
      null => 'Selecting backend',
    };
  }
}
