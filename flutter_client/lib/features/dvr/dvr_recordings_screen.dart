import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/dvr/dvr_series_rule_options_screen.dart';
import 'package:m3u_tv/features/shows/shows_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

class DvrRecordingsScreen extends StatefulWidget {
  const DvrRecordingsScreen({
    super.key,
    required this.recordings,
    required this.isLoading,
    required this.isConfigured,
    required this.onPlay,
    this.storageInfo,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.onDeleteSeriesRule,
    this.onUpdateSeriesRule,
    this.seriesRules = const <DvrSeriesRule>[],
    this.onSidebarActivate,
    this.onSearchShows,
    this.onOpenShowDetail,
    this.onEnterFullScreenDetail,
    this.onExitFullScreenDetail,
  });

  final List<DvrRecording> recordings;
  final bool isLoading;
  final bool isConfigured;
  final DvrStorageInfo? storageInfo;
  final void Function(PlayerArgs args) onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final Future<void> Function(DvrSeriesRule)? onDeleteSeriesRule;
  final Future<void> Function(DvrSeriesRule rule, DvrSeriesRuleOptions options)?
  onUpdateSeriesRule;
  final List<DvrSeriesRule> seriesRules;
  final VoidCallback? onSidebarActivate;

  /// Wired from AppShell against `XtreamService.searchEpgShows`. Powers the
  /// Shows tab (third DVR tab). Defaults to returning an empty list so
  /// callers in tests / previews can render the screen without a backend.
  final Future<List<EpgShow>> Function(String query)? onSearchShows;

  /// Wired from AppShell to `AppShell._pushDetail(..., fullScreen: true)` so
  /// opening a show from the Shows tab gets the same immersive, nav-hiding
  /// push as VOD/Series/AIOStreams detail. See [ShowsScreen.onShowSelect].
  final void Function(EpgShow show)? onOpenShowDetail;

  /// Wired from AppShell to `AppShell._enterFullScreenDetail`/
  /// `_exitFullScreenDetail`. The Series Rules tab opens the DVR Options
  /// screen via a plain `Navigator.push`, not a go_router route, so it
  /// doesn't get the immersive sidebar/bottom-nav-hiding treatment for
  /// free the way `onOpenShowDetail`'s route push does — these let
  /// `_openEdit` opt into the same state manually for the duration of
  /// that push.
  final VoidCallback? onEnterFullScreenDetail;
  final VoidCallback? onExitFullScreenDetail;

  @override
  State<DvrRecordingsScreen> createState() => _DvrRecordingsScreenState();
}

