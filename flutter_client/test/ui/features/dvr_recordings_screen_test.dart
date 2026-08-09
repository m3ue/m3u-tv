import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/dvr/dvr_recordings_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('DvrRecordingsScreen', () {
    testWidgets(
      'renders title and one-line meta with channel, episode, duration, size',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording()]),
        );
        await tester.pumpAndSettle();

        expect(find.text('Evening Movie'), findsOneWidget);
        // Subtitle is no longer rendered in the dense row — channel/episode/
        // duration/size replace it as the second line.
        expect(find.text('Director Cut'), findsNothing);
        // Channel name surfaces in the meta line.
        expect(find.textContaining('BBC One'), findsOneWidget);
        // Season/episode collapses to compact `S{season}-E{episode}` form.
        expect(find.textContaining('S2-E5'), findsOneWidget);
        // Duration + size render as compact labels.
        expect(find.textContaining('2h'), findsOneWidget);
        expect(find.textContaining('GB'), findsOneWidget);
        // `Completed` no longer renders a status word in the meta line — the
        // leading tile carries that information.
        expect(find.text('Completed'), findsNothing);
      },
    );

    testWidgets('completed recording has overflow menu, not an inline delete', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          onDeleteRecording: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      // The always-visible red delete button is gone — there is exactly one
      // overflow affordance per row.
      expect(find.byTooltip('Delete'), findsNothing);
      expect(find.byTooltip('Cancel'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('completed recording opens player with stream_url', (
      tester,
    ) async {
      PlayerArgs? opened;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          onPlay: (args) => opened = args,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Evening Movie'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.streamUrl, 'https://stream.example/recordings/rec-1.mp4');
      expect(opened!.title, 'Evening Movie');
      expect(opened!.type, 'vod');
      expect(opened!.metadata['dvr_uuid'], 'rec-1');
      expect(
        opened!.metadata['edl_url'],
        'https://stream.example/recordings/rec-1.edl',
      );
    });

    testWidgets(
      'in-progress recording renders "● Recording" in the meta line',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_recordingNow()]),
        );
        await tester.pumpAndSettle();

        expect(find.text('Live News'), findsOneWidget);
        // The in-progress status word leads the meta line and carries a
        // filled dot glyph prefix. The exact "● Recording" string uniquely
        // identifies the meta line (the DVR Recordings tab label also
        // contains "Recording", so plain find.textContaining('Recording')
        // would match both — see #177's tabbed layout).
        expect(find.textContaining('● Recording'), findsOneWidget);
        // Channel name still follows as a normal meta segment.
        expect(find.textContaining('News 24'), findsOneWidget);
      },
    );

    testWidgets('in-progress recording opens player with live_url', (
      tester,
    ) async {
      PlayerArgs? opened;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_recordingNow()],
          onPlay: (args) => opened = args,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Live News'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(
        opened!.streamUrl,
        'https://stream.example/recordings/rec-2/live.m3u8',
      );
      expect(opened!.title, 'Live News');
      expect(opened!.type, 'live');
      expect(opened!.metadata['dvr_uuid'], 'rec-2');
    });

    testWidgets(
      'in-progress recording overflow menu offers Stop, never Delete',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_recordingNow()],
            onCancelRecording: (_) async {},
            onCancelAndDeleteRecording: (_) async {},
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();

        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        expect(find.text('Stop'), findsOneWidget);
        expect(find.text('Delete'), findsNothing);
      },
    );

    testWidgets(
      'completed recording overflow menu offers Play, Select, and Delete',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();

        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(find.text('Stop'), findsNothing);
      },
    );

    testWidgets(
      'failed row renders "Failed" in the meta line and a checkbox-free tile',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_failedRecording()],
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Broken Show'), findsOneWidget);
        // No status word was rendered for completed/cancelled/postProcessing
        // before; failed DOES show a status word so the meta line leads with
        // "Failed" (in the error color, asserted via `DefaultTextStyle` below).
        expect(find.textContaining('Failed'), findsOneWidget);
        // The error status surfaces as an Icons.error glyph in the leading
        // tile (the prior layout used the same icon, so this is a smoke test).
        expect(find.byIcon(Icons.error), findsOneWidget);
        // A failed recording is not playable — overflow menu must not show Play.
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsNothing);
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets(
      'overflow Delete shows confirmation dialog and runs callback',
      (tester) async {
        String? deletedUuid;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            onDeleteRecording: (uuid) async {
              deletedUuid = uuid;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Delete recording?'), findsOneWidget);
        await tester.tap(find.text('Delete recording'));
        await tester.pumpAndSettle();

        expect(deletedUuid, 'rec-1');
      },
    );

    testWidgets(
      'overflow Stop "Keep recording" choice stops but keeps it',
      (tester) async {
        String? cancelledUuid;
        String? cancelAndDeletedUuid;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_recordingNow()],
            onCancelRecording: (uuid) async {
              cancelledUuid = uuid;
            },
            onCancelAndDeleteRecording: (uuid) async {
              cancelAndDeletedUuid = uuid;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();

        expect(find.text('Stop recording — Live News'), findsOneWidget);
        await tester.tap(find.text('Keep recording'));
        await tester.pumpAndSettle();

        expect(cancelledUuid, 'rec-2');
        expect(cancelAndDeletedUuid, isNull);
      },
    );

    testWidgets(
      'overflow Stop "Delete recording" choice stops and deletes it',
      (tester) async {
        String? cancelledUuid;
        String? cancelAndDeletedUuid;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_recordingNow()],
            onCancelRecording: (uuid) async {
              cancelledUuid = uuid;
            },
            onCancelAndDeleteRecording: (uuid) async {
              cancelAndDeletedUuid = uuid;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete recording'));
        await tester.pumpAndSettle();

        expect(cancelAndDeletedUuid, 'rec-2');
        expect(cancelledUuid, isNull);
      },
    );

    testWidgets(
      'long-press on a row enters select mode and morphs the tile',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording(), _recordingNow()]),
        );
        await tester.pumpAndSettle();

        // Tap behavior before long-press: completing a long-press would
        // enter select mode and the next tap should toggle selection, not
        // play. Use a synthesized long-press to keep the test deterministic.
        await tester.longPress(find.text('Evening Movie'));
        await tester.pumpAndSettle();

        // Selection action bar appears with the plural count.
        expect(find.text('1 item selected'), findsOneWidget);
        // Leading tile morphs to a checkbox-style indicator in select mode.
        expect(find.byIcon(Icons.check_box), findsOneWidget);
        // Untapped row still renders as an unchecked checkbox.
        expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      },
    );

    testWidgets(
      'overflow Select enters select mode and shows the action bar',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording()]),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        expect(find.text('1 item selected'), findsOneWidget);
      },
    );

    testWidgets(
      'bulk Delete from the action bar calls delete for each selected',
      (tester) async {
        final deleted = <String>[];
        await tester.pumpWidget(
          _TestApp(
            recordings: [
              _completedRecording(),
              _failedRecording(),
              _recordingNow(),
            ],
            onDeleteRecording: (uuid) async {
              deleted.add(uuid);
            },
          ),
        );
        await tester.pumpAndSettle();

        // Enter select mode from the first row's overflow, then tap the
        // other deletable rows to extend the selection (the in-progress
        // row is non-deletable so it should be filtered out by the action
        // bar's Play/Delete availability).
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        // Toggle the failed row's selection via tap. In select mode, tapping
        // a row toggles selection rather than playing.
        await tester.tap(find.text('Broken Show'));
        await tester.pumpAndSettle();
        expect(find.text('2 items selected'), findsOneWidget);

        // The action bar Delete button deletes each selected.
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(deleted.toSet(), <String>{'rec-1', 'rec-4'});
      },
    );

    testWidgets(
      'overflow button is reachable and selectable via D-pad, not just touch',
      (tester) async {
        // Regression test: the play row autofocuses first (index == 0);
        // moving right must land on the overflow button and D-pad select
        // must open the menu.
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        // Overflow menu opens, surfacing Play/Select/Delete for a completed
        // recording.
        expect(find.text('Delete'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete recording?'), findsOneWidget);
      },
    );

    group('inline row actions (desktop/TV)', () {
      testWidgets(
        'completed recording starts collapsed to just the more button',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              recordings: [_completedRecording()],
              onDeleteRecording: (_) async {},
              navigationMode: NavigationMode.directional,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.more_vert), findsOneWidget);
          expect(find.byIcon(Icons.play_arrow), findsNothing);
          expect(find.byIcon(Icons.delete), findsNothing);
        },
      );

      testWidgets(
        'selecting the more button expands actions inline, no floating menu',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              recordings: [_completedRecording()],
              onDeleteRecording: (_) async {},
              navigationMode: NavigationMode.directional,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();

          // Actions render as inline icon buttons, not MenuItemButtons in a
          // floating MenuAnchor overlay. The trigger stays the same "more"
          // icon (just rotated) rather than swapping to a close icon.
          expect(find.byIcon(Icons.play_arrow), findsOneWidget);
          expect(find.byIcon(Icons.check), findsOneWidget);
          expect(find.byIcon(Icons.delete), findsOneWidget);
          expect(find.byType(MenuItemButton), findsNothing);
          expect(find.byIcon(Icons.more_vert), findsOneWidget);
        },
      );

      testWidgets(
        'more button is reachable via D-pad right, not just direct click',
        (tester) async {
          // Regression test: RowActionMenu's inline presentation used to wrap
          // its actions in a nested DpadRegion, which excluded them from the
          // enclosing list region's candidate set. With the list region's
          // horizontalEdge set to `stop`, arrow-right from the row's autofocused
          // content had nothing to land on and consumed the key press instead
          // of reaching the more button — reachable only by direct click/tap.
          await tester.pumpWidget(
            _TestApp(
              recordings: [_completedRecording()],
              onDeleteRecording: (_) async {},
              navigationMode: NavigationMode.directional,
            ),
          );
          await tester.pumpAndSettle();

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();

          expect(find.byIcon(Icons.play_arrow), findsOneWidget);
          expect(find.byIcon(Icons.more_vert), findsOneWidget);
        },
      );

      testWidgets(
        'select mode docks a rail beside the list, reachable via D-pad '
        'right regardless of scroll position, instead of a bottom bar',
        (tester) async {
          // Regression test: a bottom action bar only exists after the last
          // row, so reaching it with a d-pad means holding Down through
          // every row above it — fine for a touch scroll, a real barrier on
          // a long list navigated one focus stop at a time. On TV/desktop
          // this docks a rail beside the list instead, one Right press away
          // from whichever row currently has focus.
          final deleted = <String>[];
          await tester.pumpWidget(
            _TestApp(
              recordings: [_completedRecording()],
              onDeleteRecording: (uuid) async => deleted.add(uuid),
              navigationMode: NavigationMode.directional,
            ),
          );
          await tester.pumpAndSettle();

          await tester.longPress(find.text('Evening Movie'));
          await tester.pumpAndSettle();

          // The rail shows a compact count (with the full sentence as a
          // tooltip), not the bottom bar's inline sentence.
          expect(find.text('1'), findsOneWidget);
          expect(find.text('1 item selected'), findsNothing);
          expect(find.byTooltip('1 item selected'), findsOneWidget);

          // Per-row actions are hidden while selecting, freeing the row's
          // right edge so D-pad right reaches the rail instead.
          expect(find.byIcon(Icons.more_vert), findsNothing);

          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();

          expect(deleted, ['rec-1']);
        },
      );

      testWidgets(
        'tapping an expanded action fires it and collapses the row back',
        (tester) async {
          DvrRecording? played;
          await tester.pumpWidget(
            _TestApp(
              recordings: [_completedRecording()],
              onDeleteRecording: (_) async {},
              onPlay: (_) => played = _completedRecording(),
              navigationMode: NavigationMode.directional,
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.more_vert));
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.play_arrow));
          await tester.pumpAndSettle();

          expect(played, isNotNull);
          expect(find.byIcon(Icons.play_arrow), findsNothing);
          expect(find.byIcon(Icons.more_vert), findsOneWidget);
        },
      );
    });

    testWidgets(
      '"Back" on the stop-recording dialog invokes no callback',
      (tester) async {
        var cancelCalls = 0;
        var cancelAndDeleteCalls = 0;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_recordingNow()],
            onCancelRecording: (_) async {
              cancelCalls += 1;
            },
            onCancelAndDeleteRecording: (_) async {
              cancelAndDeleteCalls += 1;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Stop'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(cancelCalls, 0);
        expect(cancelAndDeleteCalls, 0);
        expect(find.text('Stop recording — Live News'), findsNothing);
      },
    );

    testWidgets(
      'scheduled recording overflow menu offers Stop (no Play, no Delete)',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_scheduledRecording()],
            onCancelRecording: (_) async {},
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        // Scheduled recordings are not playable yet — no Play entry.
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsNothing);
        expect(find.text('Select'), findsOneWidget);
        expect(find.text('Stop'), findsOneWidget);
        expect(find.text('Delete'), findsNothing);
      },
    );

    testWidgets(
      'cancelled recording overflow menu offers Delete (no Play, no Stop)',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_cancelledRecording()],
            onDeleteRecording: (_) async {},
          ),
        );
        await tester.pumpAndSettle();

        // Cancelled recordings are not playable and not cancellable.
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsNothing);
        expect(find.text('Select'), findsOneWidget);
        expect(find.text('Stop'), findsNothing);
        expect(find.text('Delete'), findsOneWidget);
      },
    );

    testWidgets('hides the storage summary when storageInfo is absent', (
      tester,
    ) async {
      await tester.pumpWidget(_TestApp(recordings: [_completedRecording()]));
      await tester.pumpAndSettle();

      expect(find.text('DVR Storage'), findsNothing);
    });

    testWidgets('shows used/quota and percentage when a quota is configured', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          storageInfo: const DvrStorageInfo(
            usedBytes: 5368709120, // 5.0 GB
            quotaBytes: 10737418240, // 10.0 GB
            percentUsed: 50,
            recordingCount: 12,
            scope: 'account',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DVR Storage'), findsOneWidget);
      expect(find.text('5.0 GB of 10.0 GB used'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('12 recordings'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Unlimited'), findsNothing);
    });

    testWidgets(
      'shows an "Unlimited" badge and no percentage without a quota',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            storageInfo: const DvrStorageInfo(
              usedBytes: 1073741824, // 1.0 GB
              recordingCount: 3,
              scope: 'account',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1.0 GB used'), findsOneWidget);
        expect(find.text('Unlimited'), findsOneWidget);
        expect(find.text('3 recordings'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );

    testWidgets('storage bar turns error-colored at >= 90% used', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          storageInfo: const DvrStorageInfo(
            usedBytes: 9500000000,
            quotaBytes: 10000000000,
            percentUsed: 95,
            recordingCount: 20,
            scope: 'account',
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      final expectedColor = ThemeData.dark(
        useMaterial3: true,
      ).colorScheme.error;
      expect(
        (indicator.valueColor! as AlwaysStoppedAnimation<Color>).value,
        expectedColor,
      );
    });

    testWidgets(
      'non-empty series rules + non-empty recordings render both tabs with no layout exception',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording(), _recordingNow()],
            seriesRules: [_seriesRule()],
          ),
        );
        await tester.pumpAndSettle();

        // Recordings tab is the initial tab and renders its list.
        expect(find.text('Evening Movie'), findsOneWidget);
        expect(find.text('Live News'), findsOneWidget);

        // No layout exception — the crash that hid all recordings.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('switching to the Series Rules tab shows the rules', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          seriesRules: [_seriesRule()],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Evening Movie'), findsOneWidget);
      expect(find.text('Test Series Alpha'), findsNothing);

      await tester.tap(find.text('Series Rules'));
      await tester.pumpAndSettle();

      expect(find.text('Test Series Alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Back to the Recordings tab keeps the recordings list intact.
      await tester.tap(find.text('DVR Recordings'));
      await tester.pumpAndSettle();
      expect(find.text('Evening Movie'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'series rule overflow offers Edit rule, Select, and Delete rule',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule()],
            onDeleteSeriesRule: (_) async {},
            onUpdateSeriesRule: (_, _) async {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();

        expect(find.text('Edit rule'), findsOneWidget);
        expect(find.text('Select'), findsOneWidget);
        expect(find.text('Delete rule'), findsOneWidget);
      },
    );

    testWidgets(
      'series rule overflow Delete rule shows confirmation and invokes onDeleteSeriesRule',
      (tester) async {
        DvrSeriesRule? deleted;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule()],
            onDeleteSeriesRule: (rule) async => deleted = rule,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();
        expect(find.text('Test Series Alpha'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete rule'));
        await tester.pumpAndSettle();

        expect(find.text('Delete this series rule?'), findsOneWidget);
        await tester.tap(find.text('Delete series rule'));
        await tester.pumpAndSettle();

        expect(deleted, isNotNull);
        expect(deleted!.id, 7);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('empty series rules list shows dvrSeriesRulesEmpty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(recordings: [_completedRecording()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Evening Movie'), findsOneWidget);

      await tester.tap(find.text('Series Rules'));
      await tester.pumpAndSettle();

      expect(find.text('No series rules'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'selecting Edit rule opens the edit sheet and does NOT delete',
      (
        tester,
      ) async {
        DvrSeriesRule? deletedRule;
        DvrSeriesRule? updatedRule;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule()],
            onDeleteSeriesRule: (rule) async => deletedRule = rule,
            onUpdateSeriesRule: (rule, options) async {
              updatedRule = rule;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();
        expect(find.text('Test Series Alpha'), findsOneWidget);

        // A plain tap on the row no longer does anything — edit/delete are
        // reached only through the row's context menu, same as Recordings.
        await tester.tap(find.text('Test Series Alpha'));
        await tester.pumpAndSettle();
        expect(find.text('Options: Test Series Alpha'), findsNothing);

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit rule'));
        await tester.pumpAndSettle();

        expect(deletedRule, isNull, reason: 'edit must not delete');
        expect(
          find.text('Options: Test Series Alpha'),
          findsOneWidget,
          reason: 'edit sheet opens',
        );
        expect(updatedRule, isNull, reason: 'update fires only on Save');
        expect(tester.takeException(), isNull);

        // Dismiss the options screen without saving.
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(updatedRule, isNull);
      },
    );

    testWidgets(
      'saving the edit sheet calls onUpdateSeriesRule with the rule',
      (
        tester,
      ) async {
        DvrSeriesRule? updatedRule;
        DvrSeriesRuleOptions? updatedOptions;
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule()],
            onUpdateSeriesRule: (rule, options) async {
              updatedRule = rule;
              updatedOptions = options;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit rule'));
        await tester.pumpAndSettle();

        // Sheet pre-fills from the rule: seriesMode all, matchMode contains,
        // keepLast null, priority null.
        expect(find.text('Options: Test Series Alpha'), findsOneWidget);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(updatedRule, isNotNull);
        expect(updatedRule!.id, 7);
        expect(updatedOptions, isNotNull);
        expect(updatedOptions!.channelId, 8);
        expect(updatedOptions!.seriesMode, DvrSeriesMode.all);
        expect(updatedOptions!.matchMode, DvrMatchMode.contains);
        expect(updatedOptions!.keepLast, isNull);
        expect(updatedOptions!.priority, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'long-press on a series rule enters select mode and morphs the tile',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule(), _secondSeriesRule()],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();

        await tester.longPress(find.text('Test Series Alpha'));
        await tester.pumpAndSettle();

        expect(find.text('1 item selected'), findsOneWidget);
        expect(find.byIcon(Icons.check_box), findsOneWidget);
        expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      },
    );

    testWidgets(
      'series rule overflow Select enters select mode and shows the action bar',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule()],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        expect(find.text('1 item selected'), findsOneWidget);
      },
    );

    testWidgets(
      'bulk Delete from the series rules action bar calls delete for each selected',
      (tester) async {
        final deleted = <int>[];
        await tester.pumpWidget(
          _TestApp(
            recordings: [_completedRecording()],
            seriesRules: [_seriesRule(), _secondSeriesRule()],
            onDeleteSeriesRule: (rule) async {
              deleted.add(rule.id);
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Series Rules'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Test Series Beta'));
        await tester.pumpAndSettle();
        expect(find.text('2 items selected'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        expect(deleted.toSet(), <int>{7, 12});
      },
    );

    // -------------------------------------------------------------------------
    // Series-recording-config: Shows tab (third DVR tab) — Tests 1–3
    // -------------------------------------------------------------------------

    testWidgets(
      'DVR screen renders three tabs (Recordings, Series Rules, Shows)',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording()]),
        );
        await tester.pumpAndSettle();

        expect(find.text('DVR Recordings'), findsOneWidget);
        expect(find.text('Series Rules'), findsOneWidget);
        expect(find.text('Shows'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'switching to the Shows tab renders without a layout exception',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording()]),
        );
        await tester.pumpAndSettle();

        // Initial tab is Recordings — confirm no exception before switching.
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Shows'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Shows search field does not hold focus while the Recordings tab is '
      'selected',
      (tester) async {
        // _TestApp provides the three Riverpod overrides (isConfigured,
        // isBootstrapping, dvrSeriesRules) that ShowsScreen needs to render
        // its search field. Without those, the field wouldn't be in the tree.
        await tester.pumpWidget(
          _TestApp(recordings: [_completedRecording()]),
        );
        await tester.pumpAndSettle();

        // Force the Shows tab to build by switching to it first. TabBarView
        // is lazy, so on initial render with Recordings selected the third
        // tab may not be in the tree, which would make a pure "no focus at
        // start" check vacuous. Switching to Shows + back exercises the
        // listener in both directions.
        await tester.tap(find.text('Shows'));
        await tester.pumpAndSettle();
        // The listener must hand focus to the search field once the tab is
        // active — this is the post-fix behavior.
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'dvr/shows-search',
          reason:
              'switching to the Shows tab must move focus to the search field',
        );

        // Switch back to Recordings. Focus must NOT remain stolen on the
        // shows search field — that's the regression we're guarding.
        await tester.tap(find.text('DVR Recordings'));
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          isNot('dvr/shows-search'),
          reason:
              'switching back to Recordings must not leave focus stuck on '
              'the shows search field',
        );
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.recordings,
    this.onPlay,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.storageInfo,
    this.seriesRules = const <DvrSeriesRule>[],
    this.onDeleteSeriesRule,
    this.onUpdateSeriesRule,
    this.navigationMode,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args)? onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final DvrStorageInfo? storageInfo;
  final List<DvrSeriesRule> seriesRules;
  final Future<void> Function(DvrSeriesRule)? onDeleteSeriesRule;
  final Future<void> Function(DvrSeriesRule, DvrSeriesRuleOptions)?
  onUpdateSeriesRule;

  /// Forces `NavigationMode.directional`, which `_useInlineRowActions`
  /// (dvr_recordings_screen.dart) treats as TV — the same signal
  /// `deviceTypeForView` uses. Lets tests exercise the inline expand-in-
  /// place row actions without needing a real tvOS/desktop platform.
  final NavigationMode? navigationMode;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      // ShowsScreen (third DVR tab) watches three Riverpod providers that
      // derive from `appStateControllerProvider`. Recordings/SeriesRules
      // tabs don't read those, so older tests didn't trip the
      // unimplemented-error guard. Override the derived providers here so
      // tests that exercise the Shows tab don't have to wire up a full
      // AppStateController.
      overrides: [
        isConfiguredProvider.overrideWith((_) => true),
        isBootstrappingProvider.overrideWith((_) => false),
        dvrSeriesRulesProvider.overrideWith((_) => const <DvrSeriesRule>[]),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) {
          final mode = navigationMode;
          if (mode == null) return child!;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(navigationMode: mode),
            child: child!,
          );
        },
        home: DvrRecordingsScreen(
          recordings: recordings,
          isLoading: false,
          isConfigured: true,
          onPlay: onPlay ?? (_) {},
          onCancelRecording: onCancelRecording,
          onCancelAndDeleteRecording: onCancelAndDeleteRecording,
          onDeleteRecording: onDeleteRecording,
          storageInfo: storageInfo,
          seriesRules: seriesRules,
          onDeleteSeriesRule: onDeleteSeriesRule,
          onUpdateSeriesRule: onUpdateSeriesRule,
        ),
      ),
    );
  }
}

