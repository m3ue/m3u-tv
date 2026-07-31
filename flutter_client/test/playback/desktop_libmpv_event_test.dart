// ignore_for_file: avoid_dynamic_calls, cascade_invocations

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopLibmpvEvent', () {
    test('parses full snapshot from map', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 7,
        'sequence': 3,
        'kind': 'PLAYBACK_RESTART',
        'positionMs': 12500,
        'durationMs': 60000,
        'paused': false,
        'buffering': false,
        'eof': false,
        'videoAspectRatio': 1.78,
        'speed': 1.0,
        'aid': '1',
        'sid': 'no',
      });

      expect(event.schemaVersion, 1);
      expect(event.handle, 7);
      expect(event.sequence, 3);
      expect(event.kind, DesktopLibmpvEventKind.playbackRestart);
      expect(event.position, const Duration(milliseconds: 12500));
      expect(event.duration, const Duration(milliseconds: 60000));
      expect(event.paused, isFalse);
      expect(event.buffering, isFalse);
      expect(event.eof, isFalse);
      expect(event.videoAspectRatio, 1.78);
      expect(event.speed, 1.0);
      expect(event.aid, '1');
      expect(event.sid, isNull);
    });

    test('parses minimal snapshot with defaults', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 1,
        'sequence': 0,
        'kind': 'START_FILE',
      });

      expect(event.kind, DesktopLibmpvEventKind.startFile);
      expect(event.position, Duration.zero);
      expect(event.duration, isNull);
      expect(event.paused, isFalse);
      expect(event.buffering, isFalse);
      expect(event.eof, isFalse);
      expect(event.videoAspectRatio, isNull);
      expect(event.speed, isNull);
      expect(event.aid, isNull);
      expect(event.sid, isNull);
    });

    test('normalizes omitted and zero native durations as unknown', () {
      final linuxEvent = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 1,
        'sequence': 0,
        'kind': 'FILE_LOADED',
      });
      final windowsEvent = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 1,
        'sequence': 0,
        'kind': 'FILE_LOADED',
        'durationMs': 0,
      });

      expect(linuxEvent.duration, isNull);
      expect(windowsEvent.duration, isNull);
    });

    test('normalizes empty native track IDs to no selected track', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 1,
        'sequence': 0,
        'kind': 'FILE_LOADED',
        'aid': '',
        'sid': '',
      });

      expect(event.aid, isNull);
      expect(event.sid, isNull);
    });

    test('parses and normalizes schema v2 track lists', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 2,
        'handle': 1,
        'sequence': 0,
        'kind': 'FILE_LOADED',
        'audioTracks': <Object?>[
          <String, Object?>{
            'id': ' 1 ',
            'label': ' English ',
            'language': ' eng ',
          },
          <String, Object?>{'id': '2', 'label': ' ', 'language': ' deu '},
          <String, Object?>{'id': '3', 'label': ''},
          <String, Object?>{'id': '', 'label': 'Missing ID'},
          <String, Object?>{'id': 4, 'label': 'Wrong ID type'},
          'not a map',
        ],
        'subtitleTracks': <Object?>[
          <String, Object?>{'id': '4', 'label': ' Commentary '},
          <String, Object?>{'id': '5', 'label': 5, 'language': ''},
        ],
      });

      expect(event.audioTracks, hasLength(3));
      expect(event.audioTracks![0].id, '1');
      expect(event.audioTracks![0].label, 'English');
      expect(event.audioTracks![0].language, 'eng');
      expect(event.audioTracks![1].label, 'deu');
      expect(event.audioTracks![1].language, 'deu');
      expect(event.audioTracks![2].label, '3');
      expect(event.audioTracks![2].language, isNull);
      expect(event.subtitleTracks, hasLength(2));
      expect(event.subtitleTracks![0].label, 'Commentary');
      expect(event.subtitleTracks![0].language, isNull);
      expect(event.subtitleTracks![1].label, '5');
      expect(event.subtitleTracks![1].language, isNull);
    });

    test('gates track lists by schema version and payload shape', () {
      final legacy = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'kind': 'FILE_LOADED',
        'audioTracks': <Object?>[
          <String, Object?>{'id': '1', 'label': 'Legacy'},
        ],
      });
      final malformed = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 2,
        'kind': 'FILE_LOADED',
        'audioTracks': <String, Object?>{'id': '1'},
        'subtitleTracks': 'not a list',
      });
      final empty = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 2,
        'kind': 'PLAYBACK_RESTART',
        'audioTracks': <Object?>[],
        'subtitleTracks': <Object?>[],
      });

      expect(legacy.audioTracks, isNull);
      expect(legacy.subtitleTracks, isNull);
      expect(malformed.audioTracks, isNull);
      expect(malformed.subtitleTracks, isNull);
      expect(empty.audioTracks, isEmpty);
      expect(empty.subtitleTracks, isEmpty);
    });

    test('parses ERROR kind with message and code', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 2,
        'sequence': 5,
        'kind': 'ERROR',
        'message': 'demuxer failed',
        'code': 'demuxer_error',
        'recoverable': true,
      });

      expect(event.kind, DesktopLibmpvEventKind.error);
      expect(event.message, 'demuxer failed');
      expect(event.code, 'demuxer_error');
      expect(event.recoverable, isTrue);
    });

    test('parses END_FILE kind', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 3,
        'sequence': 10,
        'kind': 'END_FILE',
      });

      expect(event.kind, DesktopLibmpvEventKind.endFile);
    });

    test('parses STOP kind', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 4,
        'sequence': 11,
        'kind': 'STOP',
      });

      expect(event.kind, DesktopLibmpvEventKind.stop);
    });

    test('parses VIDEO_RECONFIG kind', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 5,
        'sequence': 7,
        'kind': 'VIDEO_RECONFIG',
        'videoAspectRatio': 2.35,
      });

      expect(event.kind, DesktopLibmpvEventKind.videoReconfig);
      expect(event.videoAspectRatio, 2.35);
    });

    test('unknown kind maps to unknown, not error', () {
      final event = DesktopLibmpvEvent.fromMap(<String, Object?>{
        'schemaVersion': 1,
        'handle': 6,
        'sequence': 0,
        'kind': 'FOOBAR',
      });

      expect(event.kind, DesktopLibmpvEventKind.unknown);
    });
  });

  group('DesktopLibmpvEventReducer', () {
    const source = PlaybackSource(uri: 'https://example.test/live.m3u8');
    const idle = PlaybackState(
      backend: PlaybackBackend.desktopLibmpv,
      status: PlaybackStatus.idle,
    );

    test('START_FILE maps to loading', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 0,
          'kind': 'START_FILE',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.loading);
      expect(next.source, source);
    });

    test('FILE_LOADED maps to ready', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 1,
          'kind': 'FILE_LOADED',
          'positionMs': 0,
          'durationMs': 60000,
          'videoAspectRatio': 1.78,
        }),
        source,
      );
      expect(next.status, PlaybackStatus.ready);
      expect(next.duration, const Duration(milliseconds: 60000));
      expect(next.videoAspectRatio, 1.78);
    });

    test('PLAYBACK_RESTART not paused and not buffering maps to playing', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
          'paused': false,
          'buffering': false,
        }),
        source,
      );
      expect(next.status, PlaybackStatus.playing);
    });

    test('PLAYBACK_RESTART with buffering maps to buffering', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
          'paused': false,
          'buffering': true,
        }),
        source,
      );
      expect(next.status, PlaybackStatus.buffering);
    });

    test('PLAYBACK_RESTART with paused maps to paused', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
          'paused': true,
          'buffering': false,
        }),
        source,
      );
      expect(next.status, PlaybackStatus.paused);
    });

    test('VIDEO_RECONFIG updates aspect ratio only', () {
      final previous = idle.copyWith(
        status: PlaybackStatus.playing,
        position: const Duration(seconds: 10),
      );
      final next = DesktopLibmpvEventReducer.reduce(
        previous,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 4,
          'kind': 'VIDEO_RECONFIG',
          'videoAspectRatio': 2.35,
        }),
        source,
      );
      expect(next.status, PlaybackStatus.playing);
      expect(next.position, const Duration(seconds: 10));
      expect(next.videoAspectRatio, 2.35);
    });

    test('END_FILE maps to completed', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 8,
          'kind': 'END_FILE',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.completed);
    });

    test('STOP maps to stopped', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 9,
          'kind': 'STOP',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.stopped);
    });

    test('QUIT maps to stopped', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 9,
          'kind': 'QUIT',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.stopped);
    });

    test('ERROR produces no state change (error is emitted separately)', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 5,
          'kind': 'ERROR',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.idle);
    });

    test('SHUTDOWN maps to backend error state stopped', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 99,
          'kind': 'SHUTDOWN',
        }),
        source,
      );
      expect(next.status, PlaybackStatus.stopped);
    });

    test('position and speed are forwarded', () {
      final next = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 1,
          'handle': 1,
          'sequence': 3,
          'kind': 'PLAYBACK_RESTART',
          'paused': false,
          'buffering': false,
          'positionMs': 42000,
          'durationMs': 120000,
          'speed': 1.5,
          'aid': '2',
          'sid': '3',
        }),
        source,
      );
      expect(next.position, const Duration(milliseconds: 42000));
      expect(next.duration, const Duration(milliseconds: 120000));
      expect(next.playbackSpeed, 1.5);
      expect(next.selectedAudioTrackId, '2');
      expect(next.selectedSubtitleTrackId, '3');
    });

    test('preserves track lists across selection and disable events', () {
      final loaded = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 1,
          'kind': 'FILE_LOADED',
          'aid': '1',
          'sid': '4',
          'audioTracks': <Object?>[
            <String, Object?>{'id': '1', 'label': 'English'},
            <String, Object?>{'id': '2', 'label': 'Deutsch'},
          ],
          'subtitleTracks': <Object?>[
            <String, Object?>{'id': '4', 'label': 'English CC'},
          ],
        }),
        source,
      );
      final omitted = DesktopLibmpvEventReducer.reduce(
        loaded,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
        }),
        source,
      );
      final disabled = DesktopLibmpvEventReducer.reduce(
        omitted,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 3,
          'kind': 'PLAYBACK_RESTART',
          'aid': 'no',
          'sid': '',
        }),
        source,
      );
      final selected = DesktopLibmpvEventReducer.reduce(
        disabled,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 4,
          'kind': 'PLAYBACK_RESTART',
          'aid': '2',
          'sid': '4',
          'audioTracks': <Object?>[
            <String, Object?>{'id': '1', 'label': 'English'},
            <String, Object?>{'id': '2', 'label': 'Deutsch'},
          ],
          'subtitleTracks': <Object?>[
            <String, Object?>{'id': '4', 'label': 'English CC'},
          ],
        }),
        source,
      );

      expect(loaded.audioTracks, hasLength(2));
      expect(loaded.subtitleTracks, hasLength(1));
      expect(omitted.audioTracks, same(loaded.audioTracks));
      expect(omitted.subtitleTracks, same(loaded.subtitleTracks));
      expect(disabled.selectedAudioTrackId, isNull);
      expect(disabled.selectedSubtitleTrackId, isNull);
      expect(disabled.audioTracks, same(loaded.audioTracks));
      expect(disabled.subtitleTracks, same(loaded.subtitleTracks));
      expect(selected.selectedAudioTrackId, '2');
      expect(selected.selectedSubtitleTrackId, '4');
      expect(selected.audioTracks, hasLength(2));
      expect(selected.subtitleTracks, hasLength(1));
    });

    test('distinguishes unknown selections from confirmed disabled', () {
      final loaded = DesktopLibmpvEventReducer.reduce(
        idle,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 1,
          'kind': 'FILE_LOADED',
          'audioTracks': <Object?>[
            <String, Object?>{'id': '1', 'label': 'English'},
          ],
          'subtitleTracks': <Object?>[
            <String, Object?>{'id': '4', 'label': 'English CC'},
          ],
        }),
        source,
      );
      final disabled = DesktopLibmpvEventReducer.reduce(
        loaded,
        DesktopLibmpvEvent.fromMap(<String, Object?>{
          'schemaVersion': 2,
          'handle': 1,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
          'aid': 'no',
          'sid': '',
        }),
        source,
      );

      expect(loaded.isAudioTrackSelectionKnown, isFalse);
      expect(loaded.isSubtitleTrackSelectionKnown, isFalse);
      expect(disabled.isAudioTrackSelectionKnown, isTrue);
      expect(disabled.isSubtitleTrackSelectionKnown, isTrue);
      expect(disabled.selectedAudioTrackId, isNull);
      expect(disabled.selectedSubtitleTrackId, isNull);
      expect(disabled.audioTracks, same(loaded.audioTracks));
      expect(disabled.subtitleTracks, same(loaded.subtitleTracks));
    });
  });

  group('DesktopLibmpvBackend event integration', () {
    const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
    const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    test(
      'subscribes to events before load and emits ready on FILE_LOADED',
      () async {
        final events = StreamController<Map<String, Object?>>.broadcast();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              switch (call.method) {
                case 'probe':
                  return <String, Object?>{
                    'platform': 'linux',
                    'windowSystem': 'wayland',
                    'videoApi': 'sw',
                    'ownedSurface': true,
                    'libmpvAvailable': true,
                    'renderApiAvailable': true,
                    'canPlayFixture': true,
                    'fallbackDecision': 'none',
                    'details': 'mock',
                  };
                case 'load':
                  // Emit FILE_LOADED concurrently so load() can complete.
                  scheduleMicrotask(() {
                    events.add(<String, Object?>{
                      'schemaVersion': 1,
                      'handle': 7,
                      'sequence': 0,
                      'kind': 'START_FILE',
                    });
                    events.add(<String, Object?>{
                      'schemaVersion': 1,
                      'handle': 7,
                      'sequence': 1,
                      'kind': 'FILE_LOADED',
                      'positionMs': 0,
                      'durationMs': 60000,
                      'videoAspectRatio': 1.78,
                    });
                  });
                  return <String, Object?>{
                    'ok': true,
                    'handle': 7,
                    'textureId': 99,
                  };
                default:
                  return null;
              }
            });

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, eventSink) {
                  events.stream.listen((event) {
                    eventSink.success(event);
                  });
                },
              ),
            );

        final backend = DesktopLibmpvBackend();
        final states = <PlaybackState>[];
        final stateSub = backend.onState.listen(states.add);

        await backend.load(
          const PlaybackSource(uri: 'https://example.test/live.m3u8'),
        );

        await pumpEventQueue();

        expect(
          states.map((s) => s.status),
          containsAllInOrder(<PlaybackStatus>[
            PlaybackStatus.loading,
            PlaybackStatus.ready,
          ]),
        );
        expect(states.last.videoAspectRatio, 1.78);

        await stateSub.cancel();
        await backend.dispose();
        await events.close();
      },
    );

    test('publishes v2 track lists through selection transitions', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 2,
                  'handle': 70,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                  'aid': '1',
                  'sid': '4',
                  'audioTracks': <Object?>[
                    <String, Object?>{'id': '1', 'label': 'English'},
                    <String, Object?>{'id': '2', 'label': 'Deutsch'},
                  ],
                  'subtitleTracks': <Object?>[
                    <String, Object?>{'id': '4', 'label': 'English CC'},
                  ],
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 70,
                'textureId': 700,
              };
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen(eventSink.success);
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);
      await backend.load(
        const PlaybackSource(uri: 'https://example.test/tracks.mkv'),
      );
      events
        ..add(<String, Object?>{
          'schemaVersion': 2,
          'handle': 70,
          'sequence': 1,
          'kind': 'PLAYBACK_RESTART',
          'sid': 'no',
        })
        ..add(<String, Object?>{
          'schemaVersion': 2,
          'handle': 70,
          'sequence': 2,
          'kind': 'PLAYBACK_RESTART',
          'aid': '2',
        });
      await pumpEventQueue();

      expect(states.last.audioTracks, hasLength(2));
      expect(states.last.subtitleTracks, hasLength(1));
      expect(states.last.selectedAudioTrackId, '2');
      expect(states.last.selectedSubtitleTrackId, isNull);

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('ignores events from stale handle', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            switch (call.method) {
              case 'load':
                scheduleMicrotask(() {
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 2,
                    'sequence': 0,
                    'kind': 'START_FILE',
                  });
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 1,
                    'sequence': 99,
                    'kind': 'PLAYBACK_RESTART',
                    'paused': false,
                    'buffering': false,
                  });
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 2,
                    'sequence': 1,
                    'kind': 'FILE_LOADED',
                  });
                });
                return <String, Object?>{
                  'ok': true,
                  'handle': 2,
                  'textureId': 100,
                };
              default:
                return null;
            }
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/a.m3u8'),
      );
      await pumpEventQueue();

      expect(
        states.map((s) => s.status),
        isNot(contains(PlaybackStatus.playing)),
      );
      expect(states.last.status, PlaybackStatus.ready);

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('ignores out-of-order sequence for same handle', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 3,
                  'sequence': 2,
                  'kind': 'FILE_LOADED',
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 3,
                  'sequence': 1,
                  'kind': 'PLAYBACK_RESTART',
                  'paused': false,
                  'buffering': false,
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 3,
                'textureId': 101,
              };
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/b.m3u8'),
      );
      await pumpEventQueue();

      expect(states.last.status, PlaybackStatus.ready);

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('terminal error during load is delivered only by load', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 4,
                  'sequence': 0,
                  'kind': 'START_FILE',
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 4,
                  'sequence': 1,
                  'kind': 'ERROR',
                  'message': 'network unreachable',
                  'code': 'network_unavailable',
                  'recoverable': true,
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 4,
                  'sequence': 2,
                  'kind': 'PLAYBACK_RESTART',
                  'paused': false,
                  'buffering': false,
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 4,
                'textureId': 102,
              };
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final errors = <PlaybackError>[];
      final states = <PlaybackState>[];
      final errorSub = backend.onError.listen(errors.add);
      final stateSub = backend.onState.listen(states.add);

      await expectLater(
        backend.load(const PlaybackSource(uri: 'https://example.test/c.m3u8')),
        throwsA(isA<PlaybackException>()),
      );
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(
        states.map((s) => s.status),
        isNot(contains(PlaybackStatus.playing)),
      );

      await errorSub.cancel();
      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('EOF event maps to completed', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 5,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 5,
                  'sequence': 1,
                  'kind': 'END_FILE',
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 5,
                'textureId': 103,
              };
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/d.m3u8'),
      );
      await pumpEventQueue();

      expect(states.last.status, PlaybackStatus.completed);

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('ERROR before FILE_LOADED fails only load without hanging', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            methodCalls.add(call);
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 51,
                  'sequence': 0,
                  'kind': 'ERROR',
                  'message': 'demuxer failed',
                  'code': 'mpv-end-file-error',
                  'recoverable': true,
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 51,
                  'sequence': 1,
                  'kind': 'END_FILE',
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 51,
                'textureId': 5100,
              };
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen(eventSink.success);
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final errors = <PlaybackError>[];
      final states = <PlaybackState>[];
      final errorSub = backend.onError.listen(errors.add);
      final stateSub = backend.onState.listen(states.add);

      await expectLater(
        backend
            .load(const PlaybackSource(uri: 'https://example.test/error.m3u8'))
            .timeout(const Duration(seconds: 1)),
        throwsA(
          isA<PlaybackException>().having(
            (error) => error.code,
            'code',
            'mpv-end-file-error',
          ),
        ),
      );
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(states, isEmpty);
      expect(backend.textureId, isNull);
      final disposeCalls = methodCalls
          .where((call) => call.method == 'dispose')
          .toList();
      expect(disposeCalls, hasLength(1));
      expect(disposeCalls.single.arguments, <String, Object?>{'handle': 51});

      await errorSub.cancel();
      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test(
      'event channel error before load response disposes the late handle once',
      () async {
        final loadResponse = Completer<Map<String, Object?>>();
        final methodCalls = <MethodCall>[];
        late MockStreamHandlerEventSink nativeEvents;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              methodCalls.add(call);
              if (call.method == 'load') return loadResponse.future;
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, eventSink) {
                  nativeEvents = eventSink;
                },
              ),
            );

        final backend = DesktopLibmpvBackend();
        final errors = <PlaybackError>[];
        final errorSub = backend.onError.listen(errors.add);
        final load = backend.load(
          const PlaybackSource(uri: 'https://example.test/delayed.m3u8'),
        );

        await pumpEventQueue();
        nativeEvents.error(
          code: 'native-event-channel-failed',
          message: 'event transport failed',
        );
        await pumpEventQueue();
        loadResponse.complete(<String, Object?>{
          'ok': true,
          'handle': 53,
          'textureId': 5300,
        });

        await expectLater(
          load.timeout(const Duration(seconds: 1)),
          throwsA(
            isA<PlaybackException>().having(
              (error) => error.code,
              'code',
              'event-stream-error',
            ),
          ),
        );
        await pumpEventQueue();

        expect(errors, isEmpty);
        expect(backend.textureId, isNull);
        final disposeCalls = methodCalls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(1));
        expect(disposeCalls.single.arguments, <String, Object?>{'handle': 53});

        await errorSub.cancel();
        await backend.dispose();
      },
    );

    test(
      'END_FILE before FILE_LOADED fails only load without hanging',
      () async {
        final events = StreamController<Map<String, Object?>>.broadcast();
        final methodCalls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              methodCalls.add(call);
              if (call.method == 'load') {
                scheduleMicrotask(() {
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 52,
                    'sequence': 0,
                    'kind': 'END_FILE',
                  });
                });
                return <String, Object?>{
                  'ok': true,
                  'handle': 52,
                  'textureId': 5200,
                };
              }
              return null;
            });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(
              eventChannel,
              MockStreamHandler.inline(
                onListen: (arguments, eventSink) {
                  events.stream.listen(eventSink.success);
                },
              ),
            );

        final backend = DesktopLibmpvBackend();
        final errors = <PlaybackError>[];
        final errorSub = backend.onError.listen(errors.add);

        await expectLater(
          backend
              .load(const PlaybackSource(uri: 'https://example.test/end.m3u8'))
              .timeout(const Duration(seconds: 1)),
          throwsA(
            isA<PlaybackException>().having(
              (error) => error.code,
              'code',
              'desktop-libmpv-ended-before-ready',
            ),
          ),
        );
        await pumpEventQueue();

        expect(errors, isEmpty);
        expect(backend.textureId, isNull);
        final disposeCalls = methodCalls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(1));
        expect(disposeCalls.single.arguments, <String, Object?>{'handle': 52});

        await errorSub.cancel();
        await backend.dispose();
        await events.close();
      },
    );

    test('buffering event maps to buffering status', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 6,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 6,
                  'sequence': 1,
                  'kind': 'PLAYBACK_RESTART',
                  'paused': false,
                  'buffering': true,
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle': 6,
                'textureId': 104,
              };
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/e.m3u8'),
      );
      await pumpEventQueue();

      expect(states.last.status, PlaybackStatus.buffering);

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('new load disposes previous handle and ignores its events', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      final methodCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            methodCalls.add(call);
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle':
                      call.arguments?['uri'] ==
                          'https://example.test/first.m3u8'
                      ? 10
                      : 11,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
              });
              return <String, Object?>{
                'ok': true,
                'handle':
                    call.arguments?['uri'] == 'https://example.test/first.m3u8'
                    ? 10
                    : 11,
                'textureId': 200,
              };
            }
            if (call.method == 'dispose') {
              return null;
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/first.m3u8'),
      );
      await backend.load(
        const PlaybackSource(uri: 'https://example.test/second.m3u8'),
      );
      await pumpEventQueue();

      expect(methodCalls.map((c) => c.method), contains('dispose'));
      expect(states.last.status, PlaybackStatus.ready);
      expect(
        states.map((s) => s.status),
        isNot(contains(PlaybackStatus.playing)),
      );

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });

    test('buffers events before handle is known then drains', () async {
      final events = StreamController<Map<String, Object?>>.broadcast();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') {
              // Emit events BEFORE returning so _handle is still null.
              events.add(<String, Object?>{
                'schemaVersion': 1,
                'handle': 8,
                'sequence': 0,
                'kind': 'START_FILE',
              });
              events.add(<String, Object?>{
                'schemaVersion': 1,
                'handle': 8,
                'sequence': 1,
                'kind': 'FILE_LOADED',
                'positionMs': 0,
                'durationMs': 120000,
              });
              return <String, Object?>{
                'ok': true,
                'handle': 8,
                'textureId': 105,
              };
            }
            return null;
          });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final backend = DesktopLibmpvBackend();
      final states = <PlaybackState>[];
      final stateSub = backend.onState.listen(states.add);

      await backend.load(
        const PlaybackSource(uri: 'https://example.test/buffer.m3u8'),
      );
      await pumpEventQueue();

      expect(states.map((s) => s.status), contains(PlaybackStatus.loading));
      expect(states.last.status, PlaybackStatus.ready);
      expect(states.last.duration, const Duration(milliseconds: 120000));

      await stateSub.cancel();
      await backend.dispose();
      await events.close();
    });
  });
}
