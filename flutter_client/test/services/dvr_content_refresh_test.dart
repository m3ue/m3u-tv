import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/push_notification_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _testCredentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'dvrtest',
  password: 'dvrtest-pass',
);

/// Initial VOD/Series data the controller sees during its
/// `_replaceWithXtreamContent` bootstrap — its `name` ("Initial Movie" /
/// "Initial Show") is distinct from the post-push fixture so tests can
/// prove a refresh actually fetched new data rather than just asserting
/// the controller still has its initial state.
final VodItem _postPushVod = VodItem.fromXtream(
  <String, Object?>{'stream_id': 7001, 'name': 'New Recording Movie'},
  'http://fixture.invalid/movie/7001.mp4',
);
final Series _postPushSeries = Series.fromXtream(
  <String, Object?>{'series_id': 8001, 'name': 'New Episode Show'},
);

/// Builds a [DvrRecording] suitable for firing into the controller's DVR
/// push handler. The pushed status is only consulted for the
/// `deleted`-short-circuit in `_onDvrStatusPush` — for everything else the
/// controller fetches the full detail via `get_dvr_recording` and uses THAT
/// status (see the matching fixture
/// detail). Pass [season] and [episode] for documentation; they only matter
/// if a test enqueues a matching detail.
DvrRecording _recording({
  required String uuid,
  required String status,
  int? season,
  int? episode,
  String title = 'Recording',
}) {
  final json = <String, Object?>{
    'uuid': uuid,
    'title': title,
    'status': status,
  };
  if (season != null) json['season'] = season;
  if (episode != null) json['episode_number'] = episode;
  return DvrRecording.fromXtream(json);
}

/// Enqueues a detail row for the next `get_dvr_recording` call (in FIFO
/// order). Tests that need a specific status / season / episode combo
/// (e.g. "this push represents a completed series-episode recording") call
/// this before `simulateDvrStatus` so the controller's classifier sees the
/// right shape.
typedef DetailEnqueuer = void Function(Map<String, Object?> detail);

/// How long the controller's DVR-content-refresh debounce delays before
/// firing the batched fetch (see `AppStateController._scheduleDvrContentRefresh`).
/// Each test calls `await _waitForDebounce()` after pushing a
/// completed/post-processing recording so it gets a fresh 1700ms wait — the
/// debounce uses a real `dart:async` `Timer`, which `fakeAsync` would also
/// intercept but the default `PushNotificationService` blocks on a platform
/// channel that no test harness services, so we run real-time here.
const _refreshDebounceDelay = Duration(milliseconds: 1700);

Future<void> _waitForDebounce() => Future<void>.delayed(_refreshDebounceDelay);

