import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/m3u_parser.dart';
import 'package:m3u_tv/transcoding/transcoding.dart';

void main() {
  group('production backend policy', () {
    testWidgets(
      'unsupported_codec: Android uses Media3 then server transcode without player diagnostics',
      (tester) async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadFailure: const PlaybackException.unsupported(
            'Unsupported codec hevc/aac on Android Media3',
            backend: PlaybackBackend.androidExoPlayer,
          ),
        );
        final androidMpv = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidMpv,
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'unsupported-stream',
            streamUrl:
                'https://m3u-editor.example/hls/unsupported-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'running',
            sessionId: 'unsupported-session',
          ),
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
            PlaybackBackend.androidMpv: androidMpv,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );
        addTearDown(orchestrator.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://provider.example/live/unsupported.ts',
                title: 'Unsupported Codec Fixture',
                type: 'live',
                videoCodec: 'hevc',
                audioCodec: 'aac',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime(2026)),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(media3.commands, <String>[
          'load:https://provider.example/live/unsupported.ts',
        ]);
        expect(androidMpv.commands, isEmpty);
        expect(gateway.startedServerRequests, hasLength(1));
        expect(gateway.startedServerRequests.single.videoCodec, 'hevc');
        expect(serverPlayer.loadedSources.single.uri, contains('unsupported'));
        expect(orchestrator.activeBackend, PlaybackBackend.serverTranscode);
        expect(
          orchestrator.diagnostics,
          contains('android-mpv:disabled-future-gated:unsupported'),
        );
        expect(
          orchestrator.diagnostics,
          contains('active-backend:serverTranscode:ready'),
        );

        expect(find.text('Backend'), findsNothing);
        expect(find.text('Server transcode fallback'), findsNothing);
        expect(find.text('Fallback'), findsNothing);
        expect(find.textContaining('Unsupported codec hevc/aac'), findsNothing);
        expect(find.text('Transcode'), findsNothing);
        expect(find.textContaining('unsupported-session'), findsNothing);
        expect(find.text('Android mpv/libmpv'), findsNothing);
        expect(find.textContaining('disabled'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    test(
      'desktop policy reports libmpv failure when no server transcode player is registered',
      () async {
        final desktopLibmpv = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException(
            'libmpv shared library not found; tried libmpv.so.2',
          ),
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: desktopLibmpv,
          },
          transcodeGateway: gateway,
        );
        addTearDown(orchestrator.dispose);
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);
        addTearDown(subscription.cancel);

        await orchestrator.open(
          const PlaybackSource(
            uri: 'https://provider.example/vod/movie.mkv',
            videoCodec: 'hevc',
            audioCodec: 'dts',
          ),
        );

        expect(desktopLibmpv.commands, <String>[
          'load:https://provider.example/vod/movie.mkv',
        ]);
        expect(gateway.startedServerRequests, isEmpty);
        expect(orchestrator.activeBackend, isNull);
        expect(errors, hasLength(1));
        expect(errors.single.backend, PlaybackBackend.desktopLibmpv);
        expect(errors.single.code, BackendUnavailableException.unavailableCode);
        expect(
          errors.single.message,
          'libmpv shared library not found; tried libmpv.so.2',
        );
        expect(
          orchestrator.diagnostics,
          contains(
            'load-failed:desktopLibmpv:backend_unavailable:libmpv shared library not found; tried libmpv.so.2',
          ),
        );
        expect(
          orchestrator.diagnostics,
          contains(
            'error:backend_unavailable:libmpv shared library not found; tried libmpv.so.2',
          ),
        );
      },
    );

    test('Windows loader resolves the libmpv DLL bundled by media_kit', () {
      final windowsBackend = File(
        'windows/runner/desktop_libmpv_backend.cpp',
      ).readAsStringSync();
      final releaseWorkflow = File(
        '../.github/workflows/release.yml',
      ).readAsStringSync();

      final bundledNameIndex = windowsBackend.indexOf('L"libmpv-2.dll"');
      final compatibilityNameIndex = windowsBackend.indexOf('L"mpv-2.dll"');
      expect(bundledNameIndex, isNonNegative);
      expect(compatibilityNameIndex, greaterThan(bundledNameIndex));
      expect(
        releaseWorkflow,
        contains(r'foreach ($RelativePath in $Required)'),
      );
      expect(releaseWorkflow, contains(r'Test-Path $Path -PathType Leaf'));
      expect(releaseWorkflow, contains('libmpv-2.dll'));
    });

    test('desktop smoke requires the packaged libmpv runtime', () {
      final smokeTest = File(
        'integration_test/desktop_playback_smoke_test.dart',
      ).readAsStringSync();

      expect(smokeTest, contains('Packaged libmpv unavailable:'));
      expect(smokeTest, isNot(contains('return;')));
    });

    test(
      'desktop software texture render paths use Flutter RGBA pixel buffers',
      () {
        final linuxBackend = File(
          'linux/desktop_libmpv_backend.cc',
        ).readAsStringSync();
        final windowsBackend = File(
          'windows/runner/desktop_libmpv_backend.cpp',
        ).readAsStringSync();

        expect(linuxBackend, contains('char format[] = "rgba";'));
        expect(windowsBackend, contains('char format[] = "rgba";'));
        expect(linuxBackend, contains('mpv_get_property'));
        expect(windowsBackend, contains('mpv_get_property'));
        expect(linuxBackend, contains('getVideoAspectRatio'));
        expect(windowsBackend, contains('getVideoAspectRatio'));
        expect(linuxBackend, isNot(contains('char format[] = "bgra";')));
        expect(windowsBackend, isNot(contains('char format[] = "bgra";')));
      },
    );

    test('desktop libmpv load applies resume start position', () {
      final linuxBackend = File(
        'linux/desktop_libmpv_backend.cc',
      ).readAsStringSync();
      final windowsBackend = File(
        'windows/runner/desktop_libmpv_backend.cpp',
      ).readAsStringSync();

      expect(linuxBackend, contains('startPositionMs'));
      expect(linuxBackend, contains('start='));
      expect(windowsBackend, contains('startPositionMs'));
      expect(windowsBackend, contains('start='));
    });

    test('desktop native event transport shares the libmpv channel ABI', () {
      final linuxBackend = File(
        'linux/desktop_libmpv_backend.cc',
      ).readAsStringSync();
      final windowsBackend = File(
        'windows/runner/desktop_libmpv_backend.cpp',
      ).readAsStringSync();

      for (final backend in <String>[linuxBackend, windowsBackend]) {
        expect(
          backend,
          contains('constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";'),
        );
        expect(
          backend,
          contains(
            'constexpr char kEventChannelName[] = "m3u_tv/desktop_libmpv/events";',
          ),
        );
        expect(backend, contains('"schemaVersion"'));
        expect(backend, contains('"handle"'));
        expect(backend, contains('"sequence"'));
        expect(backend, contains('struct mpv_event_end_file'));
        expect(backend, contains('MPV_END_FILE_REASON_ERROR'));
        expect(backend, contains('snapshot.kind = "ERROR"'));
        expect(backend, contains('snapshot.code = "mpv-end-file-error"'));
        expect(backend, contains('end_file->error'));
      }

      final abiBlocks = <String>[
        linuxBackend.substring(
          linuxBackend.indexOf('struct mpv_event_end_file'),
          linuxBackend.indexOf('constexpr int MPV_FORMAT_DOUBLE'),
        ),
        windowsBackend.substring(
          windowsBackend.indexOf('struct mpv_event_end_file'),
          windowsBackend.indexOf('constexpr int MPV_RENDER_PARAM_INVALID'),
        ),
      ];
      for (final abiBlock in abiBlocks) {
        expect(abiBlock, contains('struct mpv_event_end_file'));
        expect(abiBlock, contains('int reason;'));
        expect(abiBlock, contains('int error;'));
        expect(abiBlock, contains('int64_t playlist_entry_id;'));
        expect(abiBlock, contains('int64_t playlist_insert_id;'));
        expect(abiBlock, contains('int playlist_insert_num_entries;'));
        expect(abiBlock, contains('constexpr int MPV_EVENT_END_FILE = 7;'));
        expect(abiBlock, contains('MPV_END_FILE_REASON_ERROR = 4'));
      }

      final linuxChannelContract = linuxBackend.substring(
        0,
        linuxBackend.indexOf('using mpv_handle'),
      );
      final windowsChannelContract = windowsBackend.substring(
        0,
        windowsBackend.indexOf('using mpv_handle'),
      );
      for (final channelContract in <String>[
        linuxChannelContract,
        windowsChannelContract,
      ]) {
        expect(
          channelContract,
          contains('constexpr char kChannelName[] = "m3u_tv/desktop_libmpv";'),
        );
        expect(
          channelContract,
          contains(
            'constexpr char kEventChannelName[] = "m3u_tv/desktop_libmpv/events";',
          ),
        );
      }

      final linuxEventValueStart = linuxBackend.indexOf(
        'FlValue* BuildEventValue',
      );
      final linuxEventValueEnd = linuxBackend.indexOf(
        'static gboolean SendEventSnapshotOnGtkThread',
        linuxEventValueStart,
      );
      expect(linuxEventValueStart, isNonNegative);
      expect(linuxEventValueEnd, greaterThan(linuxEventValueStart));
      final linuxEventValue = linuxBackend.substring(
        linuxEventValueStart,
        linuxEventValueEnd,
      );
      final windowsEventValueStart = windowsBackend.indexOf(
        'class EventSinkState',
      );
      final windowsEventValueEnd = windowsBackend.indexOf(
        'struct PlayerInstance',
        windowsEventValueStart,
      );
      expect(windowsEventValueStart, isNonNegative);
      expect(windowsEventValueEnd, greaterThan(windowsEventValueStart));
      final windowsEventValue = windowsBackend.substring(
        windowsEventValueStart,
        windowsEventValueEnd,
      );
      for (final eventValue in <String>[
        linuxEventValue,
        windowsEventValue,
      ]) {
        expect(eventValue, contains('if (snapshot.duration > 0.0)'));
        expect(eventValue, contains('"durationMs"'));
      }
      expect(
        linuxEventValue,
        contains(
          'fl_value_set_string_take(event, "schemaVersion", fl_value_new_int(1));',
        ),
      );
      expect(
        linuxEventValue,
        contains(
          'fl_value_set_string_take(event, "handle", fl_value_new_int(snapshot.handle));',
        ),
      );
      expect(
        linuxEventValue,
        contains(
          'fl_value_set_string_take(event, "sequence", fl_value_new_int(snapshot.sequence));',
        ),
      );
      expect(
        windowsEventValue,
        contains(
          '{flutter::EncodableValue("schemaVersion"), flutter::EncodableValue(1)}',
        ),
      );
      expect(
        windowsEventValue,
        contains(
          '{flutter::EncodableValue("handle"), flutter::EncodableValue(snapshot.handle)}',
        ),
      );
      expect(
        windowsEventValue,
        contains(
          '{flutter::EncodableValue("sequence"), flutter::EncodableValue(snapshot.sequence)}',
        ),
      );

      final linuxEndFileStart = linuxBackend.indexOf(
        'case MPV_EVENT_END_FILE:',
      );
      final linuxEndFileEnd = linuxBackend.indexOf(
        'case 1:',
        linuxEndFileStart,
      );
      final windowsEndFileStart = windowsBackend.indexOf(
        'event->event_id == MPV_EVENT_END_FILE',
      );
      final windowsEndFileEnd = windowsBackend.indexOf(
        'event->event_id == MPV_EVENT_SHUTDOWN',
        windowsEndFileStart,
      );
      expect(linuxEndFileStart, isNonNegative);
      expect(linuxEndFileEnd, greaterThan(linuxEndFileStart));
      expect(windowsEndFileStart, isNonNegative);
      expect(windowsEndFileEnd, greaterThan(windowsEndFileStart));
      for (final endFileMapping in <String>[
        linuxBackend.substring(linuxEndFileStart, linuxEndFileEnd),
        windowsBackend.substring(windowsEndFileStart, windowsEndFileEnd),
      ]) {
        expect(endFileMapping, contains('MPV_END_FILE_REASON_ERROR'));
        expect(endFileMapping, contains('snapshot.kind = "ERROR"'));
        expect(
          endFileMapping,
          contains('snapshot.code = "mpv-end-file-error"'),
        );
        expect(endFileMapping, contains('end_file->error'));
      }

      final eventThreadStart = linuxBackend.indexOf(
        'void PlayerInstance::StartEventThread()',
      );
      final eventThreadEnd = linuxBackend.indexOf(
        'FlMethodResponse* Load',
        eventThreadStart,
      );
      expect(eventThreadStart, isNonNegative);
      expect(eventThreadEnd, greaterThan(eventThreadStart));
      final eventThread = linuxBackend.substring(
        eventThreadStart,
        eventThreadEnd,
      );
      expect(eventThread, isNot(contains('fl_value_')));
      expect(eventThread, isNot(contains('fl_event_channel_')));
      expect(linuxBackend, contains('struct EventDispatchState'));
      expect(linuxBackend, contains('void QueueEvent(EventSnapshot snapshot)'));
      expect(linuxBackend, contains('EventSnapshot snapshot;'));
      expect(linuxBackend, contains('event_dispatch_state->Deactivate()'));
    });

    test(
      'desktop software renderers keep frame callbacks without advanced control',
      () {
        final linuxBackend = File(
          'linux/desktop_libmpv_backend.cc',
        ).readAsStringSync();
        final windowsBackend = File(
          'windows/runner/desktop_libmpv_backend.cpp',
        ).readAsStringSync();

        for (final backend in <String>[linuxBackend, windowsBackend]) {
          expect(
            backend,
            isNot(contains('MPV_RENDER_PARAM_ADVANCED_CONTROL')),
          );
          expect(backend, isNot(contains('advanced_control')));
          expect(backend, contains('render_context_set_update_callback'));
          expect(backend, contains('render_context_render('));
        }
        expect(
          windowsBackend,
          contains(
            'player->copy_context->SetUpdateCallback(RenderUpdate, player->texture_state.get())',
          ),
        );
        final platformDispatcherStart = windowsBackend.indexOf(
          'class PlatformDispatcher',
        );
        final platformDispatcherEnd = windowsBackend.indexOf(
          'class EventSinkState',
          platformDispatcherStart,
        );
        expect(platformDispatcherStart, isNonNegative);
        expect(platformDispatcherEnd, greaterThan(platformDispatcherStart));
        final platformDispatcher = windowsBackend.substring(
          platformDispatcherStart,
          platformDispatcherEnd,
        );
        expect(
          platformDispatcher,
          contains('bool Post(std::function<void()> callback)'),
        );
        expect(
          platformDispatcher,
          contains('PostMessageW(hwnd_, kDesktopLibmpvPlatformDispatchMessage'),
        );

        final textureStateStart = windowsBackend.indexOf('struct TextureState');
        final textureStateEnd = windowsBackend.indexOf(
          'struct PlayerInstance',
          textureStateStart,
        );
        expect(textureStateStart, isNonNegative);
        expect(textureStateEnd, greaterThan(textureStateStart));
        final textureState = windowsBackend.substring(
          textureStateStart,
          textureStateEnd,
        );
        expect(textureState, contains('void QueueFrame()'));
        expect(
          textureState,
          contains('std::weak_ptr<PlatformDispatcher> dispatcher'),
        );
        expect(
          textureState,
          contains('std::weak_ptr<TextureState> weak = shared_from_this()'),
        );
        expect(textureState, contains('platform_dispatcher->Post([weak]()'));
        expect(textureState, contains('auto state = weak.lock()'));
        expect(
          textureState,
          contains(
            'state->registrar->MarkTextureFrameAvailable(state->texture_id)',
          ),
        );
        expect(
          textureState.indexOf('platform_dispatcher->Post([weak]()'),
          lessThan(
            textureState.indexOf(
              'state->registrar->MarkTextureFrameAvailable(state->texture_id)',
            ),
          ),
        );

        final renderUpdateStart = windowsBackend.indexOf('void RenderUpdate');
        final renderUpdateEnd = windowsBackend.indexOf(
          'ProbeMap Load',
          renderUpdateStart,
        );
        expect(renderUpdateStart, isNonNegative);
        expect(renderUpdateEnd, greaterThan(renderUpdateStart));
        final renderUpdate = windowsBackend.substring(
          renderUpdateStart,
          renderUpdateEnd,
        );
        expect(renderUpdate, contains('texture_state->QueueFrame()'));
      },
    );

    test(
      'Linux attaches non-inline dispatch to a retained GTK main context',
      () {
        final linuxBackend = File(
          'linux/desktop_libmpv_backend.cc',
        ).readAsStringSync();

        expect(
          linuxBackend,
          contains('g_main_context_default()'),
        );
        expect(
          linuxBackend,
          isNot(contains('g_main_context_invoke')),
        );
        expect(
          linuxBackend,
          contains('g_main_context_ref(g_gtk_main_context)'),
        );
        expect(
          linuxBackend,
          contains('g_main_context_unref(g_gtk_main_context)'),
        );

        final dispatchStart = linuxBackend.indexOf(
          'bool DispatchOnGtkMain',
        );
        final dispatchEnd = linuxBackend.indexOf(
          'struct EventSnapshot',
          dispatchStart,
        );
        expect(dispatchStart, isNonNegative);
        expect(dispatchEnd, greaterThan(dispatchStart));
        final dispatch = linuxBackend.substring(dispatchStart, dispatchEnd);
        final idleSourceIndex = dispatch.indexOf('g_idle_source_new()');
        final callbackIndex = dispatch.indexOf('g_source_set_callback(');
        final attachIndex = dispatch.indexOf(
          'g_source_attach(source, g_gtk_main_context)',
        );
        final unrefIndex = dispatch.indexOf('g_source_unref(source)');
        for (final index in <int>[
          idleSourceIndex,
          callbackIndex,
          attachIndex,
          unrefIndex,
        ]) {
          expect(index, isNonNegative);
        }
        expect(callbackIndex, greaterThan(idleSourceIndex));
        expect(attachIndex, greaterThan(callbackIndex));
        expect(unrefIndex, greaterThan(attachIndex));
        expect(
          dispatch,
          isNot(contains('g_main_context_invoke')),
        );

        final textureStateStart = linuxBackend.indexOf(
          'struct TextureDispatchState',
        );
        final textureStateEnd = linuxBackend.indexOf(
          'struct PlayerInstance {',
          textureStateStart,
        );
        expect(textureStateStart, isNonNegative);
        expect(textureStateEnd, greaterThan(textureStateStart));
        final textureState = linuxBackend.substring(
          textureStateStart,
          textureStateEnd,
        );
        expect(textureState, contains('std::atomic<bool> active{true}'));
        expect(
          textureState,
          contains('if (state->active.load(std::memory_order_acquire) &&'),
        );
        expect(textureState, contains('void Retain()'));
        expect(textureState, contains('void Release()'));
        expect(textureState, contains('void QueueFrame()'));
        expect(textureState, contains('void Deactivate()'));
        expect(
          textureState,
          isNot(contains('g_main_context_invoke')),
        );
        expect(
          textureState,
          contains('DispatchOnGtkMain('),
        );
        expect(
          textureState,
          contains('fl_texture_registrar_mark_texture_frame_available'),
        );
        expect(
          textureState.indexOf('DispatchOnGtkMain('),
          lessThan(
            textureState.indexOf(
              'fl_texture_registrar_mark_texture_frame_available',
            ),
          ),
        );

        final eventDispatchStart = linuxBackend.indexOf(
          'void PlayerInstance::QueueEvent',
        );
        final eventDispatchEnd = linuxBackend.indexOf(
          'void PlayerInstance::ReadSnapshotProperties',
          eventDispatchStart,
        );
        expect(eventDispatchStart, isNonNegative);
        expect(eventDispatchEnd, greaterThan(eventDispatchStart));
        final eventDispatch = linuxBackend.substring(
          eventDispatchStart,
          eventDispatchEnd,
        );
        expect(
          eventDispatch,
          isNot(contains('g_main_context_invoke')),
        );
        expect(
          eventDispatch,
          contains('DispatchOnGtkMain('),
        );

        final renderUpdateStart = linuxBackend.indexOf('void RenderUpdate');
        final renderUpdateEnd = linuxBackend.indexOf(
          'static gboolean SendEventSnapshotOnGtkThread',
          renderUpdateStart,
        );
        expect(renderUpdateStart, isNonNegative);
        expect(renderUpdateEnd, greaterThan(renderUpdateStart));
        final renderUpdate = linuxBackend.substring(
          renderUpdateStart,
          renderUpdateEnd,
        );
        expect(renderUpdate, contains('texture_state->QueueFrame()'));
        expect(
          renderUpdate,
          isNot(contains('fl_texture_registrar_mark_texture_frame_available')),
        );

        final loadStart = linuxBackend.indexOf('FlMethodResponse* Load');
        final loadEnd = linuxBackend.indexOf(
          'FlMethodResponse* Control',
          loadStart,
        );
        expect(loadStart, isNonNegative);
        expect(loadEnd, greaterThan(loadStart));
        final load = linuxBackend.substring(loadStart, loadEnd);
        expect(load, contains('player->texture_state'));
        expect(load, isNot(contains('RenderUpdate, player.get()')));

        final playerStart = linuxBackend.indexOf('struct PlayerInstance {');
        final playerEnd = linuxBackend.indexOf('LibmpvApi g_api', playerStart);
        expect(playerStart, isNonNegative);
        expect(playerEnd, greaterThan(playerStart));
        final playerInstance = linuxBackend.substring(playerStart, playerEnd);
        final disposingIndex = playerInstance.indexOf('disposing.store(true)');
        final detachIndex = playerInstance.indexOf(
          'copy_context->SetUpdateCallback(nullptr, nullptr)',
        );
        final wakeupIndex = playerInstance.indexOf('api->wakeup(handle)');
        final joinIndex = playerInstance.indexOf('event_thread.join()');
        final deactivateIndex = playerInstance.indexOf(
          'texture_state->Deactivate()',
        );
        final unregisterIndex = playerInstance.indexOf(
          'fl_texture_registrar_unregister_texture',
        );
        final releaseResourcesIndex = playerInstance.indexOf(
          'copy_context->ReleaseResources()',
        );
        final textureUnrefIndex = playerInstance.indexOf(
          'g_object_unref(texture)',
        );
        for (final index in <int>[
          disposingIndex,
          detachIndex,
          wakeupIndex,
          joinIndex,
          deactivateIndex,
          unregisterIndex,
          releaseResourcesIndex,
          textureUnrefIndex,
        ]) {
          expect(index, isNonNegative);
        }
        expect(detachIndex, greaterThan(disposingIndex));
        expect(wakeupIndex, greaterThan(detachIndex));
        expect(joinIndex, greaterThan(wakeupIndex));
        expect(deactivateIndex, greaterThan(joinIndex));
        expect(unregisterIndex, greaterThan(deactivateIndex));
        expect(releaseResourcesIndex, greaterThan(unregisterIndex));
        expect(textureUnrefIndex, greaterThan(releaseResourcesIndex));
        expect(playerInstance, isNot(contains('api->render_context_free')));
        expect(playerInstance, isNot(contains('api->terminate_destroy')));
      },
    );

    test(
      'Windows retains raster resources until async unregister completion',
      () {
        final windowsBackend = File(
          'windows/runner/desktop_libmpv_backend.cpp',
        ).readAsStringSync();

        expect(
          windowsBackend,
          isNot(contains('raw_player = player.get()')),
        );

        expect(
          windowsBackend,
          contains('std::shared_ptr<CopyPixelsContext>'),
        );
        expect(
          windowsBackend,
          contains('[ctx = player->copy_context]'),
        );
        expect(windowsBackend, contains('struct TextureReleaseContext'));

        final destructorStart = windowsBackend.indexOf('~PlayerInstance()');
        final destructorEnd = windowsBackend.indexOf(
          'void PlayerInstance::StartEventThread',
          destructorStart,
        );
        expect(destructorStart, isNonNegative);
        expect(destructorEnd, greaterThan(destructorStart));
        final destructor = windowsBackend.substring(
          destructorStart,
          destructorEnd,
        );
        final unregisterIndex = destructor.indexOf(
          'texture_registrar->UnregisterTexture',
        );
        final releaseContextIndex = destructor.indexOf(
          'std::make_shared<TextureReleaseContext>',
        );
        expect(unregisterIndex, isNonNegative);
        expect(releaseContextIndex, isNonNegative);
        expect(unregisterIndex, greaterThan(releaseContextIndex));
        expect(
          destructor,
          contains('UnregisterTexture(texture_id, [release_context]()'),
        );
        expect(
          destructor,
          isNot(contains('UnregisterTexture(texture_id);')),
        );
        expect(destructor, isNot(contains('api->render_context_free')));
        expect(destructor, isNot(contains('api->terminate_destroy')));

        final releaseContextStart = windowsBackend.indexOf(
          'struct TextureReleaseContext',
        );
        final releaseContextEnd = windowsBackend.indexOf(
          'struct PlayerInstance',
          releaseContextStart,
        );
        expect(releaseContextStart, isNonNegative);
        expect(releaseContextEnd, greaterThan(releaseContextStart));
        final releaseContext = windowsBackend.substring(
          releaseContextStart,
          releaseContextEnd,
        );
        expect(
          releaseContext,
          contains('std::unique_ptr<flutter::TextureVariant>'),
        );
        expect(releaseContext, contains('std::shared_ptr<CopyPixelsContext>'));
        expect(releaseContext, contains('copy_context->mutex'));
        expect(
          releaseContext,
          contains('api->render_context_free(render_context)'),
        );
        expect(releaseContext, contains('api->terminate_destroy(handle)'));

        final pixelBufferStart = windowsBackend.indexOf(
          'flutter::PixelBufferTexture(',
        );
        expect(pixelBufferStart, isNonNegative);
        final lambdaEnd = windowsBackend.indexOf(
          'return &ctx->pixel_buffer;',
          pixelBufferStart,
        );
        expect(lambdaEnd, isNonNegative);
        final lambdaSnippet = windowsBackend.substring(
          pixelBufferStart,
          lambdaEnd + 'return &ctx->pixel_buffer;'.length,
        );
        expect(lambdaSnippet, contains('ctx'));
        expect(lambdaSnippet, isNot(contains('raw_player')));
      },
    );

    test(
      'desktop render callback changes share the retained render-state lock',
      () {
        final linuxBackend = File(
          'linux/desktop_libmpv_backend.cc',
        ).readAsStringSync();
        final windowsBackend = File(
          'windows/runner/desktop_libmpv_backend.cpp',
        ).readAsStringSync();

        final linuxContextStart = linuxBackend.indexOf(
          'struct CopyPixelsContext {',
        );
        final linuxContextEnd = linuxBackend.indexOf(
          'struct DisplayInfo',
          linuxContextStart,
        );
        expect(linuxContextStart, isNonNegative);
        expect(linuxContextEnd, greaterThan(linuxContextStart));
        final linuxContext = linuxBackend.substring(
          linuxContextStart,
          linuxContextEnd,
        );
        final linuxSetterStart = linuxContext.indexOf(
          'void SetUpdateCallback(',
        );
        expect(linuxSetterStart, isNonNegative);
        final linuxSetterEnd = linuxContext.indexOf(
          'void Retain()',
          linuxSetterStart,
        );
        expect(linuxSetterEnd, greaterThan(linuxSetterStart));
        final linuxSetter = linuxContext.substring(
          linuxSetterStart,
          linuxSetterEnd,
        );
        final linuxSetterLock = linuxSetter.indexOf(
          'std::lock_guard<std::mutex> lock(mutex)',
        );
        final linuxSetterCall = linuxSetter.indexOf(
          'api->render_context_set_update_callback(',
        );
        expect(linuxSetterLock, isNonNegative);
        expect(linuxSetterCall, greaterThan(linuxSetterLock));

        final linuxCopyStart = linuxContext.indexOf('gboolean CopyPixels(');
        final linuxCopyEnd = linuxContext.indexOf(
          'void ReleaseResources()',
          linuxCopyStart,
        );
        expect(linuxCopyStart, isNonNegative);
        expect(linuxCopyEnd, greaterThan(linuxCopyStart));
        final linuxCopy = linuxContext.substring(linuxCopyStart, linuxCopyEnd);
        final linuxCopyLock = linuxCopy.indexOf(
          'std::lock_guard<std::mutex> lock(mutex)',
        );
        final linuxRender = linuxCopy.indexOf(
          'render_context_render(render_context, params)',
        );
        expect(linuxCopyLock, isNonNegative);
        expect(linuxRender, greaterThan(linuxCopyLock));

        final linuxRelease = linuxContext.substring(
          linuxContext.indexOf('void ReleaseResources()'),
        );
        final linuxReleaseLock = linuxRelease.indexOf(
          'std::lock_guard<std::mutex> lock(mutex)',
        );
        final linuxFree = linuxRelease.indexOf(
          'render_context_free(render_context)',
        );
        expect(linuxReleaseLock, isNonNegative);
        expect(linuxFree, greaterThan(linuxReleaseLock));

        final linuxPlayerStart = linuxBackend.indexOf(
          'struct PlayerInstance {',
        );
        final linuxPlayerEnd = linuxBackend.indexOf(
          'LibmpvApi g_api',
          linuxPlayerStart,
        );
        final linuxPlayer = linuxBackend.substring(
          linuxPlayerStart,
          linuxPlayerEnd,
        );
        final linuxDetach = linuxPlayer.indexOf(
          'copy_context->SetUpdateCallback(nullptr, nullptr)',
        );
        final linuxWake = linuxPlayer.indexOf('api->wakeup(handle)');
        final linuxReleaseResources = linuxPlayer.indexOf(
          'copy_context->ReleaseResources()',
        );
        expect(linuxDetach, isNonNegative);
        expect(linuxWake, greaterThan(linuxDetach));
        expect(linuxReleaseResources, greaterThan(linuxWake));
        expect(
          linuxPlayer,
          isNot(contains('api->render_context_set_update_callback(')),
        );

        final linuxLoadStart = linuxBackend.indexOf('FlMethodResponse* Load');
        final linuxLoadEnd = linuxBackend.indexOf(
          'FlMethodResponse* Control',
          linuxLoadStart,
        );
        final linuxLoad = linuxBackend.substring(linuxLoadStart, linuxLoadEnd);
        expect(
          linuxLoad,
          contains(
            'player->copy_context->SetUpdateCallback(RenderUpdate, player->texture_state)',
          ),
        );
        expect(
          linuxLoad,
          isNot(contains('api.render_context_set_update_callback(')),
        );

        final windowsContextStart = windowsBackend.indexOf(
          'struct CopyPixelsContext {',
        );
        final windowsContextEnd = windowsBackend.indexOf(
          'struct TextureReleaseContext',
          windowsContextStart,
        );
        expect(windowsContextStart, isNonNegative);
        expect(windowsContextEnd, greaterThan(windowsContextStart));
        final windowsContext = windowsBackend.substring(
          windowsContextStart,
          windowsContextEnd,
        );
        final windowsSetterStart = windowsContext.indexOf(
          'void SetUpdateCallback(',
        );
        expect(windowsSetterStart, isNonNegative);
        final windowsSetterEnd = windowsContext.indexOf(
          'std::mutex mutex;',
          windowsSetterStart,
        );
        expect(windowsSetterEnd, greaterThan(windowsSetterStart));
        final windowsSetter = windowsContext.substring(
          windowsSetterStart,
          windowsSetterEnd,
        );
        final windowsSetterLock = windowsSetter.indexOf(
          'std::lock_guard<std::mutex> lock(mutex)',
        );
        final windowsSetterCall = windowsSetter.indexOf(
          'api->render_context_set_update_callback(',
        );
        expect(windowsSetterLock, isNonNegative);
        expect(windowsSetterCall, greaterThan(windowsSetterLock));

        final windowsPixelStart = windowsBackend.indexOf(
          'flutter::PixelBufferTexture(',
        );
        final windowsPixelEnd = windowsBackend.indexOf(
          'const int64_t texture_id',
          windowsPixelStart,
        );
        expect(windowsPixelStart, isNonNegative);
        expect(windowsPixelEnd, greaterThan(windowsPixelStart));
        final windowsPixel = windowsBackend.substring(
          windowsPixelStart,
          windowsPixelEnd,
        );
        final windowsPixelLock = windowsPixel.indexOf(
          'std::lock_guard<std::mutex> lock(ctx->mutex)',
        );
        final windowsRender = windowsPixel.indexOf(
          'ctx->api->render_context_render(ctx->render_context, params)',
        );
        expect(windowsPixelLock, isNonNegative);
        expect(windowsRender, greaterThan(windowsPixelLock));

        final windowsReleaseStart = windowsBackend.indexOf(
          'struct TextureReleaseContext',
        );
        final windowsReleaseEnd = windowsBackend.indexOf(
          'struct PlayerInstance',
          windowsReleaseStart,
        );
        final windowsRelease = windowsBackend.substring(
          windowsReleaseStart,
          windowsReleaseEnd,
        );
        final windowsReleaseLock = windowsRelease.indexOf(
          'std::lock_guard<std::mutex> lock(copy_context->mutex)',
        );
        final windowsFree = windowsRelease.indexOf(
          'api->render_context_free(render_context)',
        );
        expect(windowsReleaseLock, isNonNegative);
        expect(windowsFree, greaterThan(windowsReleaseLock));

        final windowsPlayerStart = windowsBackend.indexOf(
          'struct PlayerInstance {',
        );
        final windowsPlayerEnd = windowsBackend.indexOf(
          'LibmpvApi g_api',
          windowsPlayerStart,
        );
        final windowsPlayer = windowsBackend.substring(
          windowsPlayerStart,
          windowsPlayerEnd,
        );
        final windowsDetach = windowsPlayer.indexOf(
          'copy_context->SetUpdateCallback(nullptr, nullptr)',
        );
        final windowsReleaseContext = windowsPlayer.indexOf(
          'std::make_shared<TextureReleaseContext>',
        );
        final windowsUnregister = windowsPlayer.indexOf(
          'texture_registrar->UnregisterTexture',
        );
        expect(windowsDetach, isNonNegative);
        expect(windowsReleaseContext, greaterThan(windowsDetach));
        expect(windowsUnregister, greaterThan(windowsReleaseContext));
        expect(
          windowsPlayer,
          isNot(contains('api->render_context_set_update_callback(')),
        );

        final windowsLoadStart = windowsBackend.indexOf('ProbeMap Load(');
        final windowsLoadEnd = windowsBackend.indexOf(
          'bool DoubleProperty',
          windowsLoadStart,
        );
        final windowsLoad = windowsBackend.substring(
          windowsLoadStart,
          windowsLoadEnd,
        );
        expect(
          windowsLoad,
          contains(
            'player->copy_context->SetUpdateCallback(RenderUpdate, player->texture_state.get())',
          ),
        );
        expect(
          windowsLoad,
          isNot(contains('api.render_context_set_update_callback(')),
        );
      },
    );

    test('Linux serializes raster callbacks with native teardown', () {
      final linuxBackend = File(
        'linux/desktop_libmpv_backend.cc',
      ).readAsStringSync();

      final contextStart = linuxBackend.indexOf('struct CopyPixelsContext {');
      expect(contextStart, isNonNegative);
      final contextEnd = linuxBackend.indexOf(
        'struct DisplayInfo',
        contextStart,
      );
      expect(contextEnd, greaterThan(contextStart));
      final context = linuxBackend.substring(contextStart, contextEnd);
      expect(context, contains('std::mutex mutex;'));
      expect(context, contains('void Retain()'));
      expect(context, contains('void Release()'));

      final copyStart = context.indexOf('gboolean CopyPixels(');
      final copyEnd = context.indexOf('void ReleaseResources()', copyStart);
      expect(copyStart, isNonNegative);
      expect(copyEnd, greaterThan(copyStart));
      final copy = context.substring(copyStart, copyEnd);
      expect(copy, contains('std::lock_guard<std::mutex> lock(mutex)'));
      expect(copy, contains('render_context_render(render_context, params)'));

      final releaseStart = context.indexOf('void ReleaseResources()');
      expect(releaseStart, isNonNegative);
      final release = context.substring(releaseStart);
      expect(release, contains('std::lock_guard<std::mutex> lock(mutex)'));
      expect(release, contains('render_context_free(render_context)'));
      expect(release, contains('terminate_destroy(handle)'));

      final textureStart = linuxBackend.indexOf('struct _MpvTexture {');
      final textureEnd = linuxBackend.indexOf(
        'struct _MpvTextureClass',
        textureStart,
      );
      expect(textureStart, isNonNegative);
      expect(textureEnd, greaterThan(textureStart));
      final texture = linuxBackend.substring(textureStart, textureEnd);
      expect(texture, contains('CopyPixelsContext* copy_context;'));
      expect(texture, isNot(contains('PlayerInstance*')));

      final callbackStart = linuxBackend.indexOf(
        'gboolean MpvTextureCopyPixels',
      );
      final callbackEnd = linuxBackend.indexOf(
        'void mpv_texture_class_init',
        callbackStart,
      );
      expect(callbackStart, isNonNegative);
      expect(callbackEnd, greaterThan(callbackStart));
      final callback = linuxBackend.substring(callbackStart, callbackEnd);
      expect(callback, contains('context->Retain()'));
      expect(callback, contains('context->CopyPixels('));
      expect(callback, contains('context->Release()'));
      expect(callback, isNot(contains('PlayerInstance')));
      expect(
        linuxBackend,
        contains('texture->copy_context = copy_context;'),
      );
      expect(
        linuxBackend,
        contains('G_OBJECT_CLASS(klass)->finalize = mpv_texture_finalize;'),
      );

      final playerStart = linuxBackend.indexOf('struct PlayerInstance {');
      final playerEnd = linuxBackend.indexOf('LibmpvApi g_api', playerStart);
      expect(playerStart, isNonNegative);
      expect(playerEnd, greaterThan(playerStart));
      final player = linuxBackend.substring(playerStart, playerEnd);
      final unregisterIndex = player.indexOf(
        'fl_texture_registrar_unregister_texture',
      );
      final releaseResourcesIndex = player.indexOf(
        'copy_context->ReleaseResources()',
      );
      expect(unregisterIndex, isNonNegative);
      expect(releaseResourcesIndex, greaterThan(unregisterIndex));
      expect(player, contains('copy_context->Retain()'));
      expect(player, contains('copy_context->Release()'));
      expect(player, isNot(contains('api->render_context_free')));
      expect(player, isNot(contains('api->terminate_destroy')));
    });

    test('desktop buffering follows paused-for-cache only', () {
      final backends = <String>[
        File('linux/desktop_libmpv_backend.cc').readAsStringSync(),
        File('windows/runner/desktop_libmpv_backend.cpp').readAsStringSync(),
      ];

      for (final backend in backends) {
        final snapshotStart = backend.indexOf(
          'void PlayerInstance::ReadSnapshotProperties',
        );
        final snapshotEnd = backend.indexOf(
          'void PlayerInstance::StartEventThread',
          snapshotStart,
        );
        expect(snapshotStart, isNonNegative);
        expect(snapshotEnd, greaterThan(snapshotStart));
        final snapshot = backend.substring(snapshotStart, snapshotEnd);
        expect(snapshot, contains('snapshot->buffering = paused_for_cache;'));
        expect(snapshot, isNot(contains('cache_buffering_state >')));
      }
    });

    test('desktop END_FILE reasons have explicit native mappings', () {
      final backends = <String>[
        File('linux/desktop_libmpv_backend.cc').readAsStringSync(),
        File('windows/runner/desktop_libmpv_backend.cpp').readAsStringSync(),
      ];

      for (final backend in backends) {
        expect(backend, contains('MPV_END_FILE_REASON_EOF = 0'));
        expect(backend, contains('MPV_END_FILE_REASON_STOP = 2'));
        expect(backend, contains('MPV_END_FILE_REASON_QUIT = 3'));
        expect(backend, contains('MPV_END_FILE_REASON_ERROR = 4'));
        expect(backend, contains('MPV_END_FILE_REASON_REDIRECT = 5'));

        final mappingStart = backend.indexOf('switch (end_file_reason)');
        expect(mappingStart, isNonNegative);
        final mappingEnd = backend.indexOf(
          'ReadSnapshotProperties',
          mappingStart,
        );
        expect(mappingEnd, greaterThan(mappingStart));
        final mapping = backend.substring(mappingStart, mappingEnd);
        expect(mapping, contains('case MPV_END_FILE_REASON_EOF:'));
        expect(mapping, contains('snapshot.kind = "END_FILE"'));
        expect(mapping, contains('case MPV_END_FILE_REASON_STOP:'));
        expect(mapping, contains('snapshot.kind = "STOP"'));
        expect(mapping, contains('case MPV_END_FILE_REASON_QUIT:'));
        expect(mapping, contains('snapshot.kind = "QUIT"'));
        expect(mapping, contains('case MPV_END_FILE_REASON_ERROR:'));
        expect(mapping, contains('snapshot.code = "mpv-end-file-error"'));
        expect(mapping, contains('case MPV_END_FILE_REASON_REDIRECT:'));
        expect(
          mapping,
          contains(
            RegExp(r'case MPV_END_FILE_REASON_REDIRECT:\s+continue;'),
          ),
        );
        expect(
          mapping,
          contains('snapshot.code = "mpv-end-file-unknown-reason"'),
        );
        expect(
          mapping,
          isNot(contains('} else {\n            snapshot.kind = "END_FILE"')),
        );
      }
    });

    test('Android Media3 retries mislabeled HLS streams as MPEG-TS', () {
      final media3Plugin = File(
        'android/app/src/main/kotlin/dev/sparkison/tv/Media3PlaybackPlugin.kt',
      ).readAsStringSync();

      expect(media3Plugin, contains('retriedHlsAsProgressive'));
      expect(media3Plugin, contains('MimeTypes.VIDEO_MP2T'));
      expect(
        media3Plugin,
        contains('Input does not start with the #EXTM3U header'),
      );
    });

    test('Android Media3 validates and applies native playback speed', () {
      final media3Plugin = File(
        'android/app/src/main/kotlin/dev/sparkison/tv/Media3PlaybackPlugin.kt',
      ).readAsStringSync();

      expect(media3Plugin, contains('"setPlaybackSpeed" ->'));
      expect(
        media3Plugin,
        contains(
          'PlaybackSpeedValidation.validateAndCreatePlaybackParameters(speed)',
        ),
      );

      final validationClass = File(
        'android/app/src/main/kotlin/dev/sparkison/tv/PlaybackSpeedValidation.kt',
      ).readAsStringSync();
      expect(validationClass, contains('!speed.isFinite() || speed <= 0f'));
    });

    test(
      'failure diagnostics cover decoder failure, dead stream, and stalled transcode',
      () async {
        final decoderFailure = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException(
            message: 'Media3 decoder failed during init',
            backend: PlaybackBackend.androidExoPlayer,
            code: 'decoder_failure',
            recoverable: true,
          ),
        );
        expect(decoderFailure.errors, isEmpty);
        expect(
          decoderFailure.orchestrator.diagnostics,
          contains(
            'fallback-reason:decoder_failure:Media3 decoder failed during init',
          ),
        );
        await decoderFailure.dispose();

        final deadStream = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException(
            message: 'Fixture stream not found',
            backend: PlaybackBackend.androidExoPlayer,
            code: 'stream_not_found',
          ),
        );
        expect(deadStream.errors.single.code, 'stream_not_found');
        expect(deadStream.gateway.startedServerRequests, isEmpty);
        expect(
          deadStream.orchestrator.diagnostics,
          contains(
            'load-failed:androidExoPlayer:stream_not_found:Fixture stream not found',
          ),
        );
        await deadStream.dispose();

        final stalledGateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'stalled-stream',
            streamUrl:
                'https://m3u-editor.example/hls/stalled-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'stalled',
            sessionId: 'stalled-session',
            errorCode: 'transcode_stalled',
            message: 'No HLS segments arrived',
          ),
        );
        final stalled = await _openWithFailure(
          PlaybackPlatform.android,
          PlaybackCapabilities.androidExoPlayer,
          const PlaybackException.unsupported(
            'Unsupported codec vp9/opus',
            backend: PlaybackBackend.androidExoPlayer,
          ),
          gateway: stalledGateway,
        );
        expect(stalled.errors.single.code, 'transcode_stalled');
        expect(stalled.gateway.stoppedServerTranscodes, <String>[
          'stalled-stream:stalled-session',
        ]);
        expect(
          stalled.orchestrator.diagnostics,
          contains(
            'cleanup:server-transcode:stopped:stalled-stream:stalled-session',
          ),
        );
        await stalled.dispose();
      },
    );

    test(
      'cleanup_idempotent: stop and dispose clean backend and transcode session once',
      () async {
        final direct = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException('mpv-2.dll not found'),
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway(
          serverResponse: const TranscodeResponse(
            streamId: 'cleanup-stream',
            streamUrl:
                'https://m3u-editor.example/hls/cleanup-stream/index.m3u8',
            mode: TranscodeMode.server,
            status: 'running',
            sessionId: 'cleanup-session',
          ),
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );

        await orchestrator.open(
          const PlaybackSource(uri: 'https://provider.example/live/news.ts'),
        );
        await orchestrator.stop();
        await orchestrator.stop();
        await orchestrator.dispose();
        await orchestrator.dispose();

        expect(
          serverPlayer.commands.where((command) => command == 'stop'),
          hasLength(1),
        );
        expect(gateway.stoppedServerTranscodes, <String>[
          'cleanup-stream:cleanup-session',
        ]);
        expect(
          orchestrator.diagnostics.where(
            (item) =>
                item ==
                'cleanup:server-transcode:stopped:cleanup-stream:cleanup-session',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'network_loss: buffering timeout retries once then cleans up',
      () async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
          loadStatus: PlaybackStatus.buffering,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
          },
          transcodeGateway: gateway,
          bufferingTimeout: const Duration(milliseconds: 20),
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          const PlaybackSource(uri: 'https://provider.example/live/offline.ts'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(
          media3.commands.where(
            (command) =>
                command == 'load:https://provider.example/live/offline.ts',
          ),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'network_unavailable');
        expect(errors.single.recoverable, isTrue);
        expect(orchestrator.activeBackend, isNull);
        expect(media3.commands, contains('stop'));

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'token_expiry: mid-playback expiry reloads once then errors',
      () async {
        final media3 = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.androidExoPlayer,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.android,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.androidExoPlayer: media3,
          },
          transcodeGateway: gateway,
          retryDelay: Duration.zero,
        );
        final errors = <PlaybackError>[];
        final subscription = orchestrator.onError.listen(errors.add);

        await orchestrator.open(
          const PlaybackSource(
            uri: 'https://provider.example/live/expiring.ts',
          ),
        );
        media3.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();
        media3.emitError(
          const PlaybackError(
            backend: PlaybackBackend.androidExoPlayer,
            message: 'Provider token expired during playback',
            code: 'expired_token',
            recoverable: true,
          ),
        );
        await pumpEventQueue();

        expect(
          media3.commands.where(
            (command) =>
                command == 'load:https://provider.example/live/expiring.ts',
          ),
          hasLength(2),
        );
        expect(errors, hasLength(1));
        expect(errors.single.code, 'expired_token');
        expect(errors.single.recoverable, isTrue);
        expect(
          orchestrator.diagnostics,
          contains('active-retry:expired_token:androidExoPlayer:1'),
        );

        await subscription.cancel();
        await orchestrator.dispose();
      },
    );

    test(
      'rapid_channel_switch: twenty server sessions leave no active backend',
      () async {
        final direct = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          loadFailure: BackendUnavailableException('libmpv unavailable'),
        );
        final serverPlayer = _PolicyPlayerAdapter(
          capabilities: PlaybackCapabilities.serverTranscode,
        );
        final gateway = _PolicyTranscodeGateway();
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: direct,
            PlaybackBackend.serverTranscode: serverPlayer,
          },
          transcodeGateway: gateway,
        );

        for (var index = 0; index < 20; index += 1) {
          await orchestrator.open(
            PlaybackSource(
              uri: 'https://provider.example/live/channel-$index.ts',
              metadata: <String, Object?>{
                'broadcast_network_id': 'network-$index',
              },
            ),
          );
        }
        await orchestrator.dispose();

        expect(orchestrator.activeBackend, isNull);
        expect(gateway.startedServerRequests, hasLength(20));
        expect(gateway.stoppedBroadcasts, hasLength(20));
        expect(gateway.stoppedServerTranscodes, hasLength(20));
        expect(
          serverPlayer.commands.where((command) => command == 'stop'),
          hasLength(20),
        );
      },
    );

    test(
      'large_m3u_epg_perf: fixture stays under documented thresholds',
      () {
        final buffer = StringBuffer('#EXTM3U\n');
        final now = DateTime.utc(2026, 1, 1, 12);
        final programs = <EpgProgram>[];
        for (var index = 0; index < 10000; index += 1) {
          buffer
            ..writeln(
              '#EXTINF:-1 tvg-id="bulk.$index" group-title="Bulk",Bulk $index',
            )
            ..writeln('https://streams.example/live/$index.m3u8');
          programs.add(
            EpgProgram(
              channelId: 'bulk.$index',
              title: 'Current $index',
              description: 'Task 9 bulk EPG fixture',
              start: now.subtract(const Duration(minutes: 5)),
              end: now.add(const Duration(minutes: 55)),
            ),
          );
        }

        final rssBefore = ProcessInfo.currentRss;
        final stopwatch = Stopwatch()..start();
        final playlist = M3UParser().parse(buffer.toString());
        final epg = EpgService(clock: () => now)..loadPrograms(programs);
        final elapsed = stopwatch.elapsed;
        final rssDelta = ProcessInfo.currentRss - rssBefore;

        expect(playlist.channels, hasLength(10000));
        expect(
          epg.lookupForChannel(playlist.channels.last)?.current.title,
          'Current 9999',
        );
        expect(elapsed, lessThan(const Duration(seconds: 2)));
        expect(rssDelta, lessThan(64 * 1024 * 1024));
      },
      timeout: const Timeout(Duration(seconds: 3)),
    );
  });
}