class _DvrRecordingsScreenState extends State<DvrRecordingsScreen>
    with SingleTickerProviderStateMixin {
  // 0 = Recordings, 1 = Series Rules, 2 = Shows. The Shows tab's search
  // field attaches to [_showsSearchFocus] so we can hand focus to it only
  // when the tab is selected — TabBarView builds every child up front, so
  // a plain autofocus on the field would steal focus from whichever tab
  // the user actually opened on.
  static const int _showsTabIndex = 2;

  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  final FocusNode _showsSearchFocus = FocusNode(debugLabel: 'dvr/shows-search');

  @override
  void initState() {
    super.initState();
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging ||
        _tabController.index != _showsTabIndex) {
      return;
    }
    _showsSearchFocus.requestFocus();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    _showsSearchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!widget.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.dvrRecordingsTitle)),
        body: Center(
          child: Text(
            l10n.dvrNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DpadTabBar(
            controller: _tabController,
            tabs: [
              l10n.dvrRecordingsTitle,
              l10n.dvrSeriesRulesTitle,
              l10n.navShows,
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.pagePadding,
                  ),
                  child: _buildRecordingsTab(context),
                ),
                Padding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.pagePadding,
                  ),
                  child: _buildSeriesRulesTab(context),
                ),
                Padding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.pagePadding,
                  ),
                  child: _buildShowsTab(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingsTab(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.storageInfo != null) ...[
          _DvrStorageSummary(info: widget.storageInfo!),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        Expanded(
          child: widget.isLoading
              ? const Center(child: CircularProgressIndicator())
              : widget.recordings.isEmpty
              ? Center(
                  child: Text(
                    l10n.dvrNoRecordings,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : _RecordingList(
                  recordings: widget.recordings,
                  onPlay: widget.onPlay,
                  onCancelRecording: widget.onCancelRecording,
                  onCancelAndDeleteRecording: widget.onCancelAndDeleteRecording,
                  onDeleteRecording: widget.onDeleteRecording,
                  onSidebarActivate: widget.onSidebarActivate,
                ),
        ),
      ],
    );
  }

  Widget _buildSeriesRulesTab(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (widget.seriesRules.isEmpty) {
      return Center(
        child: Text(
          l10n.dvrSeriesRulesEmpty,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return _SeriesRulesList(
      rules: widget.seriesRules,
      onDelete: widget.onDeleteSeriesRule,
      onUpdate: widget.onUpdateSeriesRule,
      onSidebarActivate: widget.onSidebarActivate,
      onEnterFullScreenDetail: widget.onEnterFullScreenDetail,
      onExitFullScreenDetail: widget.onExitFullScreenDetail,
    );
  }

  Widget _buildShowsTab(BuildContext context) {
    return ShowsScreen(
      onSearch: widget.onSearchShows ?? _emptyShowsSearch,
      searchFocusNode: _showsSearchFocus,
      onSidebarActivate: widget.onSidebarActivate,
      onShowSelect: widget.onOpenShowDetail,
    );
  }
}

Future<List<EpgShow>> _emptyShowsSearch(String query) async => <EpgShow>[];

class _SeriesRulesList extends StatelessWidget {
  const _SeriesRulesList({
    required this.rules,
    this.onDelete,
    this.onUpdate,
    this.onSidebarActivate,
    this.onEnterFullScreenDetail,
    this.onExitFullScreenDetail,
  });

  final List<DvrSeriesRule> rules;
  final Future<void> Function(DvrSeriesRule)? onDelete;
  final Future<void> Function(DvrSeriesRule rule, DvrSeriesRuleOptions options)?
  onUpdate;
  final VoidCallback? onSidebarActivate;
  final VoidCallback? onEnterFullScreenDetail;
  final VoidCallback? onExitFullScreenDetail;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      memoryKey: 'dvr/series-rules',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) onSidebarActivate?.call();
      },
      child: ScrollbarListView(
        itemCount: rules.length,
        itemBuilder: (context, index) {
          final rule = rules[index];
          return Padding(
            padding: const EdgeInsets.only(
              bottom: MediaBrowsingMetrics.itemGap,
            ),
            child: _SeriesRuleCard(
              rule: rule,
              autofocus: index == 0,
              onEdit: onUpdate == null ? null : () => _openEdit(context, rule),
              onDelete: onDelete == null ? null : () => onDelete!(rule),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEdit(BuildContext context, DvrSeriesRule rule) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    onEnterFullScreenDetail?.call();
    final DvrSeriesRuleOptions? options;
    try {
      options = await openDvrSeriesRuleOptions(
        context,
        show: _showForRule(rule),
        initialRule: rule,
      );
    } finally {
      onExitFullScreenDetail?.call();
    }
    if (options == null || !context.mounted) return;
    try {
      await onUpdate!(rule, options);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dvrUpdateSeriesRuleSuccess)),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dvrUpdateSeriesRuleFailed)),
      );
    }
  }

  /// Builds a minimal EpgShow from the rule for the sheet's channel picker.
  /// channelCount 1 keeps the picker hidden; the rule's channel is preserved
  /// via the sheet's initialRule pre-fill, so this show is only a shape
  /// requirement.
  static EpgShow _showForRule(DvrSeriesRule rule) {
    return EpgShow(
      normalizedTitle: rule.seriesTitle,
      displayTitle: rule.seriesTitle,
      channelCount: 1,
      channels: const [],
      episodeCount: 0,
      recentEpisodes: const [],
    );
  }
}

