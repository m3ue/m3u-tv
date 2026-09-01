import 'package:flutter/widgets.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Bridges AppShell navigation callbacks to go_router branch builders.
/// AppShell provides this in its build tree so nested route builders can call
/// [ContentActions.of] without changing feature screen constructor signatures.
class ContentActions extends InheritedWidget {
  const ContentActions({
    super.key,
    required this.appState,
    required this.onOpenPlayer,
    required this.onChannelSelect,
    required this.onCatchupSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    required this.onSidebarActivate,
    required this.onRecordSeries,
    required this.onDeleteSeriesRule,
    this.onScheduleEpisode,
    this.onScheduleEpisodes,
    this.onMarkEpisodeWatched,
    required this.buildTabScreen,
    required super.child,
  });

  final AppStateController appState;

  /// Opens the player overlay directly (used by detail screens' play buttons).
  final void Function(PlayerArgs) onOpenPlayer;

  /// Navigates to VOD details route (pushes `/vod/details/:id`).
  final void Function(VodItem) onVodSelect;

  final void Function(Channel) onChannelSelect;
  final void Function(Channel, EpgProgram) onCatchupSelect;

  /// Navigates to series details route (pushes `/series/details/:id`).
  final void Function(Series) onSeriesSelect;

  final void Function(Progress) onProgressSelect;
  final VoidCallback onSidebarActivate;

  /// Creates a persistent DVR series rule for the given show. Wired by
  /// AppShell against `XtreamService.createDvrSeriesRule`; the
  /// `ShowDetailScreen` route passes it through to the screen so the Record
  /// Series button has a target. Returns the outcome so the screen can
  /// distinguish created / duplicate / failed.
  ///
  /// The options params ([DvrSeriesRuleOptions]) are threaded through from the
  /// configure sheet (B5); nulls mean "use server default".
  final Future<CreateDvrSeriesRuleOutcome> Function({
    int? channelId,
    required String title,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  })?
  onRecordSeries;

  /// Deletes a DVR series rule. Wired by AppShell against
  /// `XtreamService.deleteDvrSeriesRule`; the `ShowDetailScreen` route passes
  /// it through to the screen so the rule-active state can offer a delete
  /// affordance without a separate round-trip to fetch the rule id.
  final Future<void> Function(DvrSeriesRule rule)? onDeleteSeriesRule;

  /// Schedules a single DVR airing for one `EpgShowEpisode`. Wired by
  /// AppShell against `AppStateController.scheduleDvrAiring`; the
  /// `ShowDetailScreen` route passes it through so each episode row can
  /// offer a one-shot Record affordance (unlike [onRecordSeries], no
  /// persistent rule is created). Returns the matching recording if the
  /// post-schedule refresh surfaced one, else null.
  final Future<DvrRecording?> Function(EpgShowEpisode)? onScheduleEpisode;

  /// Schedules a batch of DVR airings for the user-selected episodes in
  /// selection mode. Wired by AppShell against
  /// `AppStateController.scheduleDvrAirings`. Null means the selection-mode
  /// entry affordance is hidden on the route (same null-hides-affordance
  /// convention as [onScheduleEpisode]).
  final Future<List<DvrAiringScheduleResult>> Function(
    List<EpgShowEpisode>,
  )?
  onScheduleEpisodes;

  /// Marks a single series episode watched or unwatched for the active viewer.
  /// Wired by AppShell against `AppStateController` (server `update_progress` +
  /// local resume store). The series detail route passes it through so the
  /// long-press affordances on the season picker and episode cards have a
  /// target. Null hides those affordances (non-Xtream sources / no viewer).
  /// Resolves to whether the server write landed (local state updates either
  /// way) so a bulk "mark season" can report partial failure.
  final Future<bool> Function({
    required int streamId,
    required int seriesId,
    required int seasonNumber,
    required int episodeNumber,
    int? durationSeconds,
    String? seriesName,
    String? episodeTitle,
    required bool watched,
  })?
  onMarkEpisodeWatched;

  /// Builds the full tab screen for the given routeName.
  /// Provided by AppShell so go_router branch builders don't need to import
  /// every feature screen directly.
  final Widget Function(String routeName) buildTabScreen;

  XtreamService get xtreamService => appState.xtreamService;
  EpgService get epgService => appState.epgService;
  List<Progress> get progressList => appState.progressList;

  static ContentActions of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<ContentActions>();
    assert(result != null, 'ContentActions not found in widget tree');
    return result!;
  }

  static ContentActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentActions>();

  @override
  bool updateShouldNotify(ContentActions oldWidget) =>
      // Only the appState instance ever changes. All callbacks are stable
      // method tearoffs from AppShellState — comparing them would always return
      // false (equal), but if any were closures they'd always return true and
      // flood every feature screen with unnecessary rebuilds on each tab switch.
      appState != oldWidget.appState;
}