Future<_PolicyOpenResult> _openWithFailure(
  PlaybackPlatform platform,
  PlaybackCapabilities capabilities,
  PlaybackException failure, {
  _PolicyTranscodeGateway? gateway,
}) async {
  final direct = _PolicyPlayerAdapter(
    capabilities: capabilities,
    loadFailure: failure,
  );
  final serverPlayer = _PolicyPlayerAdapter(
    capabilities: PlaybackCapabilities.serverTranscode,
  );
  final transcodeGateway = gateway ?? _PolicyTranscodeGateway();
  final orchestrator = PlaybackOrchestrator(
    platform: platform,
    adapters: <PlaybackBackend, PlayerAdapter>{
      capabilities.backend: direct,
      PlaybackBackend.serverTranscode: serverPlayer,
    },
    transcodeGateway: transcodeGateway,
  );
  final errors = <PlaybackError>[];
  // ignore: cancel_subscriptions
  final subscription = orchestrator.onError.listen(errors.add);

  await orchestrator.open(
    const PlaybackSource(
      uri: 'https://provider.example/live/news.ts',
      videoCodec: 'vp9',
      audioCodec: 'opus',
    ),
  );
  await pumpEventQueue();

  return _PolicyOpenResult(
    orchestrator: orchestrator,
    gateway: transcodeGateway,
    errors: errors,
    subscription: subscription,
  );
}

