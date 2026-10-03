import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App binding that tells Android when a Flutter text field holds the text
/// input connection (#309).
///
/// Google TV Streamer, Chromecast with Google TV and other Android TV builds
/// ship `config_preventImeStartupUnlessTextEditor`: the system unbinds the
/// keyboard for any startInput whose focused view does not report itself as
/// a text editor. FlutterView never does, so the keyboard is drawn without an
/// input session - D-pad presses never reach it and typed text is dropped.
/// MainActivity's TextEditorProxyView answers that check from the flag sent
/// here (approach ported from Plezy).
///
/// The flag has to reach Android before the engine's restartInput, which runs
/// on the `TextInput.setEditingState` sent right after `TextInput.setClient`.
/// A focus listener fires too late (EditableText attaches from its own focus
/// listener first), so this watches the outgoing text input messages instead
/// and reports ahead of `setClient`. Platform messages are delivered in
/// order, so Android always sees the flag first.
class TextInputReportingBinding extends WidgetsFlutterBinding {
  /// Call once, in place of [WidgetsFlutterBinding.ensureInitialized], as the
  /// first thing in `main()`.
  static WidgetsBinding ensureInitialized() {
    TextInputReportingBinding();
    return WidgetsBinding.instance;
  }

  @override
  BinaryMessenger createBinaryMessenger() {
    final messenger = super.createBinaryMessenger();
    if (kIsWeb || !Platform.isAndroid) return messenger;
    return TextInputReportingMessenger(messenger);
  }
}

/// Forwards every message to the wrapped messenger, sending `setActive` on
/// [reportChannel] ahead of `TextInput.setClient` and after
/// `TextInput.clearClient`.
@visibleForTesting
class TextInputReportingMessenger extends BinaryMessenger {
  TextInputReportingMessenger(this._inner);

  static const reportChannel = 'm3u_tv/text_input';
  static const _reportCodec = StandardMethodCodec();

  final BinaryMessenger _inner;
  bool _active = false;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel != SystemChannels.textInput.name || message == null) {
      return _inner.send(channel, message);
    }
    final method = SystemChannels.textInput.codec
        .decodeMethodCall(message)
        .method;
    if (method == 'TextInput.setClient') _report(true);
    final reply = _inner.send(channel, message);
    if (method == 'TextInput.clearClient') _report(false);
    return reply;
  }

  void _report(bool active) {
    if (active == _active) return;
    _active = active;
    // Straight to the wrapped messenger so it is queued synchronously, ahead
    // of the text input message that follows.
    unawaited(
      _inner.send(
        reportChannel,
        _reportCodec.encodeMethodCall(MethodCall('setActive', active)),
      ),
    );
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _inner.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _inner.handlePlatformMessage(channel, data, callback);
}