void main() {
  group('DVR post-processing refreshes content lists', () {
    test(
      'completed + season+episode → only Series re-fetched, VOD NOT touched',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Detail is a completed series episode → controller classifies the
        // refresh target as Series only. VOD is not in the refresh set.
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-series',
            status: 'completed',
            season: 2,
            episode: 5,
          ),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 1);
        expect(counts['get_series'], 2);
        // Series was refreshed — controller picked up the post-push fixture.
        expect(fixture.controller.seriesList.single.name, 'New Episode Show');
        // VOD was not re-fetched — still the initial fixture data.
        expect(fixture.controller.vodItems.single.name, 'Initial Movie');
        // VOD cache was not re-written after the initial connect write.
        final vodCache = await fixture.cacheService.get<List<VodItem>>(
          'vodStreams',
        );
        expect(vodCache?.data.single.name, 'Initial Movie');
      },
    );

    test(
      'completed + no season/episode → BOTH VOD and Series re-fetched',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Detail has no season/episode → classifier falls back to BOTH lists
        // (the issue permits over-refresh, never under-refresh).
        fixture.enqueueNextDetail(<String, Object?>{
          'uuid': 'rec-movie',
          'title': 'Recording',
          'status': 'completed',
        });
        fixture.transport.setVodItems(<VodItem>[_postPushVod]);
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-movie', status: 'completed'),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 2);
        expect(counts['get_series'], 2);
        // Both lists picked up the post-push fixture data — proves the
        // refresh actually fired (the initial data was Initial Movie /
        // Initial Show).
        expect(
          fixture.controller.vodItems.single.name,
          'New Recording Movie',
        );
        expect(fixture.controller.seriesList.single.name, 'New Episode Show');
      },
    );

    test(
      'postProcessing status triggers refresh (same as completed)',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Detail has wire-format status `post_processing` (the JSON the
        // server sends) plus season/episode → controller classifies as
        // Series-only, like a completed episode.
        fixture.enqueueNextDetail(<String, Object?>{
          'uuid': 'rec-postproc',
          'title': 'Recording',
          'status': 'post_processing',
          'season': 1,
          'episode_number': 3,
        });
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-postproc',
            status: 'post_processing',
            season: 1,
            episode: 3,
          ),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 1);
        expect(counts['get_series'], 2);
      },
    );

    test(
      'Other detail statuses (scheduled/recording/failed/cancelled/'
      ' deleted/unknown) do NOT trigger refresh',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // For each non-refresh-triggering status, enqueue a matching detail
        // row so the controller sees that status when it re-fetches the
        // recording. The pushed wire status on its own is NOT what the
        // controller checks — it refetches and uses the detail's status.
        for (final status in <String>[
          'scheduled',
          'recording',
          'failed',
          'cancelled',
          'unknown',
          'deleted',
        ]) {
          fixture.transport.actionCounts.clear();
          fixture.enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-$status',
            'title': 'Recording',
            'status': status,
          });
          fixture.reverb.simulateDvrStatus(
            _recording(uuid: 'rec-$status', status: status),
          );
          await _waitForDebounce();

          final counts = fixture.transport.actionCounts;
          expect(
            counts['get_vod_streams'] ?? 0,
            0,
            reason: 'VOD re-fetched for status "$status"',
          );
          expect(
            counts['get_series'] ?? 0,
            0,
            reason: 'Series re-fetched for status "$status"',
          );
        }
      },
    );
  });

  group('debounce coalesces multiple pushes', () {
    test(
      'Multiple completed pushes within debounce window → single batched '
      'refresh',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Three pushes back-to-back. Targets union to {vod, series}, so the
        // batched refresh should fetch each list exactly once.
        fixture.transport.setVodItems(<VodItem>[_postPushVod]);
        fixture.transport.setSeries(<Series>[_postPushSeries]);
        fixture
          ..enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-1',
            'title': 'Recording',
            'status': 'completed',
            'season': 1,
            'episode_number': 1,
          })
          ..enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-2',
            'title': 'Recording',
            'status': 'completed',
          })
          ..enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-3',
            'title': 'Recording',
            'status': 'completed',
            'season': 4,
            'episode_number': 9,
          });

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-1',
            status: 'completed',
            season: 1,
            episode: 1,
          ),
        );
        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-2', status: 'completed'),
        );
        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-3',
            status: 'completed',
            season: 4,
            episode: 9,
          ),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 2);
        expect(counts['get_series'], 2);
      },
    );

    test(
      'Mixed targets in the same window — only fetch each list once',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // First push: series-only (has season+episode). Second push: both
        // targets. Their contributions coalesce into one batched refresh.
        fixture.transport.setVodItems(<VodItem>[_postPushVod]);
        fixture.transport.setSeries(<Series>[_postPushSeries]);
        fixture
          ..enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-ep',
            'title': 'Recording',
            'status': 'completed',
            'season': 2,
            'episode_number': 5,
          })
          ..enqueueNextDetail(<String, Object?>{
            'uuid': 'rec-movie',
            'title': 'Recording',
            'status': 'completed',
          });

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-ep',
            status: 'completed',
            season: 2,
            episode: 5,
          ),
        );
        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-movie', status: 'completed'),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 2);
        expect(counts['get_series'], 2);
        expect(
          fixture.controller.vodItems.single.name,
          'New Recording Movie',
        );
        expect(fixture.controller.seriesList.single.name, 'New Episode Show');
      },
    );

    test(
      'Second push AFTER debounce fires creates a SECOND refresh',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Both pushes use the default detail (completed series-episode),
        // so each fires a Series-only refresh.
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-a',
            status: 'completed',
            season: 1,
            episode: 1,
          ),
        );
        await _waitForDebounce();

        var counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 1);
        expect(counts['get_series'], 2);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-b',
            status: 'completed',
            season: 1,
            episode: 2,
          ),
        );
        await _waitForDebounce();

        counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 1);
        expect(counts['get_series'], 3);
      },
    );

    test(
      'push arriving while a flush is still in-flight (slow network) is '
      'coalesced into the next loop iteration, not run as a concurrent '
      'duplicate fetch',
      () async {
        // Regression test for a bug where a push landing mid-flush — its own
        // debounce timer already cleared by the in-flight flush — started an
        // independent second flush that issued a duplicate `get_series` call
        // while the first was still awaiting. The fix makes
        // `_flushDvrContentRefresh` loop internally instead, guarded by
        // `_dvrContentRefreshFlushing`.
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        final hold = Completer<void>();
        fixture.transport.holdSeries = hold;
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        // Push A: debounce fires, flush starts, `get_series` call #2 begins
        // and parks on `hold`.
        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-a', status: 'completed', season: 1, episode: 1),
        );
        await _waitForDebounce();
        expect(fixture.transport.actionCounts['get_series'], 2);

        // Push B arrives while flush A is still parked. Its own debounce
        // timer fires 1500ms later, well before `hold` is released below.
        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-b', status: 'completed', season: 1, episode: 2),
        );
        await _waitForDebounce();

        // Push B's timer fired, but `_dvrContentRefreshFlushing` was still
        // true, so it must NOT have started a concurrent second fetch — the
        // call count stays at 2 while flush A is still parked.
        expect(fixture.transport.actionCounts['get_series'], 2);

        // Release flush A. It resolves, sees push B's target still pending,
        // and loops to fetch it — one more call, not a race with a second
        // in-flight one.
        hold.complete();
        await pumpEventQueue();

        expect(fixture.transport.actionCounts['get_series'], 3);
      },
    );
  });

  group('error handling and notifications', () {
    test(
      'VOD fetch failure is swallowed and does not prevent Series fetch',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Detail with no season/episode → refresh fires for both lists, so
        // we exercise both transports' failure and success paths in one go.
        fixture.enqueueNextDetail(<String, Object?>{
          'uuid': 'rec-movie-fail',
          'title': 'Recording',
          'status': 'completed',
        });
        fixture.transport.setSeries(<Series>[_postPushSeries]);
        fixture.transport.failVodNext = true;

        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-movie-fail', status: 'completed'),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        // VOD transport was attempted (and threw); Series succeeded.
        expect(counts['get_vod_streams'], 2);
        expect(counts['get_series'], 2);
        expect(fixture.controller.seriesList.single.name, 'New Episode Show');
        // VOD list stays at its initial value — the helper returned false
        // before assigning, so _vodItems was never overwritten.
        expect(fixture.controller.vodItems.single.name, 'Initial Movie');
      },
    );

    test(
      'Series fetch failure is swallowed and does not prevent VOD fetch',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        fixture.enqueueNextDetail(<String, Object?>{
          'uuid': 'rec-movie-fail2',
          'title': 'Recording',
          'status': 'completed',
        });
        fixture.transport.setVodItems(<VodItem>[_postPushVod]);
        fixture.transport.failSeriesNext = true;

        fixture.reverb.simulateDvrStatus(
          _recording(uuid: 'rec-movie-fail2', status: 'completed'),
        );
        await _waitForDebounce();

        final counts = fixture.transport.actionCounts;
        expect(counts['get_vod_streams'], 2);
        expect(counts['get_series'], 2);
        expect(
          fixture.controller.vodItems.single.name,
          'New Recording Movie',
        );
        expect(fixture.controller.seriesList.single.name, 'Initial Show');
      },
    );

    test('Both fetches fail → no extra notifyListeners', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      expect(
        await fixture.controller.connectXtream(_testCredentials),
        isTrue,
      );
      await fixture.reverb.connected.future;

      fixture.enqueueNextDetail(<String, Object?>{
        'uuid': 'rec-both-fail',
        'title': 'Recording',
        'status': 'completed',
      });
      fixture.transport.failVodNext = true;
      fixture.transport.failSeriesNext = true;

      var notifyCount = 0;
      fixture.controller.addListener(() => notifyCount++);

      fixture.reverb.simulateDvrStatus(
        _recording(uuid: 'rec-both-fail', status: 'completed'),
      );
      // _refreshDvrRecordingDetail's notifyListeners() should have fired
      // by now (get_dvr_recording completed, list updated, notify ran).
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifyCount, 1);

      await _waitForDebounce();

      // Both helpers returned false → no extra notifyListeners from
      // _flushDvrContentRefresh.
      expect(notifyCount, 1);
    });
  });

  group('cache and dispose', () {
    test('Successful refresh does NOT write new data to cache', () async {
      final fixture = _Fixture();
      addTearDown(fixture.dispose);
      expect(
        await fixture.controller.connectXtream(_testCredentials),
        isTrue,
      );
      await fixture.reverb.connected.future;

      // Default detail (completed series-episode) → Series-only refresh.
      fixture.transport.setSeries(<Series>[_postPushSeries]);

      fixture.reverb.simulateDvrStatus(
        _recording(
          uuid: 'rec-cache',
          status: 'completed',
          season: 2,
          episode: 5,
        ),
      );
      await _waitForDebounce();

      // In-memory state IS updated — the refresh actually fetched new data.
      expect(fixture.controller.seriesList.single.name, 'New Episode Show');
      // Cache is NOT rewritten: it stays at the connect-time whole-bundle
      // replace value. Rewriting per-key here would risk persisting
      // another account's library if the ownership predicate goes stale
      // mid-fetch — the same bug class that #160 exists to prevent.
      final seriesCache = await fixture.cacheService.get<List<Series>>(
        'seriesStreams',
      );
      expect(seriesCache, isNotNull);
      expect(seriesCache!.data, hasLength(1));
      expect(seriesCache.data.single.name, 'Initial Show');
    });

    test('dispose() cancels pending debounce timer', () async {
      final fixture = _Fixture();
      expect(
        await fixture.controller.connectXtream(_testCredentials),
        isTrue,
      );
      await fixture.reverb.connected.future;

      fixture.reverb.simulateDvrStatus(
        _recording(uuid: 'rec-dispose', status: 'completed'),
      );
      // Debounce is scheduled but has not fired yet (delay = 1500ms).

      // Dispose immediately, well before the debounce window elapses.
      fixture.controller.dispose();

      await _waitForDebounce();

      final counts = fixture.transport.actionCounts;
      // No second fetch occurred — dispose cancelled the timer.
      expect(counts['get_vod_streams'], 1);
      expect(counts['get_series'], 1);
    });

    test(
      'dispose() DURING an in-flight refresh does not notify a disposed '
      'notifier',
      () async {
        // Cancelling the debounce timer only helps before it fires. Here the
        // timer fires, the Series fetch is held open, and dispose lands while
        // it is still in flight — so the flush resumes against a disposed
        // notifier. _flushDvrContentRefresh runs from a fire-and-forget Timer
        // callback, so an unguarded notifyListeners() here surfaces as an
        // unhandled async error rather than being caught anywhere.
        final fixture = _Fixture();
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        final hold = Completer<void>();
        fixture.transport.holdSeries = hold;
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-dispose-inflight',
            status: 'completed',
            season: 1,
            episode: 1,
          ),
        );

        // Let the debounce fire so the Series fetch starts and then parks on
        // the hold completer.
        await _waitForDebounce();
        expect(fixture.transport.actionCounts['get_series'], 2);

        // Dispose while the fetch is still parked, then release it.
        fixture.controller.dispose();
        hold.complete();
        await pumpEventQueue();

        // Reaching here without an unhandled error is the assertion: the
        // flush saw _disposed and bailed instead of notifying.
        expect(fixture.transport.actionCounts['get_series'], 2);
      },
    );
  });

  group('ownership change mid-flight abandons refresh', () {
    test(
      'Flipping ownsWork() to false mid-flight abandons the refresh — '
      'in-memory state is NOT overwritten',
      () async {
        // The whole point of the rework. A 1500ms debounce sits between
        // _refreshDvrRecordingDetail's notifyListeners() and
        // _flushDvrContentRefresh's getSeries/getVodStreams fetches. If
        // account/source ownership flips during that window (account switch,
        // logout, source swap), the in-flight refresh must NOT overwrite
        // _vodItems / _seriesList — that would write another account's
        // library into current state.
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        final hold = Completer<void>();
        fixture.transport.holdSeries = hold;
        fixture.transport.setSeries(<Series>[_postPushSeries]);

        fixture.reverb.simulateDvrStatus(
          _recording(
            uuid: 'rec-ownership-flip',
            status: 'completed',
            season: 1,
            episode: 1,
          ),
        );

        // Let the debounce fire so the Series fetch starts and then parks
        // on the hold completer.
        await _waitForDebounce();
        expect(fixture.transport.actionCounts['get_series'], 2);

        // Flip ownsWork() to false mid-flight. AuthNotifier.disconnect()
        // nulls out both auth.credentials and xtreamService.credentials,
        // so the captured predicate — which checks
        // _sameCredentials(authNotifier.credentials, capturedCreds) AND
        // _sameCredentials(xtreamService.credentials, capturedCreds) —
        // now returns false on the next call. _disposed stays false, so
        // this test exercises the ownsWork path, not the dispose path.
        await fixture.auth.disconnect();

        // Release the parked fetch. The transport returns the post-push
        // fixture data; the refresh sees ownsWork()=false on its post-await
        // check and bails before overwriting _seriesList.
        hold.complete();
        await pumpEventQueue();

        // Fetch DID fire (proves the test isn't accidentally short-
        // circuiting earlier), but in-memory state was NOT overwritten —
        // the controller still holds its initial value.
        expect(fixture.transport.actionCounts['get_series'], 2);
        expect(fixture.controller.seriesList.single.name, 'Initial Show');
      },
    );
  });

  group('Active-recordings reconnect reconciliation', () {
    // _refreshActiveDvrRecordings is the reconnect-time recovery path for a
    // missed DVR status push: it must repair both _recordingChannelIds (the
    // live-channel dot) AND _dvrRecordings (the list backing the Recordings
    // screen and EPG badges). The bare-transport default returns [] for
    // get_dvr_recordings, so each test below seeds the two filtered buckets
    // (no status, status=recording) and inspects both controller fields.
    Map<String, Object?> dvrRecordingsJson({
      required String uuid,
      required String status,
      int? channelId,
      String channelName = 'Channel A',
      String title = 'Recording',
    }) {
      final json = <String, Object?>{
        'uuid': uuid,
        'title': title,
        'status': status,
      };
      if (channelId != null) json['channel_id'] = channelId;
      json['channel_name'] = channelName;
      return json;
    }

    test(
      'a) Scheduled recording flips to Recording on reconnect (REGRESSION)',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        // Initial state from the connect-time `get_dvr_recordings` (no
        // status filter): one Scheduled recording on channel 42.
        fixture.transport.setDvrRecordingsAll(<Map<String, Object?>>[
          dvrRecordingsJson(
            uuid: 'rec-flip',
            status: 'scheduled',
            channelId: 42,
          ),
        ]);
        // Reconnect-time active fetch (status=recording): the server now
        // reports the SAME recording as Recording.
        fixture.transport.setDvrRecordingsActive(<Map<String, Object?>>[
          dvrRecordingsJson(
            uuid: 'rec-flip',
            status: 'recording',
            channelId: 42,
          ),
        ]);

        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Pre-refresh sanity: state is what the connect seeded.
        expect(fixture.controller.dvrRecordings, hasLength(1));
        expect(
          fixture.controller.dvrRecordings.single.status,
          DvrRecordingStatus.scheduled,
        );
        // (Note: _recordingChannelIds already contains 42 here, because the
        // connect-time fetch also ran isInProgress filtering and 42 was
        // filtered. Test (a)'s distinguishing power is the dvrRecordings
        // status flip — not the channel id.)

        // Drive the reconnect reconciliation explicitly. The harness's
        // _RecordingReverbService does NOT fire the onConnected callback,
        // so the production code's own unawaited _refreshActiveDvrRecordings
        // has not yet run. Calling it directly is the same code path.
        await fixture.controller.refreshActiveDvrRecordings();

        // BOTH _recordingChannelIds and the entry in _dvrRecordings must
        // now reflect Recording — this is the regression test: pre-fix, the
        // active reconcile patched only the channel-ids set and left the
        // dvrRecordings entry stuck on Scheduled.
        expect(
          fixture.controller.dvrRecordings.single.uuid,
          'rec-flip',
        );
        expect(
          fixture.controller.dvrRecordings.single.status,
          DvrRecordingStatus.recording,
        );
        // Channel id parity: the dot is on, and the entry points at the
        // same channel. _recordingChannelIds is private but observable via
        // the public EPG channel map; assert via dvrRecordings instead.
        expect(
          fixture.controller.dvrRecordings.single.channelId,
          42,
        );
      },
    );

    test(
      'b) Already-Recording entry causes no splice and no notifyListeners',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        // Connect-time state: one recording already in Recording status.
        fixture.transport.setDvrRecordingsAll(<Map<String, Object?>>[
          dvrRecordingsJson(
            uuid: 'rec-unchanged',
            status: 'recording',
            channelId: 7,
          ),
        ]);
        // Reconnect-time active fetch: SAME uuid, SAME status. Nothing
        // should change.
        fixture.transport.setDvrRecordingsActive(<Map<String, Object?>>[
          dvrRecordingsJson(
            uuid: 'rec-unchanged',
            status: 'recording',
            channelId: 7,
          ),
        ]);

        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;

        // Wire a notify-count spy. attach it BEFORE refreshActive so we
        // catch every notification fired by the function and its awaits.
        var notifyCount = 0;
        fixture.controller.addListener(() => notifyCount++);

        await fixture.controller.refreshActiveDvrRecordings();

        // Allow any trailing microtasks to settle so an erroneous late
        // notify would be caught.
        await pumpEventQueue();
        await pumpEventQueue();

        expect(
          notifyCount,
          0,
          reason:
              'No notifyListeners() must fire when _recordingChannelIds was '
              'already correct AND _mergeActiveDvrRecordings returns null '
              '(no status disagreement, no new uuids). A test that only '
              'checked end-state would pass even if every reconcile '
              'notifyed unnecessarily.',
        );
        // End-state sanity (defence in depth).
        expect(fixture.controller.dvrRecordings, hasLength(1));
        expect(
          fixture.controller.dvrRecordings.single.status,
          DvrRecordingStatus.recording,
        );
      },
    );

    test(
      'c) Recording in active fetch but unknown to _dvrRecordings is '
      'inserted, not dropped',
      () async {
        final fixture = _Fixture();
        addTearDown(fixture.dispose);
        // Connect-time state: empty — the controller knows of no recordings.
        // (Default dvrRecordingsAll = []; default dvrRecordingsActive = []).
        // Reconnect-time active fetch: a single recording the controller has
        // never seen. This models "first connect racing a push" — the push
        // path never ran for this recording, and connect-time fetch
        // returned it under a status other than `recording` so it was
        // missed there too.
        fixture.transport.setDvrRecordingsActive(<Map<String, Object?>>[
          dvrRecordingsJson(
            uuid: 'rec-new',
            status: 'recording',
            channelId: 11,
          ),
        ]);

        expect(
          await fixture.controller.connectXtream(_testCredentials),
          isTrue,
        );
        await fixture.reverb.connected.future;
        expect(fixture.controller.dvrRecordings, isEmpty);

        await fixture.controller.refreshActiveDvrRecordings();

        expect(fixture.controller.dvrRecordings, hasLength(1));
        expect(fixture.controller.dvrRecordings.single.uuid, 'rec-new');
        expect(
          fixture.controller.dvrRecordings.single.status,
          DvrRecordingStatus.recording,
        );
        expect(fixture.controller.dvrRecordings.single.channelId, 11);
        // Insertion convention: unknown uuid is inserted at index 0,
        // matching _refreshDvrRecordingDetail's existing pattern.
        expect(fixture.controller.dvrRecordings.first.uuid, 'rec-new');
      },
    );
  });
}

