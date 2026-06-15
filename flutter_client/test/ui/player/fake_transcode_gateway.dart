import 'dart:async';

import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

/// A fake PlaybackTranscodeGateway for tests that records calls and
/// returns configurable responses.
class FakeTranscodeGateway implements PlaybackTranscodeGateway {
  final List<StreamRequest> startServerTranscodeCalls = [];
  final List<StreamRequest> startBroadcastCalls = [];
  final List<String> stopBroadcastCalls = [];
  final List<({String streamId, String? sessionId})> stopServerTranscodeCalls =
      [];

  TranscodeResponse? _nextServerTranscodeResponse;
  BroadcastSession? _nextBroadcastResponse;
  Exception? _nextServerTranscodeError;
  Exception? _nextBroadcastError;

  void setNextServerTranscodeResponse(TranscodeResponse response) {
    _nextServerTranscodeResponse = response;
  }

  void setNextBroadcastResponse(BroadcastSession session) {
    _nextBroadcastResponse = session;
  }

  void setNextServerTranscodeError(Exception error) {
    _nextServerTranscodeError = error;
  }

  void setNextBroadcastError(Exception error) {
    _nextBroadcastError = error;
  }

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) async {
    startServerTranscodeCalls.add(request);
    if (_nextServerTranscodeError != null) {
      final error = _nextServerTranscodeError!;
      _nextServerTranscodeError = null;
      throw error;
    }
    if (_nextServerTranscodeResponse != null) {
      return _nextServerTranscodeResponse!;
    }
    return TranscodeResponse(
      streamId: 'fake-stream-${startServerTranscodeCalls.length}',
      streamUrl: 'http://localhost/fake-stream.m3u8',
      mode: TranscodeMode.server,
      status: 'active',
      sessionId: 'fake-session-${startServerTranscodeCalls.length}',
    );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async {
    startBroadcastCalls.add(request);
    if (_nextBroadcastError != null) {
      final error = _nextBroadcastError!;
      _nextBroadcastError = null;
      throw error;
    }
    return _nextBroadcastResponse;
  }

  @override
  Future<void> stopBroadcast(String networkId) async {
    stopBroadcastCalls.add(networkId);
  }

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    String? sessionId,
  }) async {
    stopServerTranscodeCalls.add((streamId: streamId, sessionId: sessionId));
  }
}