DvrRecording _completedRecording() => DvrRecording(
  uuid: 'rec-1',
  title: 'Evening Movie',
  subtitle: 'Director Cut',
  status: DvrRecordingStatus.completed,
  channelId: 101,
  channelName: 'BBC One',
  scheduledStart: DateTime.utc(2026, 6, 25, 18),
  scheduledEnd: DateTime.utc(2026, 6, 25, 20),
  actualStart: DateTime.utc(2026, 6, 25, 18, 1),
  actualEnd: DateTime.utc(2026, 6, 25, 20, 2),
  durationSeconds: 7200,
  fileSizeBytes: 1234567890,
  seasonNumber: 2,
  episodeNumber: 5,
  streamUrl: 'https://stream.example/recordings/rec-1.mp4',
  edlUrl: 'https://stream.example/recordings/rec-1.edl',
);

DvrRecording _recordingNow() => DvrRecording(
  uuid: 'rec-2',
  title: 'Live News',
  status: DvrRecordingStatus.recording,
  channelId: 102,
  channelName: 'News 24',
  scheduledStart: DateTime.utc(2026, 6, 25, 21),
  scheduledEnd: DateTime.utc(2026, 6, 25, 22),
  actualStart: DateTime.utc(2026, 6, 25, 21, 1),
  durationSeconds: 3600,
  liveUrl: 'https://stream.example/recordings/rec-2/live.m3u8',
);

