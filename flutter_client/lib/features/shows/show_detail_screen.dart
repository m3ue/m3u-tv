import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/dvr/dvr_series_rule_options_screen.dart';
import 'package:m3u_tv/features/epg/epg_recording_index.dart';
import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
import 'package:m3u_tv/shared/dvr_schedule_feedback.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/leading_tile.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Detail screen for a single EPG show. Receives the [EpgShow] as the route
/// `extra` from `RouteNames.showDetailsFor`. The "Record Series" button
/// delegates to [onRecordSeries] (wired by AppShell against
/// `XtreamService.createDvrSeriesRule`). When an existing rule is detected
/// (`show.hasSeriesRule` from A4, refreshed through `dvrSeriesRulesProvider`),
/// the screen flips to a "Series rule active" state that exposes a delete
/// affordance routed through [onDeleteSeriesRule] + the existing
/// `showDeleteSeriesRuleDialog`.
class ShowDetailScreen extends ConsumerStatefulWidget {
  const ShowDetailScreen({
    super.key,
    required this.show,
    this.onRecordSeries,
    this.onDeleteSeriesRule,
    this.onScheduleEpisode,
    this.onScheduleEpisodes,
  });

  final EpgShow show;

  /// Returns the create outcome so the UI can distinguish created /
  /// duplicate / failed rather than collapsing every non-success into a
  /// generic failure SnackBar. Wired by AppShell against
  /// `XtreamService.createDvrSeriesRule`. Options params are threaded through
  /// from the B5 configure sheet; null means "use server default".
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

  /// Deletes an existing DVR series rule and refreshes the local cache.
  /// Wired by AppShell against `XtreamService.deleteDvrSeriesRule`. Only
  /// invoked when [ShowDetailScreen] detects an existing rule for this show.
  final Future<void> Function(DvrSeriesRule rule)? onDeleteSeriesRule;

  /// Schedules a single DVR airing for one episode row. Wired by AppShell
  /// against `AppStateController.scheduleDvrAiring`. Null hides the per-row
  /// Record affordance (screen still works unwired, same convention as
  /// [onRecordSeries]).
  final Future<DvrRecording?> Function(EpgShowEpisode episode)?
  onScheduleEpisode;

  /// Schedules a batch of DVR airings for the user-selected episodes in
  /// selection mode. Wired by AppShell against
  /// `AppStateController.scheduleDvrAirings`. Null means selection mode is
  /// unavailable entirely (no long-press affordance, no action bar), since a
  /// mode with no exit would trap the user.
  final Future<List<DvrAiringScheduleResult>> Function(
    List<EpgShowEpisode>,
  )?
  onScheduleEpisodes;

