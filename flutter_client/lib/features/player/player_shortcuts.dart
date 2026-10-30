import 'package:flutter/material.dart';

class PlayerBackIntent extends Intent {
  const PlayerBackIntent();
}

class PlayerPlayPauseIntent extends Intent {
  const PlayerPlayPauseIntent();
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

class PlayerPlayPauseAction extends Action<PlayerPlayPauseIntent> {
  PlayerPlayPauseAction(this.onToggle);
  final VoidCallback onToggle;
  @override
  Object? invoke(PlayerPlayPauseIntent intent) {
    onToggle();
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
