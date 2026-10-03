import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/app/text_input_reporting_binding.dart';

class _RecordingMessenger extends BinaryMessenger {
  final sent = <(String, ByteData?)>[];

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    sent.add((channel, message));
    return null;
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {}

  /// Each send as `channel:method[:args]`, decoded with the channel's codec.
  List<String> get log => [
    for (final (channel, message) in sent)
      if (channel == TextInputReportingMessenger.reportChannel)
        '$channel:${const StandardMethodCodec().decodeMethodCall(message).method}'
            ':${const StandardMethodCodec().decodeMethodCall(message).arguments}'
      else if (channel == SystemChannels.textInput.name)
        '$channel:${SystemChannels.textInput.codec.decodeMethodCall(message).method}'
      else
        channel,
  ];
}

ByteData _textInput(String method, [Object? arguments]) =>
    SystemChannels.textInput.codec.encodeMethodCall(
      MethodCall(method, arguments),
    );

void _post(BinaryMessenger messenger, String channel, ByteData? message) =>
    unawaited(messenger.send(channel, message));

void main() {
  const report = TextInputReportingMessenger.reportChannel;
  const textInput = 'flutter/textinput';

  test('reports active ahead of setClient and inactive after clearClient', () {
    final inner = _RecordingMessenger();
    final messenger = TextInputReportingMessenger(inner);

    _post(
      messenger,
      textInput,
      _textInput('TextInput.setClient', [1, <String, Object?>{}]),
    );
    _post(messenger, textInput, _textInput('TextInput.setEditingState', {}));
    _post(messenger, textInput, _textInput('TextInput.show'));
    _post(messenger, textInput, _textInput('TextInput.clearClient'));

    expect(inner.log, [
      '$report:setActive:true',
      '$textInput:TextInput.setClient',
      '$textInput:TextInput.setEditingState',
      '$textInput:TextInput.show',
      '$textInput:TextInput.clearClient',
      '$report:setActive:false',
    ]);
  });

  test('reports only on change when focus moves between fields', () {
    final inner = _RecordingMessenger();
    final messenger = TextInputReportingMessenger(inner);

    _post(
      messenger,
      textInput,
      _textInput('TextInput.setClient', [1, <String, Object?>{}]),
    );
    _post(
      messenger,
      textInput,
      _textInput('TextInput.setClient', [2, <String, Object?>{}]),
    );

    expect(
      inner.log.where((entry) => entry.startsWith(report)),
      ['$report:setActive:true'],
    );
  });

  test('passes other channels through untouched', () {
    final inner = _RecordingMessenger();
    final messenger = TextInputReportingMessenger(inner);
    final payload = ByteData(3);

    _post(messenger, 'm3u_tv/system_ui', payload);
    _post(messenger, textInput, null);

    expect(inner.sent, [('m3u_tv/system_ui', payload), (textInput, null)]);
  });
}