class _SeriesRuleCard extends StatelessWidget {
  const _SeriesRuleCard({
    required this.rule,
    this.onEdit,
    this.onDelete,
    this.autofocus = false,
  });

  final DvrSeriesRule rule;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onEdit,
      // Deleting is a destructive, irreversible action (it cascades to the
      // rule's recordings) — never the primary tap. Plain tap edits the
      // options; delete lives on long-press and the visible delete button,
      // both guarded by the confirm dialog.
      onLongTap: onDelete == null
          ? null
          : () => _confirmDelete(context, rule, onDelete!),
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.fiber_manual_record,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.seriesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (rule.channelName != null)
                    Text(
                      rule.channelName!,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      AppBadge(
                        label: l10n.dvrEpisodeCount(rule.recordingCount),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            if (onDelete != null)
              AppIconButton(
                tooltip: l10n.showDeleteRule,
                icon: Icons.delete,
                variant: AppButtonVariant.destructive,
                onPressed: () => _confirmDelete(context, rule, onDelete!),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DvrSeriesRule rule,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDeleteSeriesRuleDialog(context, rule: rule);
    if (confirmed != true) return;
    if (!context.mounted) return;
    await runDvrActionWithFeedback(
      context,
      action,
      successMessage: l10n.dvrDeleteSeriesRuleSuccess,
      failureMessage: l10n.dvrDeleteSeriesRuleFailed,
    );
  }
}

/// Non-interactive DVR storage meter, shown in the screen header. `info` is
/// only ever passed when the server supports `get_dvr_storage`, so this
/// widget doesn't need its own "unsupported" state — the caller simply
/// omits it. The bar is color-coded by percent used, matching the
/// success/warning/danger thresholds (<75% / 75-89% / >=90%) used by
/// m3u-editor's admin-side DvrStorageOverviewWidget.
class _DvrStorageSummary extends StatelessWidget {
  const _DvrStorageSummary({required this.info});

  final DvrStorageInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final quotaBytes = info.quotaBytes;
    final percentUsed = info.percentUsed;
    final hasQuota = quotaBytes != null && percentUsed != null;

    final usedLabel = _formatBytes(info.usedBytes);
    final summary = quotaBytes == null
        ? l10n.dvrStorageUsedUnlimited(usedLabel)
        : l10n.dvrStorageUsedWithQuota(usedLabel, _formatBytes(quotaBytes));

    final Color barColor;
    if (percentUsed == null) {
      barColor = colorScheme.primary;
    } else if (percentUsed >= 90) {
      barColor = colorScheme.error;
    } else if (percentUsed >= 75) {
      barColor = Colors.amber.shade600;
    } else {
      barColor = colorScheme.primary;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.sd_storage, color: barColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.dvrStorageTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      summary,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (hasQuota)
                Text(
                  '${percentUsed.round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.dvrStorageUnlimited,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l10n.dvrStorageRecordingCount(info.recordingCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasQuota) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (percentUsed / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  final gib = bytes / (1024 * 1024 * 1024);
  if (gib >= 1) return '${gib.toStringAsFixed(1)} GB';
  final mib = bytes / (1024 * 1024);
  return '${mib.toStringAsFixed(0)} MB';
}

class _RecordingList extends ConsumerStatefulWidget {
  const _RecordingList({
    required this.recordings,
    required this.onPlay,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args) onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final VoidCallback? onSidebarActivate;

  @override
  ConsumerState<_RecordingList> createState() => _RecordingListState();
}

class _RecordingListState extends ConsumerState<_RecordingList> {
  final Set<String> _selectedUuids = <String>{};

  bool get _selectMode => _selectedUuids.isNotEmpty;

  void _toggleSelection(String uuid) {
    setState(() {
      if (!_selectedUuids.add(uuid)) _selectedUuids.remove(uuid);
    });
  }

  void _enterSelectMode(String uuid) {
    setState(() {
      _selectedUuids.add(uuid);
    });
  }

  void _exitSelectMode() {
    setState(_selectedUuids.clear);
  }

  void _openRecording(DvrRecording recording) {
    final playbackUrl = recording.playbackUrl;
    if (playbackUrl == null || playbackUrl.isEmpty) return;
    widget.onPlay(
      PlayerArgs(
        streamUrl: playbackUrl,
        title: recording.title,
        type: recording.isInProgress ? 'live' : 'vod',
        metadata: <String, Object?>{
          'dvr_uuid': recording.uuid,
          'dvr_status': recording.status.name,
          if (recording.subtitle != null) 'subtitle': recording.subtitle,
          if (recording.channelName != null)
            'channel_name': recording.channelName,
          if (recording.seasonNumber != null)
            'season_number': recording.seasonNumber,
          if (recording.episodeNumber != null)
            'episode_number': recording.episodeNumber,
          if (recording.edlUrl != null) 'edl_url': recording.edlUrl,
        },
      ),
    );
  }

  Future<void> _confirmStop(DvrRecording recording) async {
    final cancel = widget.onCancelRecording;
    if (cancel == null) return;
    await confirmStopOrDeleteRecording(
      context,
      recording: recording,
      onCancel: cancel,
      onCancelAndDelete: widget.onCancelAndDeleteRecording,
    );
  }

  Future<void> _confirmDeleteSingle(DvrRecording recording) async {
    final delete = widget.onDeleteRecording;
    if (delete == null) return;
    final confirmed = await showDeleteRecordingDialog(context);
    if (confirmed != true) return;
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await runDvrActionWithFeedback(
      context,
      () => delete(recording.uuid),
      successMessage: l10n.dvrDeleteSuccess,
      failureMessage: l10n.dvrDeleteFailed,
    );
  }

  Future<void> _deleteSelected() async {
    final delete = widget.onDeleteRecording;
    if (delete == null) return;
    final selected = widget.recordings
        .where((r) => _selectedUuids.contains(r.uuid))
        .toList();
    for (final recording in selected) {
      await delete(recording.uuid);
    }
    _exitSelectMode();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: DpadRegion(
            memoryKey: 'dvr/recordings',
            horizontalEdge: DpadEdgeBehavior.stop,
            onEdge: (direction) {
              if (direction == TraversalDirection.left) {
                widget.onSidebarActivate?.call();
              }
            },
            child: ScrollbarListView(
              itemCount: widget.recordings.length,
              itemBuilder: (context, index) {
                final recording = widget.recordings[index];
                final selected = _selectedUuids.contains(recording.uuid);
                final canStop =
                    widget.onCancelRecording != null &&
                    (recording.status == DvrRecordingStatus.scheduled ||
                        recording.status == DvrRecordingStatus.recording);
                final canDelete =
                    widget.onDeleteRecording != null &&
                    (recording.status == DvrRecordingStatus.completed ||
                        recording.status == DvrRecordingStatus.failed ||
                        recording.status == DvrRecordingStatus.cancelled);
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: MediaBrowsingMetrics.itemGap,
                  ),
                  child: _RecordingCard(
                    recording: recording,
                    autofocus: index == 0,
                    selectMode: _selectMode,
                    selected: selected,
                    onTap: _selectMode
                        ? () => _toggleSelection(recording.uuid)
                        : recording.isPlayable
                        ? () => _openRecording(recording)
                        : null,
                    onLongTap: () => _enterSelectMode(recording.uuid),
                    onPlay: recording.isPlayable
                        ? () => _openRecording(recording)
                        : null,
                    onStop: canStop ? () => _confirmStop(recording) : null,
                    onDelete: canDelete
                        ? () => _confirmDeleteSingle(recording)
                        : null,
                    onSelect: !_selectMode
                        ? () => _enterSelectMode(recording.uuid)
                        : null,
                  ),
                );
              },
            ),
          ),
        ),
        if (_selectMode)
          _SelectionActionBar(
            count: _selectedUuids.length,
            onExit: _exitSelectMode,
            onDelete: widget.onDeleteRecording != null ? _deleteSelected : null,
          ),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.recording,
    required this.autofocus,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongTap,
    this.onPlay,
    this.onStop,
    this.onDelete,
    this.onSelect,
  });

  final DvrRecording recording;
  final bool autofocus;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  // NOTE(cj): row height is tuned for touch/desktop; scaling to 88 for TV
  // is tracked as follow-up work, not done here.
  static const double _rowHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme);
    final canSelect = onSelect != null;
    final hasMenu =
        onPlay != null || canSelect || onStop != null || onDelete != null;