class _Fixture {
  _Fixture() {
    cacheService = CacheService(memory: <String, Object?>{});
    transport = _RecordingXtreamTransport();
    xtream = XtreamService(
      transport: transport.call,
      cache: cacheService,
    );
    auth = AuthNotifier(
      xtreamService: xtream,
      secureStorage: InMemorySecureStorage(),
    );
    reverb = _RecordingReverbService();
    controller = AppStateController(
      authNotifier: auth,
      xtreamService: xtream,
      secureStorage: auth.secureStorage,
      cacheService: cacheService,
      favoritesService: FavoritesService(memory: <String, Object?>{}),
      vodFavoritesService: FavoritesService(
        memory: <String, Object?>{},
        namespace: 'vod',
      ),
      seriesFavoritesService: FavoritesService(
        memory: <String, Object?>{},
        namespace: 'series',
      ),
      viewerService: ViewerService(memory: <String, Object?>{}),
      reverbService: reverb,
      tvNotificationService: _ReverbReadyTvNotificationService(),
      // Tests don't exercise push registration; injecting a no-op fake
      // prevents the real Firebase-backed default from hanging on
      // platform-channel calls.
      pushNotificationService: _NoopPushNotificationService(),
    );
  }

  late final _RecordingXtreamTransport transport;
  late final XtreamService xtream;
  late final AuthNotifier auth;
  late final _RecordingReverbService reverb;
  late final CacheService cacheService;
  late final AppStateController controller;

