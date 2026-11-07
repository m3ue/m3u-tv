import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// What a remote's dedicated transport button asks for. Play and Pause are
/// directed: a remote with separate buttons must not flip the state it asked
/// for.
enum PlayerTransportCommand { play, pause, toggle, stop }

/// The transport command for [key], or null for any other key.
PlayerTransportCommand? playerTransportCommandFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.mediaPlay) return PlayerTransportCommand.play;
  if (key == LogicalKeyboardKey.mediaPause) return PlayerTransportCommand.pause;
  if (key == LogicalKeyboardKey.mediaPlayPause) {
    return PlayerTransportCommand.toggle;
  }
  if (key == LogicalKeyboardKey.mediaStop) return PlayerTransportCommand.stop;
  return null;
}

class PlayerBackIntent extends Intent {
  const PlayerBackIntent();
}

class PlayerSeekBackIntent extends Intent {
  const PlayerSeekBackIntent();
}

class PlayerSeekForwardIntent extends Intent {
  const PlayerSeekForwardIntent();
}

class PlayerChannelUpIntent extends Intent {
  const PlayerChannelUpIntent();
}

class PlayerChannelDownIntent extends Intent {
  const PlayerChannelDownIntent();
}

class PlayerBackAction extends Action<PlayerBackIntent> {
  PlayerBackAction(this.onBack);
  final VoidCallback onBack;
  @override
  Object? invoke(PlayerBackIntent intent) {
    onBack();
    return null;
  }
}

class PlayerChannelChangeAction extends Action<Intent> {
  PlayerChannelChangeAction(this.onChange);
  final VoidCallback? onChange;
  @override
  Object? invoke(Intent intent) {
    onChange?.call();
    return null;
  }
}

class PlayerSeekAction extends Action<Intent> {
  PlayerSeekAction(this.onSeek);
  final VoidCallback onSeek;
  @override
  Object? invoke(Intent intent) {
    onSeek();
    return null;
  }
}