    return SizedBox(
      height: _rowHeight,
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: DpadInkWell(
                autofocus: autofocus,
                onTap: onTap,
                onLongTap: onLongTap,
                borderRadius: BorderRadius.circular(
                  MediaBrowsingMetrics.cardRadius,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MediaBrowsingMetrics.contentPadding,
                  ),
                  child: Row(
                    children: [
                      _LeadingTile(
                        recording: recording,
                        selected: selected,
                        selectMode: selectMode,
                        tileColor: statusColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recording.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            _MetaLine(
                              recording: recording,
                              statusColor: statusColor,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasMenu)
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Center(
                  child: _OverflowMenu(
                    tooltip: AppLocalizations.of(context).dvrMoreActions,
                    onPlay: onPlay,
                    onStop: onStop,
                    onDelete: onDelete,
                    onSelect: onSelect,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme colorScheme) {
    return switch (recording.status) {
      DvrRecordingStatus.recording => Colors.redAccent,
      DvrRecordingStatus.postProcessing => colorScheme.secondary,
      DvrRecordingStatus.completed => colorScheme.primary,
      DvrRecordingStatus.scheduled => colorScheme.secondary,
      DvrRecordingStatus.failed => colorScheme.error,
      DvrRecordingStatus.cancelled => colorScheme.onSurfaceVariant,
      DvrRecordingStatus.deleted => colorScheme.onSurfaceVariant,
      DvrRecordingStatus.unknown => colorScheme.onSurfaceVariant,
    };
  }
}

class _LeadingTile extends StatelessWidget {
  const _LeadingTile({
    required this.recording,
    required this.selected,
    required this.selectMode,
    required this.tileColor,
  });

  final DvrRecording recording;
  final bool selected;
  final bool selectMode;
  final Color tileColor;

  static const double _size = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (selectMode) {
      final accent = selected ? colorScheme.primary : colorScheme.outline;
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent, width: 2),
        ),
        child: Icon(
          selected ? Icons.check_box : Icons.check_box_outline_blank,
          color: accent,
        ),
      );
    }

    final icon = switch (recording.status) {
      DvrRecordingStatus.recording => Icons.fiber_manual_record,
      DvrRecordingStatus.postProcessing => Icons.sync,
      DvrRecordingStatus.completed => Icons.check_circle,
      DvrRecordingStatus.scheduled => Icons.schedule,
      DvrRecordingStatus.failed => Icons.error,
      DvrRecordingStatus.cancelled => Icons.cancel,
      DvrRecordingStatus.deleted => Icons.delete,
      DvrRecordingStatus.unknown => Icons.radio_button_unchecked,
    };
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: tileColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: tileColor),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.recording, required this.statusColor});