DvrRecording _scheduledRecording() => DvrRecording(
  uuid: 'rec-3',
  title: 'Upcoming Show',
  status: DvrRecordingStatus.scheduled,
  channelId: 103,
  channelName: 'CNN',
  scheduledStart: DateTime.utc(2026, 7, 1, 19),
  scheduledEnd: DateTime.utc(2026, 7, 1, 20),
);

DvrRecording _failedRecording() => DvrRecording(
  uuid: 'rec-4',
  title: 'Broken Show',
  status: DvrRecordingStatus.failed,
  channelId: 104,
  channelName: 'HBO',
  scheduledStart: DateTime.utc(2026, 6, 20, 19),
  scheduledEnd: DateTime.utc(2026, 6, 20, 20),
);

DvrRecording _cancelledRecording() => DvrRecording(
  uuid: 'rec-5',
  title: 'Skipped Show',
  status: DvrRecordingStatus.cancelled,
  channelId: 105,
  channelName: 'FX',
  scheduledStart: DateTime.utc(2026, 6, 20, 21),
  scheduledEnd: DateTime.utc(2026, 6, 20, 22),
);

DvrSeriesRule _seriesRule() => const DvrSeriesRule(
  id: 7,
  channelId: 8,
  channelName: 'Channel Eight',
  seriesTitle: 'Test Series Alpha',
  matchMode: DvrMatchMode.contains,
  seriesMode: DvrSeriesMode.all,
  enabled: true,
  enableComskip: false,
  recordingCount: 3,
);

DvrSeriesRule _secondSeriesRule() => const DvrSeriesRule(
  id: 12,
  channelId: 9,
  channelName: 'Channel Nine',
  seriesTitle: 'Test Series Beta',
  matchMode: DvrMatchMode.contains,
  seriesMode: DvrSeriesMode.all,
  enabled: true,
  enableComskip: false,
  recordingCount: 1,
);
