import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/shared/host_platform.dart';

/// A transport button pressed on a system Now Playing surface (lock screen,
/// Control Center, headphones, later CarPlay).
enum NowPlayingCommand {
  play,
  pause,
  toggle,
  seek,
  skipForward,
  skipBackward,
  next,
  previous,
}

class NowPlayingCommandEvent {
  const NowPlayingCommandEvent(this.command, {this.position});

  final NowPlayingCommand command;

  /// The target of a [NowPlayingCommand.seek].
  final Duration? position;
}

/// What the system Now Playing surfaces show for the open player.
@immutable
class NowPlayingInfo {
  const NowPlayingInfo({
    required this.title,
    required this.isLive,
    required this.isPlaying,
    this.subtitle,
    this.artworkUrl,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.canSeek = false,
    this.canChangeChannel = false,
  });

  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final bool isLive;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool canSeek;
  final bool canChangeChannel;

  /// Equal apart from [position], which the system extrapolates itself.
  bool sameApartFromPosition(NowPlayingInfo other) =>
      title == other.title &&
      subtitle == other.subtitle &&
      artworkUrl == other.artworkUrl &&
      isLive == other.isLive &&
      isPlaying == other.isPlaying &&
      duration == other.duration &&
      canSeek == other.canSeek &&
      canChangeChannel == other.canChangeChannel;

  Map<String, Object?> toMap() => <String, Object?>{
    'title': title,
    'subtitle': subtitle,
    'artworkUrl': artworkUrl,
    'isLive': isLive,
    'isPlaying': isPlaying,
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
    'canSeek': canSeek,
    'canChangeChannel': canChangeChannel,
  };
}

/// Feeds the open player to the platform's Now Playing info and routes its
/// remote commands back. iOS only for now; a no-op elsewhere.
///
/// One player owns it at a time: a new player screen can mount before the
/// old one unmounts, so [detach] only clears what the caller still owns.
class NowPlayingBridge {
  NowPlayingBridge({MethodChannel? channel, bool? enabled})
    : _channel = channel ?? const MethodChannel(channelName),
      enabled = enabled ?? HostPlatform.isIOS;

  static const channelName = 'm3u_tv/now_playing';

  static final NowPlayingBridge instance = NowPlayingBridge();

  /// How far the reported position may drift from where the system
  /// extrapolates it before it's resent. Position ticks arrive several times
  /// a second and the system advances the clock on its own between updates.
  static const positionDriftTolerance = Duration(seconds: 2);

  final MethodChannel _channel;
  final bool enabled;

  Object? _owner;
  ValueChanged<NowPlayingCommandEvent>? _onCommand;
  NowPlayingInfo? _lastSent;
  DateTime? _lastSentAt;

  void attach(Object owner, ValueChanged<NowPlayingCommandEvent> onCommand) {
    if (!enabled) return;
    _owner = owner;
    _onCommand = onCommand;
    _lastSent = null;
    _lastSentAt = null;
    _channel.setMethodCallHandler(_handleCall);
  }

  void detach(Object owner) {
    if (!enabled || !identical(_owner, owner)) return;
    _owner = null;
    _onCommand = null;
    _lastSent = null;
    _lastSentAt = null;
    _channel.setMethodCallHandler(null);
    unawaited(_invoke('clear'));
  }

  void update(Object owner, NowPlayingInfo info) {
    if (!enabled || !identical(_owner, owner)) return;
    final now = clock.now();
    final lastSentAt = _lastSentAt;
    if (!needsUpdate(
      previous: _lastSent,
      sincePrevious: lastSentAt == null
          ? Duration.zero
          : now.difference(lastSentAt),
      next: info,
    )) {
      return;
    }
    _lastSent = info;
    _lastSentAt = now;
    unawaited(_invoke('update', info.toMap()));
  }

  /// Whether [next] differs from what the system already shows, given that
  /// it has been advancing [previous]'s position for [sincePrevious].
  @visibleForTesting
  static bool needsUpdate({
    required NowPlayingInfo? previous,
    required Duration sincePrevious,
    required NowPlayingInfo next,
  }) {
    if (previous == null || !previous.sameApartFromPosition(next)) return true;
    if (next.isLive) return false;
    final expected = previous.isPlaying
        ? previous.position + sincePrevious
        : previous.position;
    return (next.position - expected).abs() > positionDriftTolerance;
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != 'command') return;
    final arguments = call.arguments;
    if (arguments is! Map) return;
    final event = parseCommand(arguments);
    if (event != null) _onCommand?.call(event);
  }

  @visibleForTesting
  static NowPlayingCommandEvent? parseCommand(Map<Object?, Object?> arguments) {
    final name = arguments['name'];
    final command = NowPlayingCommand.values
        .where((value) => value.name == name)
        .firstOrNull;
    if (command == null) return null;
    final positionMs = arguments['positionMs'];
    return NowPlayingCommandEvent(
      command,
      position: positionMs is int ? Duration(milliseconds: positionMs) : null,
    );
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // Older native builds without the plugin.
    } on PlatformException catch (error) {
      debugPrint('[NowPlaying] $method failed: ${error.message}');
    }
  }
}