class _PolicyOpenResult {
  const _PolicyOpenResult({
    required this.orchestrator,
    required this.gateway,
    required this.errors,
    required this.subscription,
  });

  final PlaybackOrchestrator orchestrator;
  final _PolicyTranscodeGateway gateway;
  final List<PlaybackError> errors;
  final StreamSubscription<PlaybackError> subscription;

  Future<void> dispose() async {
    await subscription.cancel();
    await orchestrator.dispose();
  }
}

class _PolicyTranscodeGateway implements PlaybackTranscodeGateway {
  _PolicyTranscodeGateway({this.serverResponse});

  final TranscodeResponse? serverResponse;
  final List<StreamRequest> startedServerRequests = <StreamRequest>[];
  final List<String> stoppedBroadcasts = <String>[];
  final List<String> stoppedServerTranscodes = <String>[];

  @override
  Future<TranscodeResponse> startServerTranscode(StreamRequest request) async {
    startedServerRequests.add(request);
    return serverResponse ??
        TranscodeResponse(
          streamId: 'default-stream-${startedServerRequests.length}',
          streamUrl:
              'https://m3u-editor.example/hls/default-${startedServerRequests.length}/index.m3u8',
          mode: TranscodeMode.server,
          status: 'running',
          sessionId: 'default-session-${startedServerRequests.length}',
        );
  }