  /// Delegates to the transport's `enqueueNextDetail` so test bodies don't
  /// have to reach through `fixture.transport` for detail shaping.
  void enqueueNextDetail(Map<String, Object?> detail) =>
      transport.enqueueNextDetail(detail);

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
  }
}

class _RecordingXtreamTransport {
  final List<String> actions = <String>[];
  final Map<String, int> _actionCounts = <String, int>{};

  /// Returns the live internal map so tests can `clear()` between
  /// iterations (e.g. the "other statuses" loop) without leaking state
  /// across iterations. Callers MUST NOT mutate individual values.
  Map<String, int> get actionCounts => _actionCounts;

  /// What `get_vod_streams` returns. Defaults to the initial bootstrap
  /// data; tests call `setVodItems` to change what the post-push refresh
  /// returns.
  List<Map<String, Object?>> _vodItems = <Map<String, Object?>>[
    <String, Object?>{'stream_id': 1, 'name': 'Initial Movie'},
  ];

  /// What `get_series` returns. Defaults to the initial bootstrap data;
  /// tests call `setSeries` to change what the post-push refresh returns.
  List<Map<String, Object?>> _seriesItems = <Map<String, Object?>>[
    <String, Object?>{'series_id': 1, 'name': 'Initial Show'},
  ];