  final DvrRecording recording;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final base =
        theme.textTheme.bodySmall ??
        const TextStyle(fontSize: 12, color: Colors.white);
    final muted = base.copyWith(color: colorScheme.onSurfaceVariant);

    final String? statusWord;
    final bool statusWordIsError;
    switch (recording.status) {
      case DvrRecordingStatus.recording:
        statusWord = '● ${l10n.dvrStatusRecording}';
        statusWordIsError = false;
      case DvrRecordingStatus.scheduled:
        statusWord = l10n.dvrStatusScheduled;
        statusWordIsError = false;
      case DvrRecordingStatus.failed:
        statusWord = l10n.dvrStatusFailed;
        statusWordIsError = true;
      case DvrRecordingStatus.completed:
      case DvrRecordingStatus.cancelled:
      case DvrRecordingStatus.postProcessing:
      case DvrRecordingStatus.deleted:
      case DvrRecordingStatus.unknown:
        statusWord = null;
        statusWordIsError = false;
    }

    final channel = recording.channelName;
    final season = recording.seasonNumber;
    final episode = recording.episodeNumber;
    String? episodeLabel;
    if (season != null && episode != null) {
      episodeLabel = 'S$season-E$episode';
    } else if (season != null) {
      episodeLabel = 'S$season';
    } else if (episode != null) {
      episodeLabel = 'E$episode';
    }
    final duration = recording.durationSeconds;
    final size = recording.fileSizeBytes;