  @override
  ConsumerState<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen> {
  bool _isSubmitting = false;

  /// In-flight per-row schedule requests, keyed by
  /// `channelId|startTime` so same-title airings on different channels (or
  /// the same channel at different times) are tracked independently. Guards
  /// against double-tap double-scheduling while the request is in flight.
  final Set<String> _submittingEpisodeKeys = {};

  /// True when the user has long-pressed an episode row to enter multi-
  /// select mode. While true, the per-row Record button is hidden, the
  /// episode list is tappable (toggle selection), and the action bar shows
  /// "Record (N)" + "Cancel".
  bool _selectionMode = false;

  /// Selected episode keys in selection mode. Uses the same
  /// `channelId|startTime` key as [_submittingEpisodeKeys] / [_episodeRecordKey]
  /// so the two sets stay disjoint in their semantics.
  final Set<String> _selectedEpisodeKeys = {};

  /// True while a batch schedule request is in flight. Guards "Record (N)"
  /// against a double-tap firing two concurrent batch submissions of the
  /// same selection (mirrors [_submittingEpisodeKeys]'s per-row guard).
  bool _batchSubmitting = false;

  Future<void> _scheduleEpisode(EpgShowEpisode episode) async {
    final handler = widget.onScheduleEpisode;
    if (handler == null) return;
    final episodeKey = _episodeRecordKey(episode);
    if (_submittingEpisodeKeys.contains(episodeKey)) return;
    setState(() => _submittingEpisodeKeys.add(episodeKey));
    try {
      await scheduleDvrWithFeedback(
        context,
        schedule: () => handler(episode),
        title: episode.displayTitle,
      );
    } finally {
      if (mounted) {
        setState(() => _submittingEpisodeKeys.remove(episodeKey));
      }
    }
  }

  /// Enters selection mode with [episode] as the initially-selected row.
  /// Caller guards `onScheduleEpisodes != null` (the long-press affordance is
  /// wired conditionally so this method is never called when the handler is
  /// missing, but the guard is defensive in case the entry point changes).
  void _enterSelectionMode(EpgShowEpisode episode) {
    if (widget.onScheduleEpisodes == null) return;
    setState(() {
      _selectionMode = true;
      _selectedEpisodeKeys
        ..clear()
        ..add(_episodeRecordKey(episode));
    });
  }

  /// Toggles [episode] in the current selection. Caller is responsible for
  /// wiring this only when the row is selectable (i.e. not
  /// already-scheduled).
  void _toggleSelection(EpgShowEpisode episode) {
    final key = _episodeRecordKey(episode);
    setState(() {
      if (!_selectedEpisodeKeys.add(key)) {
        _selectedEpisodeKeys.remove(key);
      }
    });
  }

  /// Exits selection mode and clears the selection. Called by the Cancel
  /// button and by [_scheduleSelected] after the batch handler completes.
  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedEpisodeKeys.clear();
    });
  }

  /// Runs the batch schedule handler for the user's selected episodes, then
  /// exits selection mode and surfaces a single summary SnackBar.
  ///
  /// Re-entrancy is guarded by [_batchSubmitting] (mirrors
  /// [_submittingEpisodeKeys] for the single-row path) so a double-tap on
  /// "Record (N)" can't fire two concurrent batches for the same selection.
  /// Selected episodes that became already-scheduled since the user picked
  /// them (e.g. scheduled from another device, or by a series rule, while
  /// selection mode was open) are dropped before submitting rather than
  /// resubmitted.
  Future<void> _scheduleSelected() async {
    final handler = widget.onScheduleEpisodes;
    if (handler == null || _selectedEpisodeKeys.isEmpty || _batchSubmitting) {
      return;
    }
    final recordingIndex = EpgRecordingIndex.fromRecordings(
      ref.read(dvrRecordingsProvider),
    );
    final selectedEpisodes = [
      for (final episode in widget.show.recentEpisodes)
        if (_selectedEpisodeKeys.contains(_episodeRecordKey(episode)) &&
            !_isAlreadyScheduled(episode, recordingIndex))
          episode,
    ];
    if (selectedEpisodes.isEmpty) {
      _exitSelectionMode();
      return;
    }

    setState(() => _batchSubmitting = true);
    try {
      await scheduleDvrWithFeedback<List<DvrAiringScheduleResult>>(
        context,
        schedule: () => handler(selectedEpisodes),
        successMessage: (results, l10n) {
          final scheduled = results.where((r) => r.success).length;
          final failed = results.length - scheduled;
          final failureTitles = [
            for (final r in results)
              if (!r.success) r.episode.displayTitle,
          ];
          return _buildBatchSummary(l10n, scheduled, failed, failureTitles);
        },
      );
    } finally {
      if (mounted) {
        setState(() => _batchSubmitting = false);
        _exitSelectionMode();
      }
    }
  }

  /// Builds the single summary line for the post-batch SnackBar.
  ///
  /// Per the plan's judgment call (state in Worker status), failed-episode
  /// titles are listed inline only when [failed] is between 1 and 3
  /// inclusive (beyond that the line would overrun the SnackBar width).
  /// failed == 0 collapses to the summary alone ("All succeeded.").
  String _buildBatchSummary(
    AppLocalizations l10n,
    int scheduled,
    int failed,
    List<String> failureTitles,
  ) {
    final summary = l10n.showBatchScheduleSummary(scheduled, failed);
    if (failed > 0 && failed <= 3) {
      return '$summary\n${l10n.showBatchScheduleFailures(failureTitles.join(', '))}';
    }
    return summary;
  }

  DvrSeriesRule? _findExistingRule(List<DvrSeriesRule> rules) {
    final ruleId = widget.show.seriesRuleId;
    if (ruleId != null) {
      for (final rule in rules) {
        if (rule.id == ruleId) return rule;
      }
    }
    final normalized = widget.show.normalizedTitle.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final rule in rules) {
      if (rule.seriesTitle.trim().toLowerCase() == normalized) return rule;
    }
    return null;
  }

  Future<void> _recordSeries({
    int? channelId,
    DvrMatchMode? matchMode,
    DvrSeriesMode? seriesMode,
    int? keepLast,
    int? priority,
    int? startEarlySeconds,
    int? endLateSeconds,
  }) async {
    final handler = widget.onRecordSeries;
    if (handler == null) return;
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      final outcome = await handler(
        channelId: channelId,
        title: widget.show.displayTitle,
        matchMode: matchMode,
        seriesMode: seriesMode,
        keepLast: keepLast,
        priority: priority,
        startEarlySeconds: startEarlySeconds,
        endLateSeconds: endLateSeconds,
      );
      if (!mounted) return;
      final message = switch (outcome) {
        CreateDvrSeriesRuleOutcome.created => l10n.showRecordSeriesSuccess(
          widget.show.displayTitle,
        ),
        CreateDvrSeriesRuleOutcome.duplicate => l10n.showRecordSeriesDuplicate(
          widget.show.displayTitle,
        ),
        CreateDvrSeriesRuleOutcome.failed => l10n.showRecordSeriesFailed(
          widget.show.displayTitle,
        ),
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.showRecordSeriesFailed('$error'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openOptionsScreen() async {
    final options = await openDvrSeriesRuleOptions(context, show: widget.show);
    if (options == null || !mounted) return;
    // channelId is null for "any channel" — pass through so the key is
    // omitted on the request (matches the sheet's "any channel" selection).
    await _recordSeries(
      channelId: options.channelId,
      matchMode: options.matchMode,
      seriesMode: options.seriesMode,
      keepLast: options.keepLast,
      priority: options.priority,
      startEarlySeconds: options.startEarlySeconds,
      endLateSeconds: options.endLateSeconds,
    );
  }

  Future<void> _deleteSeriesRule(DvrSeriesRule rule) async {
    final handler = widget.onDeleteSeriesRule;
    if (handler == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    try {
      await handler(rule);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dvrDeleteSeriesRuleSuccess)),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.dvrDeleteSeriesRuleFailed),
        ),
      );
    }
  }

  Future<void> _confirmAndDelete(DvrSeriesRule rule) async {
    final confirmed = await showDeleteSeriesRuleDialog(context, rule: rule);
    if (confirmed != true) return;
    if (!mounted) return;
    await _deleteSeriesRule(rule);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final localized = Localizations.localeOf(context).toLanguageTag();
    final show = widget.show;
    final channelNames = show.channels
        .map((c) => c.channelName)
        .toList(
          growable: false,
        );
    final channelsLabel = channelNames.join(' · ');
    final nextAiring = show.nextAiringAt;
    final nextAiringLabel = nextAiring == null
        ? l10n.showAiringNone
        : '${l10n.showAiringNext} ${DateFormat.yMMMd(localized).add_jm().format(nextAiring.toLocal())}';

    // Watching so a delete from the DVR screen (or another device) flips
    // the toggle state without a full route re-push.
    final rules = ref.watch(dvrSeriesRulesProvider);
    final existingRule = show.hasSeriesRule ? _findExistingRule(rules) : null;

    // Watching so a freshly-scheduled airing (single tap or batch) flips
    // the per-row "Scheduled" badge without a full route re-push.
    final recordings = ref.watch(dvrRecordingsProvider);
    final recordingIndex = EpgRecordingIndex.fromRecordings(recordings);
    final scale = FontSizeScope.scaleOf(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.showDetailTitle),
        automaticallyImplyLeading: false,
        // AppBar's default toolbarHeight is fixed and unscaled - without
        // scaling it too, AppIconButton's larger footprint gets squeezed
        // into that fixed height (see item_detail_scaffold.dart).
        toolbarHeight: kToolbarHeight * scale,
        leadingWidth: 56 * scale,
        leading: Padding(
          padding: EdgeInsets.all(8 * scale),
          child: AppIconButton(
            icon: Icons.arrow_back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => context.pop(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              title: show.displayTitle,
              channelsLabel: channelsLabel,
              channelsCount: show.channelCount,
              episodeCount: show.episodeCount,
              hasDvr: widget.onRecordSeries != null,
              isSubmitting: _isSubmitting,
              hasRule: existingRule != null,
              ruleLabel: l10n.showSeriesRuleActive,
              deleteTooltip: l10n.showDeleteRule,
              // Hide the Record Series controls while in selection mode so
              // they don't compete for focus with the episode-list action bar.
              hideActions: _selectionMode,
              onRecordSeries: () => _recordSeries(
                channelId: nextAiringChannelId(widget.show),
              ),
              onOpenOptions: _openOptionsScreen,
              onDeleteRule: existingRule == null
                  ? null
                  : () => _confirmAndDelete(existingRule),
            ),
            const SizedBox(height: MediaBrowsingMetrics.itemGap),
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: MediaBrowsingMetrics.chipGap,
              ),
              child: Text(
                nextAiringLabel,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            const SizedBox(height: MediaBrowsingMetrics.itemGap),
            if (_selectionMode) ...[
              _SelectionActionsBar(
                selectedCount: _selectedEpisodeKeys.length,
                onRecord: _selectedEpisodeKeys.isEmpty || _batchSubmitting
                    ? null
                    : _scheduleSelected,
                onCancel: _exitSelectionMode,
              ),
              const SizedBox(height: MediaBrowsingMetrics.itemGap),
            ],
            if (show.recentEpisodes.isEmpty)
              Center(
                child: Text(
                  l10n.showAiringNone,
                  style: theme.textTheme.bodyLarge,
                ),
              )
            else
              ...show.recentEpisodes.map(
                (episode) {
                  final alreadyScheduled = _isAlreadyScheduled(
                    episode,
                    recordingIndex,
                  );
                  final episodeKey = _episodeRecordKey(episode);
                  // Matches the single-row `canSchedule` gate in
                  // _EpisodeRowState: an airing that has already ended can't
                  // be recorded, in batch mode any more than single-row mode.
                  final rowSelectable =
                      !alreadyScheduled &&
                      episode.endTime.isAfter(DateTime.now());
                  final toggleSelection = _selectionMode && rowSelectable
                      ? () => _toggleSelection(episode)
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: MediaBrowsingMetrics.itemGap,
                    ),
                    child: _EpisodeRow(
                      episode: episode,
                      localeTag: localized,
                      alreadyScheduled: alreadyScheduled,
                      selectionMode: _selectionMode,
                      selected: _selectedEpisodeKeys.contains(episodeKey),
                      // Long-press: enter mode (normal mode) or toggle (in
                      // mode). Only available when selection mode is
                      // reachable AND this row is selectable.
                      onLongTap:
                          (widget.onScheduleEpisodes != null &&
                              !_selectionMode &&
                              rowSelectable)
                          ? () => _enterSelectionMode(episode)
                          : toggleSelection,
                      // Tap: only meaningful in selection mode (toggle).
                      onTap: toggleSelection,
                      onScheduleEpisode:
                          !_selectionMode &&
                              widget.onScheduleEpisode != null &&
                              rowSelectable
                          ? _scheduleEpisode
                          : null,
                      isScheduling: _submittingEpisodeKeys.contains(episodeKey),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.channelsLabel,
    required this.channelsCount,
    required this.episodeCount,
    required this.hasDvr,
    required this.isSubmitting,
    required this.hasRule,
    required this.ruleLabel,
    required this.deleteTooltip,
    required this.onRecordSeries,
    required this.onOpenOptions,
    required this.onDeleteRule,
    this.hideActions = false,
  });

  final String title;
  final String channelsLabel;
  final int channelsCount;
  final int episodeCount;
  final bool hasDvr;
  final bool isSubmitting;
  final bool hasRule;
  final String ruleLabel;
  final String deleteTooltip;
  final VoidCallback onRecordSeries;
  final VoidCallback onOpenOptions;
  final VoidCallback? onDeleteRule;

  /// When true, suppresses the trailing action area entirely so it doesn't
  /// compete for focus with the episode-list selection-mode action bar.
  final bool hideActions;

  // Below this width the title + action buttons no longer fit on one row
  // (on a phone, forcing them into a Row starves the title's Expanded column
  // down to a sliver, wrapping every word onto its own line).
  static const double _narrowBreakpoint = 420;

  Widget? _buildActions(AppLocalizations l10n) {
    if (hideActions) return null;
    if (hasRule) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          AppBadge(label: ruleLabel),
          if (onDeleteRule != null)
            AppIconButton(
              icon: Icons.delete_outline,
              tooltip: deleteTooltip,
              variant: AppButtonVariant.destructive,
              onPressed: onDeleteRule,
            ),
        ],
      );
    }
    if (hasDvr) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppButton(
            label: l10n.showRecordSeries,
            icon: Icons.fiber_manual_record,
            variant: AppButtonVariant.primaryInverted,
            autofocus: true,
            loading: isSubmitting,
            onPressed: onRecordSeries,
          ),
          AppButton(
            label: l10n.dvrSeriesOptions,
            onPressed: isSubmitting ? null : onOpenOptions,
          ),
        ],
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.showChannelCount(channelsCount),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.showEpisodesCount(episodeCount),
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
    final actions = _buildActions(l10n);

    return Card(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _narrowBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleColumn,
                  if (actions != null) ...[
                    const SizedBox(height: MediaBrowsingMetrics.contentPadding),
                    actions,
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleColumn),
                if (actions != null) ...[
                  const SizedBox(width: MediaBrowsingMetrics.contentPadding),
                  actions,
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({
    required this.episode,
    required this.localeTag,
    this.alreadyScheduled = false,
    this.selectionMode = false,
    this.selected = false,
    this.onScheduleEpisode,
    this.onTap,
    this.onLongTap,
    this.isScheduling = false,
  });

  final EpgShowEpisode episode;
  final String localeTag;

  /// True when an existing DVR recording already covers this airing (by
  /// channel + time-window overlap). Renders a "Scheduled" badge on the
  /// row and excludes it from selection in batch mode.
  final bool alreadyScheduled;

  /// True when the screen is in multi-select mode. Replaces the per-row
  /// Record `AppIconButton` with a checkbox indicator via [LeadingTile]'s
  /// `selectMode` prop.
  final bool selectionMode;

  /// True when this row is among the user's selected episodes. Only
  /// meaningful when [selectionMode] is true.
  final bool selected;

  /// One-shot Record action for this single airing. Null hides the
  /// affordance (screen not wired); airings already over hide it too.
  final Future<void> Function(EpgShowEpisode episode)? onScheduleEpisode;

  /// Row tap handler. In selection mode, toggles this row's selection. In
  /// normal mode, null (rows aren't tappable; the Record icon is).
  final VoidCallback? onTap;

  /// Row long-press handler. In normal mode, enters selection mode (with
  /// this row as the seed). In selection mode, also toggles this row.
  final VoidCallback? onLongTap;

  /// True while this row's schedule request is in flight (disables the
  /// Record button so a double-tap can't schedule the same airing twice).
  final bool isScheduling;

  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  Timer? _endTimer;

  @override
  void initState() {
    super.initState();
    _scheduleEndTimer();
  }

  @override
  void didUpdateWidget(_EpisodeRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.episode.endTime != widget.episode.endTime) {
      _scheduleEndTimer();
    }
  }

  void _scheduleEndTimer() {
    _endTimer?.cancel();
    final remaining = widget.episode.endTime.difference(DateTime.now());
    if (remaining.isNegative) return;
    // Rebuilds once the airing ends so canSchedule (and the Record button)
    // stops reflecting a now-stale "still airing" state without requiring
    // the user to trigger some unrelated rebuild first.
    _endTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _endTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final localeTag = widget.localeTag;
    final onScheduleEpisode = widget.onScheduleEpisode;
    final isScheduling = widget.isScheduling;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final timeLabel = DateFormat.yMMMd(
      localeTag,
    ).add_jm().format(episode.startTime.toLocal());
    // Don't offer to record an airing that has already ended (same check
    // as the live-tv context menu's `pressedProgram.end.isAfter(now)`).
    final canSchedule =
        onScheduleEpisode != null && episode.endTime.isAfter(DateTime.now());

    return DpadInkWell(
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      color: theme.colorScheme.surfaceContainerHigh,
      onTap: widget.onTap,
      onLongTap: widget.onLongTap,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: Row(
          children: [
            LeadingTile(
              icon: Icons.play_arrow,
              tileColor: theme.colorScheme.tertiary,
              selectMode: widget.selectionMode,
              selected: widget.selected,
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        TextSpan(text: episode.channelName),
                        const TextSpan(text: ' · '),
                        TextSpan(text: timeLabel),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (widget.alreadyScheduled) ...[
              const SizedBox(width: MediaBrowsingMetrics.chipGap),
              AppBadge(label: l10n.showScheduled),
            ],
            if (!widget.selectionMode && canSchedule) ...[
              const SizedBox(width: MediaBrowsingMetrics.chipGap),
              // Direct AppIconButton rather than RowActionMenu: record is the
              // only action on episode rows, so the "more" overflow that
              // RowActionMenu exists to provide is semantically empty here;
              // using it would force a 2-tap UX (tap more_vert -> tap record)
              // for what is currently a single tap. AppIconButton already
              // handles D-pad focus and touch adaptation itself, so there's
              // no missing touch/TV behavior for the wrapper to add. If a
              // future change adds a second per-row action (e.g. cancel a
              // scheduled recording from the episode row), revisit and
              // route both through RowActionMenu at that point.
              AppIconButton(
                icon: Icons.fiber_manual_record,
                tooltip: l10n.liveTvRecord,
                onPressed: isScheduling
                    ? null
                    : () => onScheduleEpisode(episode),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Action bar shown above the episode list while the user is in multi-
/// select mode. Provides "Record (N)" (disabled at N=0) and "Cancel". Both
/// buttons are D-pad focusable so the user can navigate to the bar with
/// up-arrow from the episode list and back with down-arrow.
class _SelectionActionsBar extends StatelessWidget {
  const _SelectionActionsBar({
    required this.selectedCount,
    required this.onRecord,
    required this.onCancel,
  });

  final int selectedCount;
  final VoidCallback? onRecord;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: l10n.showBatchRecord(selectedCount),
            icon: Icons.fiber_manual_record,
            variant: AppButtonVariant.primaryInverted,
            onPressed: onRecord,
          ),
          const SizedBox(width: MediaBrowsingMetrics.contentPadding),
          AppButton(label: l10n.cancel, onPressed: onCancel),
        ],
      ),
    );
  }
}

/// Unique per-airing key for the in-flight guard: `channelId|startTime`
/// stays distinct even when the same title airs on another channel or at a
/// different time.
String _episodeRecordKey(EpgShowEpisode episode) =>
    '${episode.channelId}|${episode.startTime.toIso8601String()}';

/// True when [episode] is already covered by an existing DVR recording.
///
/// Delegates to [EpgRecordingIndex], which the EPG timeline grid also uses
/// for the same "does this programme have a recording" question: coverage-
/// based overlap (not naive boundary overlap, which false-matches adjacent
/// back-to-back airings on the same channel) plus channel-bucketed lookup
/// and terminal-status filtering.
bool _isAlreadyScheduled(EpgShowEpisode episode, EpgRecordingIndex index) {
  return index.stateFor(
        channelId: episode.channelId,
        programStart: episode.startTime,
        programEnd: episode.endTime,
      ) !=
      EpgRecordingState.none;
}