  /// Default detail returned by `get_dvr_recording` when the queue is
  /// empty: a completed series-episode recording, so the basic tests
  /// (which don't override) get Series-only refreshes.
  static const Map<String, Object?> _defaultDvrDetail = <String, Object?>{
    'uuid': 'rec-default',
    'title': 'Default Recording',
    'status': 'completed',
    'season': 1,
    'episode_number': 1,
  };

  /// FIFO of detail rows to return for successive `get_dvr_recording`
  /// calls. Tests enqueue here when they need the controller to see a
  /// specific status/season/episode combo (the push's wire status is
  /// ignored past the `deleted`-short-circuit — see
  /// AppStateController._onDvrStatusPush).
  final List<Map<String, Object?>> _nextDvrDetails = <Map<String, Object?>>[];

  bool failVodNext = false;
  bool failSeriesNext = false;

  /// `get_dvr_recordings` response when called with no status filter
  /// (the connect-time fetch). Default empty — tests in the reconnect-
  /// reconciliation group override per-test.
  List<Map<String, Object?>> _dvrRecordingsAll = const <Map<String, Object?>>[];

  /// `get_dvr_recordings` response when called with status=recording
  /// (the reconnect-time active-fetch). Default empty.
  List<Map<String, Object?>> _dvrRecordingsActive =
      const <Map<String, Object?>>[];

