import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'player_adapter.dart';

enum PlaybackOverlayAction { play, pause, dismiss, audioTracks, subtitles }

enum PlaybackOverlayControl { play, pause, audioTracks, subtitles }

class AndroidTvPlaybackOverlayController extends ChangeNotifier {
  AndroidTvPlaybackOverlayController({required PlaybackStatus initialStatus})
    : status = initialStatus,
      focusedControl = initialStatus == PlaybackStatus.playing
          ? PlaybackOverlayControl.pause
          : PlaybackOverlayControl.play;

  PlaybackStatus status;
  bool isVisible = false;
  PlaybackOverlayControl focusedControl;

  void show() {
    isVisible = true;
    _focusPrimaryPlaybackControl();
    notifyListeners();
  }

  void dismiss() {
    isVisible = false;
    notifyListeners();
  }

  void moveRight() {
    if (!isVisible) {
      show();
      return;
    }
    focusedControl = switch (focusedControl) {
      PlaybackOverlayControl.play || PlaybackOverlayControl.pause =>
        PlaybackOverlayControl.audioTracks,
      PlaybackOverlayControl.audioTracks => PlaybackOverlayControl.subtitles,
      PlaybackOverlayControl.subtitles => PlaybackOverlayControl.subtitles,
    };
    notifyListeners();
  }

  void moveLeft() {
    if (!isVisible) {
      show();
      return;
    }
    focusedControl = switch (focusedControl) {
      PlaybackOverlayControl.play || PlaybackOverlayControl.pause =>
        focusedControl,
      PlaybackOverlayControl.audioTracks => _primaryPlaybackControl,
      PlaybackOverlayControl.subtitles => PlaybackOverlayControl.audioTracks,
    };
    notifyListeners();
  }

  PlaybackOverlayAction activateFocusedControl() {
    isVisible = true;
    final action = switch (focusedControl) {
      PlaybackOverlayControl.play => PlaybackOverlayAction.play,
      PlaybackOverlayControl.pause => PlaybackOverlayAction.pause,
      PlaybackOverlayControl.audioTracks => PlaybackOverlayAction.audioTracks,
      PlaybackOverlayControl.subtitles => PlaybackOverlayAction.subtitles,
    };
    if (action == PlaybackOverlayAction.play) {
      status = PlaybackStatus.playing;
      focusedControl = PlaybackOverlayControl.pause;
    } else if (action == PlaybackOverlayAction.pause) {
      status = PlaybackStatus.paused;
      focusedControl = PlaybackOverlayControl.play;
    }
    notifyListeners();
    return action;
  }

  PlaybackOverlayAction togglePlayback() {
    isVisible = true;
    if (status == PlaybackStatus.playing) {
      status = PlaybackStatus.paused;
      focusedControl = PlaybackOverlayControl.play;
      notifyListeners();
      return PlaybackOverlayAction.pause;
    }

    status = PlaybackStatus.playing;
    focusedControl = PlaybackOverlayControl.pause;
    notifyListeners();
    return PlaybackOverlayAction.play;
  }

  PlaybackOverlayControl get _primaryPlaybackControl {
    return status == PlaybackStatus.playing
        ? PlaybackOverlayControl.pause
        : PlaybackOverlayControl.play;
  }

  void _focusPrimaryPlaybackControl() {
    focusedControl = _primaryPlaybackControl;
  }
}

class AndroidTvPlayerOverlay extends StatefulWidget {
  const AndroidTvPlayerOverlay({
    required this.controller,
    required this.onAction,
    super.key,
  });

  final AndroidTvPlaybackOverlayController controller;
  final ValueChanged<PlaybackOverlayAction> onAction;

  @override
  State<AndroidTvPlayerOverlay> createState() => _AndroidTvPlayerOverlayState();
}

class _AndroidTvPlayerOverlayState extends State<AndroidTvPlayerOverlay> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'Android TV overlay');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(AndroidTvPlayerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: widget.controller.isVisible ? _buildVisibleOverlay() : _buildHiddenOverlay(),
    );
  }

  Widget _buildHiddenOverlay() {
    return SizedBox.expand(
      child: Semantics(
        label: 'Playback overlay hidden',
        focusable: true,
      ),
    );
  }

  Widget _buildVisibleOverlay() {
    return Semantics(
      label: 'Playback controls overlay',
      focusable: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          _OverlayControlLabel(
            control: PlaybackOverlayControl.play,
            focusedControl: widget.controller.focusedControl,
          ),
          _OverlayControlLabel(
            control: PlaybackOverlayControl.pause,
            focusedControl: widget.controller.focusedControl,
          ),
          _OverlayControlLabel(
            control: PlaybackOverlayControl.audioTracks,
            focusedControl: widget.controller.focusedControl,
          ),
          _OverlayControlLabel(
            control: PlaybackOverlayControl.subtitles,
            focusedControl: widget.controller.focusedControl,
          ),
        ],
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter) {
      if (!widget.controller.isVisible) {
        widget.controller.show();
        return;
      }
      widget.onAction(widget.controller.activateFocusedControl());
      return;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      widget.onAction(widget.controller.togglePlayback());
      return;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.moveRight();
      return;
    }

    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.moveLeft();
      return;
    }

    if (key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.escape) {
      if (widget.controller.isVisible) {
        widget.controller.dismiss();
        widget.onAction(PlaybackOverlayAction.dismiss);
      }
    }
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }
}

class _OverlayControlLabel extends StatelessWidget {
  const _OverlayControlLabel({
    required this.control,
    required this.focusedControl,
  });

  final PlaybackOverlayControl control;
  final PlaybackOverlayControl focusedControl;

  @override
  Widget build(BuildContext context) {
    final focused = control == focusedControl;
    return Text('${focused ? 'focused' : 'available'}:${control.name}');
  }
}