  @override
  Future<BroadcastSession?> startBroadcast(StreamRequest request) async {
    final networkId = request.metadata['broadcast_network_id'];
    if (networkId is! String) return null;
    return BroadcastSession(
      networkId: networkId,
      status: BroadcastStatus.running,
      playlistUrl: 'https://m3u-editor.example/broadcast/$networkId/live.m3u8',
      transcodeSessionId: request.sessionId,
    );
  }

  @override
  Future<void> stopBroadcast(String networkId) async {
    stoppedBroadcasts.add(networkId);
  }

  @override
  Future<void> stopServerTranscode({
    required String streamId,
    required String? sessionId,
  }) async {
    stoppedServerTranscodes.add('$streamId:$sessionId');
  }
}

class _PolicyPlayerAdapter implements PlayerAdapter {
  _PolicyPlayerAdapter({
    required this.capabilities,
    this.loadFailure,
    this.loadStatus = PlaybackStatus.ready,
  });

  @override
  final PlaybackCapabilities capabilities;
  final PlaybackException? loadFailure;
  final PlaybackStatus loadStatus;
  final List<String> commands = <String>[];
  final List<PlaybackSource> loadedSources = <PlaybackSource>[];
  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackError> _errorController =
      StreamController<PlaybackError>.broadcast();