  /// When set, `get_series` awaits this before returning, letting a test
  /// hold the refresh open and dispose the controller mid-flight.
  Completer<void>? holdSeries;

  void setDvrRecordingsAll(List<Map<String, Object?>> items) {
    _dvrRecordingsAll = List<Map<String, Object?>>.from(items);
  }

  void setDvrRecordingsActive(List<Map<String, Object?>> items) {
    _dvrRecordingsActive = List<Map<String, Object?>>.from(items);
  }

  void setVodItems(List<VodItem> items) {
    _vodItems = items
        .map(
          (v) => <String, Object?>{
            'stream_id': v.id,
            'name': v.name,
          },
        )
        .toList(growable: false);
  }

  void setSeries(List<Series> items) {
    _seriesItems = items
        .map(
          (s) => <String, Object?>{
            'series_id': s.id,
            'name': s.name,
          },
        )
        .toList(growable: false);
  }

  /// Appends [detail] to the per-call queue. The next `get_dvr_recording`
  /// call will pop it; subsequent calls fall back to [_defaultDvrDetail].
  void enqueueNextDetail(Map<String, Object?> detail) {
    _nextDvrDetails.add(Map<String, Object?>.from(detail));
  }

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    actions.add(action);
    _actionCounts[action] = (_actionCounts[action] ?? 0) + 1;
    switch (action) {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            // Enables AppStateController.hasDvrFeature so the connect-time
            // fetch populates _dvrRecordings. Without this the controller
            // short-circuits the DVR fetch at the feature-gate (line 2193)
            // and leaves _dvrRecordings empty — which makes the reconnect-
            // reconciliation tests below blind to their own state.
            'features': <String>['dvr'],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
        return const <Object?>[];
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_recently_watched':
        return const <Object?>[];
      case 'get_vod_streams':
        if (failVodNext) {
          failVodNext = false;
          throw StateError('simulated VOD failure');
        }
        return List<Map<String, Object?>>.from(_vodItems);
      case 'get_series':
        if (failSeriesNext) {
          failSeriesNext = false;
          throw StateError('simulated Series failure');
        }
        final hold = holdSeries;
        if (hold != null) {
          holdSeries = null;
          await hold.future;
        }
        return List<Map<String, Object?>>.from(_seriesItems);
      case 'get_dvr_recording':
        if (_nextDvrDetails.isNotEmpty) {
          return <String, Object?>{..._nextDvrDetails.removeAt(0)};
        }
        return <String, Object?>{..._defaultDvrDetail};
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'get_dvr_storage':
        // The connect flow now calls refreshDvrStorage() (because
        // features: ['dvr'] is enabled). Return an empty/unlimited scope so
        // the helper returns false and the controller's _dvrStorageInfo
        // stays null — the existing tests don't assert on storage state.
        return <String, Object?>{
          'used_bytes': 0,
          'quota_bytes': null,
          'percent_used': null,
          'recording_count': 0,
          'scope': 'account',
        };
      case 'get_dvr_recordings':
        if (request.params['status'] == 'recording') {
          return List<Map<String, Object?>>.from(_dvrRecordingsActive);
        }
        return List<Map<String, Object?>>.from(_dvrRecordingsAll);
      default:
        throw StateError('No fixture for $action');
    }
  }
}

