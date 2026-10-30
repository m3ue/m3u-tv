import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// DVR and show-search operations the shell hands to feature screens as
/// callbacks (series rules, scheduling Shows-search airings, cancel-and-
/// delete). They compose `AppStateController` and `XtreamService` calls and
/// need no widget context, so they live here rather than in `AppShellState`.
class DvrActions {
  const DvrActions(this.appState);

  final AppStateController appState;

  /// Schedules a single DVR airing for one Shows-search episode. No
  /// SnackBar here: the screen owns success/failure feedback (mirroring
  /// how the live-tv `_scheduleDvr` keeps it out of the scheduling call).
  Future<DvrRecording?> scheduleAiring(EpgShowEpisode episode) {
    return appState.scheduleDvrAiring(
      channelId: episode.channelId,
      title: episode.displayTitle,
      startTime: episode.startTime,
      endTime: episode.endTime,
    );
  }

  /// Schedules a batch of DVR airings for one Shows-search selection.
  /// Per-item failures land inside the returned list (the screen turns that
  /// into a single summary SnackBar), no per-item SnackBars here, mirroring
  /// the single-item `scheduleAiring`'s "screen owns feedback" rule.
  Future<List<DvrAiringScheduleResult>> scheduleAirings(
    List<EpgShowEpisode> episodes,
  ) {
    return appState.scheduleDvrAirings(episodes);
  }

  /// Calls the foundation-agent-owned `XtreamService.createDvrSeriesRule`
  /// and refreshes the cached series rules list so the DVR screen's new
  /// "Series Rules" section reflects the addition immediately.
  ///
  /// Returns a [CreateDvrSeriesRuleOutcome] so the UI can tell
  /// "rule created" / "duplicate of existing rule" / "failed" apart and
  /// show the right SnackBar without losing the A3-409 distinction that
  /// `XtreamService.createDvrSeriesRule` throws as
  /// `DvrSeriesRuleExistsException`. The `on Object { return false; }`
  /// blanket from earlier releases would have collapsed the duplicate case
  /// into a generic failure - B2 surfaces it instead.
  Future<CreateDvrSeriesRuleOutcome> createSeriesRule({
    int? channelId,
    required String title,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  }) async {
    try {
      final id = await appState.xtreamService.createDvrSeriesRule(
        channelId: channelId,
        title: title,
        matchMode: matchMode,
        seriesMode: seriesMode,
        keepLast: keepLast,
        priority: priority,
        startEarlySeconds: startEarlySeconds,
        endLateSeconds: endLateSeconds,
      );
      await appState.refreshDvrSeriesRules();
      // The rule's `created` hook may have already matched and scheduled a
      // recording server-side (see AppStateController.refreshDvrRecordings
      // doc comment) - refresh so it shows up in the Recordings tab without
      // waiting for the next full app reload.
      unawaited(appState.refreshDvrRecordings());
      return id == 0
          ? CreateDvrSeriesRuleOutcome.failed
          : CreateDvrSeriesRuleOutcome.created;
    } on DvrSeriesRuleExistsException {
      try {
        await appState.refreshDvrSeriesRules();
      } on Object catch (error, stackTrace) {
        debugPrint('DVR: refresh after duplicate create failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return CreateDvrSeriesRuleOutcome.duplicate;
    } on Object catch (error, stackTrace) {
      debugPrint('DVR: create series rule failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return CreateDvrSeriesRuleOutcome.failed;
    }
  }

  /// Deletes a DVR series rule and refreshes the cached list.
  Future<void> deleteSeriesRule(DvrSeriesRule rule) async {
    await appState.xtreamService.deleteDvrSeriesRule(rule.id);
    await appState.refreshDvrSeriesRules();
  }

  /// Updates an existing DVR series rule in place (never delete-and-recreate —
  /// deleting cascades to the rule's recordings and would destroy history) and
  /// refreshes the cached list. `updateDvrSeriesRule` applies only the fields
  /// the sheet returned; absent fields keep their current server values.
  Future<void> updateSeriesRule(
    DvrSeriesRule rule,
    DvrSeriesRuleOptions options,
  ) async {
    await appState.xtreamService.updateDvrSeriesRule(
      ruleId: rule.id,
      // Only send a channel when the user actually changed it, so an edit to
      // padding or priority can never move the rule's channel scope.
      channel: DvrRuleChannelChange.between(
        current: rule.channelId,
        selected: options.channelId,
      ),
      matchMode: options.matchMode,
      seriesMode: options.seriesMode,
      keepLast: options.keepLast,
      priority: options.priority,
      startEarlySeconds: options.startEarlySeconds,
      endLateSeconds: options.endLateSeconds,
    );
    await appState.refreshDvrSeriesRules();
    unawaited(appState.refreshDvrRecordings());
  }

  /// Proxies the Shows screen's search through the foundation-agent-owned
  /// `XtreamService.searchEpgShows`.
  Future<List<EpgShow>> searchEpgShows(String query) {
    return appState.xtreamService.searchEpgShows(query);
  }

  /// Stops a scheduled or in-progress recording and deletes the row from the
  /// editor - the "Delete recording" choice on the Recordings screen's stop
  /// dialog (see DvrRecordingsScreen._confirmCancel). m3u-editor's
  /// `cancel_dvr_recording` only marks the recording `cancelled` (a stop +
  /// history-keep operation), so this chains a follow-up `delete_dvr_recording`
  /// once the row is in a deletable state. The "Keep recording" choice instead
  /// calls `AppStateController.cancelDvrRecording` directly and stops here.
  ///
  /// If the cancel succeeds but the delete fails (e.g. transient server
  /// hiccup), the recording is still stopped and stays in the local list with
  /// its Cancelled status - the user can retry Delete from there. The delete
  /// failure is rethrown (not swallowed) so DvrRecordingsScreen's
  /// _runWithFeedback shows the "could not delete" SnackBar instead of a
  /// false "deleted" success message for a recording that's still there.
  Future<void> cancelAndDeleteRecording(String uuid) async {
    await appState.cancelDvrRecording(uuid);
    try {
      await appState.deleteDvrRecording(uuid);
    } on Object catch (error) {
      debugPrint('DVR: post-cancel delete failed: $error');
      rethrow;
    }
  }
}