  PlaybackState _state = const PlaybackState.idle(
    backend: PlaybackBackend.serverTranscode,
  );

  @override
  Stream<PlaybackState> get onState => _stateController.stream;

  @override
  Stream<PlaybackError> get onError => _errorController.stream;

  @override
  Future<void> load(PlaybackSource source) async {
    commands.add('load:${source.uri}');
    final failure = loadFailure;
    if (failure != null) {
      throw failure;
    }
    loadedSources.add(source);
    _emit(
      PlaybackState(
        backend: capabilities.backend,
        status: loadStatus,
        source: source,
        position: source.startPosition,
      ),
    );
  }

  @override
  Future<void> play() async {
    commands.add('play');
    _emit(_state.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    _emit(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inSeconds}');
    _emit(_state.copyWith(position: position));
  }

  @override
  Future<void> stop() async {
    commands.add('stop');
    _emit(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> dispose() async {
    commands.add('dispose');
    await _stateController.close();
    await _errorController.close();
  }

  @override
  Future<void> setAudioTrack(String? trackId) async {
    commands.add('audio:$trackId');
    _emit(_state.copyWith(selectedAudioTrackId: trackId));
  }

  @override
  Future<void> setSubtitleTrack(String? trackId) async {
    commands.add('subtitle:$trackId');
    _emit(_state.copyWith(selectedSubtitleTrackId: trackId));
  }

  @override
  Future<void> setPlaybackSpeed(double speed) async {
    commands.add('speed:$speed');
    _emit(_state.copyWith(playbackSpeed: speed));
  }

  void _emit(PlaybackState state) {
    _state = state;
    _stateController.add(state);
  }

  void emitError(PlaybackError error) {
    _errorController.add(error);
  }
}