/// Returns a non-empty Reverb session so [AppStateController] actually calls
/// [ReverbService.connect] (the empty-appKey stub short-circuits earlier and
/// would leave the onDvrStatus callback un-captured, breaking every push).
class _ReverbReadyTvNotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => (
    const TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: true,
      channelName: 'tv.playlist.fixture',
      reverb: ReverbConfig(
        host: 'fixture.invalid',
        port: 443,
        scheme: 'wss',
        appKey: 'fixture-key',
      ),
    ),
    const <TvNotificationItem>[],
  );
}

/// Push stub that registers/unregisters immediately and never makes a
/// platform-channel call. Replaces the default Firebase-backed
/// [PushNotificationService], which would hang the test process waiting on
/// a method-channel reply that no platform side exists to send.
class _NoopPushNotificationService extends PushNotificationService {
  @override
  Future<String?> init({
    required PushMessageHandler onForegroundMessage,
    required PushMessageHandler onMessageOpenedApp,
  }) async => null;
}

/// Captures `onDvrStatus` from the controller's call to [ReverbService.connect]
/// so tests can fire it synchronously. Mirrors the recording stub in
/// `push_token_lifecycle_test.dart`.
class _RecordingReverbService extends ReverbService {
  void Function(DvrRecording)? _onDvrStatus;