    final spans = <InlineSpan>[];
    if (statusWord != null) {
      spans.add(
        TextSpan(
          text: statusWord,
          style: base.copyWith(
            color: statusWordIsError ? colorScheme.error : statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    void appendSeparator() {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: ' · ', style: muted));
      }
    }

    if (channel != null && channel.isNotEmpty) {
      appendSeparator();
      spans.add(TextSpan(text: channel, style: muted));
    }
    if (episodeLabel != null) {
      appendSeparator();
      spans.add(TextSpan(text: episodeLabel, style: muted));
    }
    if (duration != null && duration > 0) {
      appendSeparator();
      spans.add(TextSpan(text: _durationLabel(duration), style: muted));
    }
    if (size != null && size > 0) {
      appendSeparator();
      spans.add(TextSpan(text: _sizeLabel(size), style: muted));
    }

    return Text.rich(
      TextSpan(style: muted, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _durationLabel(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }

  String _sizeLabel(int bytes) {
    final gib = bytes / (1024 * 1024 * 1024);
    if (gib >= 1) return '${gib.toStringAsFixed(1)} GB';
    final mib = bytes / (1024 * 1024);
    return '${mib.toStringAsFixed(0)} MB';
  }
}

class _OverflowMenu extends StatefulWidget {
  const _OverflowMenu({
    required this.tooltip,
    this.onPlay,
    this.onStop,
    this.onDelete,
    this.onSelect,
  });

  final String tooltip;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  @override
  State<_OverflowMenu> createState() => _OverflowMenuState();
}

class _OverflowMenuState extends State<_OverflowMenu> {
  static const _menuEffects = <DpadEffect>[
    GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
  ];
  static const _menuWidth = 180.0;
  static const _menuStyle = MenuStyle(
    minimumSize: WidgetStatePropertyAll(Size(_menuWidth, 0)),
  );

  final MenuController _controller = MenuController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _open() => _controller.open();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <Widget>[
      if (widget.onPlay != null)
        _menuItem(text: l10n.dvrPlay, onPressed: widget.onPlay!),
      if (widget.onSelect != null)
        _menuItem(text: l10n.dvrSelect, onPressed: widget.onSelect!),
      if (widget.onStop != null)
        _menuItem(text: l10n.dvrStop, onPressed: widget.onStop!),
      if (widget.onDelete != null)
        _menuItem(text: l10n.dvrDelete, onPressed: widget.onDelete!),
    ];

    return DpadFocusable(
      focusNode: _focusNode,
      onSelect: _open,
      effects: _menuEffects,
      child: MenuAnchor(
        controller: _controller,
        style: _menuStyle,
        menuChildren: items,
        child: IconButton(
          tooltip: widget.tooltip,
          onPressed: _open,
          icon: const Icon(Icons.more_vert),
        ),
      ),
    );
  }

  Widget _menuItem({required String text, required VoidCallback onPressed}) {
    return SizedBox(
      width: _menuWidth,
      child: MenuItemButton(
        onPressed: () {
          _controller.close();
          onPressed();
        },
        child: Text(text),
      ),
    );
  }
}

class _SelectionActionBar extends StatelessWidget {
  const _SelectionActionBar({
    required this.count,
    required this.onExit,
    this.onDelete,
  });

  final int count;
  final VoidCallback onExit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MediaBrowsingMetrics.contentPadding,
            vertical: 8,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.dvrExitSelection,
                onPressed: onExit,
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.dvrSelectedCount(count),
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onDelete != null)
                FilledButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete),
                  label: Text(l10n.dvrDelete),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