  /// Completes when [connect] runs. Tests `await` this after
  /// `connectXtream` so they don't fire `simulateDvrStatus` before
  /// `_connectTvNotifications` (an `unawaited` background task after
  /// `_replaceWithXtreamContent` returns) has captured the callback.
  final Completer<void> connected = Completer<void>();

  @override
  Future<void> connect({
    required TvPlaylistSession session,
    required UserCredentials credentials,
    Set<String> subscribedChannels = const <String>{},
    required void Function(TvNotificationItem) onNotification,
    void Function(DvrRecording)? onDvrStatus,
    void Function(MediaRequestSummary)? onRequestStatus,
    void Function(FavoriteToggleEvent)? onFavoriteToggled,
    void Function(String)? onDeviceDeregister,
    void Function()? onConnected,
  }) async {
    _onDvrStatus = onDvrStatus;
    if (!connected.isCompleted) connected.complete();
  }

  /// Synchronously fires the captured `onDvrStatus` callback. The captured
  /// callback schedules `_refreshDvrRecordingDetail` as an unawaited
  /// microtask, which then awaits the transport — see the test bodies for
  /// the real-time waits that drive this end-to-end.
  void simulateDvrStatus(DvrRecording recording) {
    final callback = _onDvrStatus;
    if (callback == null) {
      throw StateError(
        'simulateDvrStatus called before ReverbService.connect captured '
        'the onDvrStatus callback — did connectXtream fail?',
      );
    }
    callback(recording);
  }
}
