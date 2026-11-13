import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/dvr/dvr_series_rule_options_screen.dart';
import 'package:m3u_tv/features/shows/shows_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_callout.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_menu_dialog.dart';
import 'package:m3u_tv/shared/app_modal.dart';
import 'package:m3u_tv/shared/app_top_bar.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/leading_tile.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/natural_sort.dart';
import 'package:m3u_tv/shared/row_action_menu.dart';
import 'package:m3u_tv/shared/selectable_chip.dart';
import 'package:m3u_tv/shared/sort_option_row.dart';
import 'package:material_ui/material_ui.dart';

/// Fallback for detecting the expand-in-place row actions (desktop/TV) vs.
/// the tap-to-open overflow menu (touch/mobile), used only when
/// [DvrRecordingsScreen.useInlineRowActions] isn't supplied (previews,
/// tests). The real app always passes it explicitly from `AppShell`, which
/// resolves `DeviceType` via `resolveDeviceType`/`shouldUseSidebar` —
/// including the Android-TV `nativeTelevisionHint` case this local check
/// can't see, since it isn't threaded through `MediaQuery`/`Platform`.
///
/// Mirrors the tv-or-desktop split `device_type_resolver.dart`'s
/// `deviceTypeForView` computes, duplicated narrowly here rather than
/// importing `app_shell.dart`'s `DeviceType`/`shouldUseSidebar` — that file
/// imports this one transitively (via this screen), so importing it back
/// would cycle. Same precedent as `_isRemoteDrivenEnvironment` in
/// `dvr_series_rule_options_screen.dart`.
bool _useInlineRowActions(BuildContext context) {
  if (HostPlatform.isTvOS) return true;
  if (MediaQuery.maybeNavigationModeOf(context) == NavigationMode.directional) {
    return true;
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => true,
    _ => false,
  };
}

class DvrRecordingsScreen extends StatefulWidget {
  const DvrRecordingsScreen({
    super.key,
    required this.recordings,
    required this.isLoading,
    required this.isConfigured,
    required this.onPlay,
    this.loadState = DvrRecordingsLoadState.loaded,
    this.onRetry,
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
    this.onHandleTopLevelBack,
    this.useInlineRowActions,
  });

  final List<DvrRecording> recordings;
  final bool isLoading;
  final bool isConfigured;

  /// How the last full library load went. Separates "nothing recorded" from
  /// "couldn't load", and flags a list missing its older pages.
  final DvrRecordingsLoadState loadState;

  /// Reloads the whole library (Try again on an error or partial load).
  final Future<void> Function()? onRetry;

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

  /// Wired from AppShell to `AppShellState.handleBackFromTopLevelRoute`
  /// (via `ContentActions.onHandleTopLevelBack`). The Series Rules tab
  /// opens the DVR Options screen via `openDvrSeriesRuleOptions`, which
  /// pushes onto the *root* Navigator (see that function's doc comment for
  /// why) rather than a go_router route nested under AppShell - so it's
  /// outside AppShell's own `Shortcuts`/`Actions` back handling the same
  /// way the top-level VOD/Series/AIOStreams detail routes are, and needs
  /// this passed through so Escape/GoBack still routes through AppShell's
  /// back-echo dedup instead of popping independently.
  final bool Function()? onHandleTopLevelBack;

  /// Whether row actions (Recordings/Series Rules) should render as
  /// expand-in-place D-pad-focusable buttons (desktop/TV) instead of a
  /// tap-to-open overflow menu (touch/mobile). `AppShell` always passes
  /// this from its already-resolved `DeviceType`; when omitted (previews,
  /// tests) it falls back to [_useInlineRowActions]'s local heuristic.
  final bool? useInlineRowActions;

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

  /// Status filter for the Recordings tab; null shows every status.
  DvrRecordingStatus? _statusFilter;
  DvrRecordingSort _sort = DvrRecordingSort.newest;

  // Memoized so a library of thousands isn't re-counted, filtered and sorted
  // on every rebuild; recomputed only when the list, filter or sort changes.
  List<DvrRecording>? _countsSource;
  Map<DvrRecordingStatus, int> _statusCounts = const {};
  List<DvrRecording>? _viewSource;
  DvrRecordingStatus? _viewFilter;
  DvrRecordingSort? _viewSort;
  List<DvrRecording> _view = const <DvrRecording>[];

  Map<DvrRecordingStatus, int> _countsFor(List<DvrRecording> recordings) {
    if (!identical(recordings, _countsSource)) {
      final counts = <DvrRecordingStatus, int>{};
      for (final recording in recordings) {
        counts.update(recording.status, (n) => n + 1, ifAbsent: () => 1);
      }
      _countsSource = recordings;
      _statusCounts = counts;
    }
    return _statusCounts;
  }

  List<DvrRecording> _visibleRecordings(List<DvrRecording> recordings) {
    if (identical(recordings, _viewSource) &&
        _viewFilter == _statusFilter &&
        _viewSort == _sort) {
      return _view;
    }
    final filter = _statusFilter;
    final filtered = filter == null
        ? recordings.toList()
        : recordings.where((r) => r.status == filter).toList();
    sortDvrRecordings(filtered, _sort);
    _viewSource = recordings;
    _viewFilter = filter;
    _viewSort = _sort;
    _view = filtered;
    return filtered;
  }

  Future<void> _pickSort() async {
    final picked = await showDvrRecordingSortDialog(context, current: _sort);
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
  }

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
    final inline = widget.useInlineRowActions ?? _useInlineRowActions(context);
    if (!widget.isConfigured) {
      return Scaffold(
        appBar: AppTopBar(title: Text(l10n.dvrRecordingsTitle)),
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
            child: DpadTabBarView(
              controller: _tabController,
              children: [
                Padding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.pagePadding,
                  ),
                  child: _buildRecordingsTab(context, inline),
                ),
                Padding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.pagePadding,
                  ),
                  child: _buildSeriesRulesTab(context, inline),
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

  Widget _buildRecordingsTab(BuildContext context, bool inline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.storageInfo != null) ...[
          _DvrStorageSummary(info: widget.storageInfo!),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        Expanded(child: _buildRecordingsBody(context, inline)),
      ],
    );
  }

  Widget _buildRecordingsBody(BuildContext context, bool inline) {
    final l10n = AppLocalizations.of(context);
    final recordings = widget.recordings;
    final loadState = widget.loadState;
    final loadFailed =
        loadState == DvrRecordingsLoadState.error ||
        loadState == DvrRecordingsLoadState.offline;

    if (recordings.isEmpty) {
      if (widget.isLoading || loadState == DvrRecordingsLoadState.loading) {
        return const Center(child: AppLoadingIndicator());
      }
      if (loadFailed) {
        return _DvrLoadFailure(
          offline: loadState == DvrRecordingsLoadState.offline,
          onRetry: widget.onRetry,
          onSidebarActivate: widget.onSidebarActivate,
        );
      }
      return Center(
        child: Text(
          l10n.dvrNoRecordings,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final counts = _countsFor(recordings);
    final visible = _visibleRecordings(recordings);
    final notice = switch (loadState) {
      DvrRecordingsLoadState.partial => l10n.dvrLoadPartial,
      DvrRecordingsLoadState.error ||
      DvrRecordingsLoadState.offline => l10n.dvrLoadRefreshFailed,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          _DvrLoadNotice(
            message: notice,
            onRetry: widget.onRetry,
            onSidebarActivate: widget.onSidebarActivate,
          ),
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        ],
        _RecordingFilterBar(
          total: recordings.length,
          counts: counts,
          selected: _statusFilter,
          sort: _sort,
          onSelect: (status) => setState(() => _statusFilter = status),
          onSort: _pickSort,
          onSidebarActivate: widget.onSidebarActivate,
        ),
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    l10n.dvrFilterEmpty,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : _RecordingList(
                  // A new filter starts a fresh selection, so a selection
                  // can't include recordings the filter hides.
                  key: ValueKey<DvrRecordingStatus?>(_statusFilter),
                  recordings: visible,
                  onPlay: widget.onPlay,
                  onCancelRecording: widget.onCancelRecording,
                  onCancelAndDeleteRecording: widget.onCancelAndDeleteRecording,
                  onDeleteRecording: widget.onDeleteRecording,
                  onSidebarActivate: widget.onSidebarActivate,
                  inline: inline,
                ),
        ),
      ],
    );
  }

  Widget _buildSeriesRulesTab(BuildContext context, bool inline) {
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
      onHandleTopLevelBack: widget.onHandleTopLevelBack,
      inline: inline,
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

/// Recordings tab sort orders.
enum DvrRecordingSort {
  /// Latest scheduled start first (the server's own order).
  newest,

  /// Earliest scheduled start first.
  oldest,

  /// Title in natural A-Z order.
  title,
}

/// Sorts [recordings] in place. Recordings with no scheduled start go last
/// for the date orders, and ties keep their incoming order.
@visibleForTesting
void sortDvrRecordings(List<DvrRecording> recordings, DvrRecordingSort sort) {
  if (recordings.length < 2) return;
  final indexed =
      [
        for (var i = 0; i < recordings.length; i++)
          (
            index: i,
            item: recordings[i],
            titleKey: sort == DvrRecordingSort.title
                ? NaturalSortKey.of(recordings[i].title)
                : null,
          ),
      ]..sort((a, b) {
        final int cmp;
        if (sort == DvrRecordingSort.title) {
          cmp = a.titleKey!.compareTo(b.titleKey!);
        } else {
          final aStart = a.item.scheduledStart;
          final bStart = b.item.scheduledStart;
          if (aStart == null || bStart == null) {
            if (aStart != bStart) return aStart == null ? 1 : -1;
            cmp = 0;
          } else {
            cmp = sort == DvrRecordingSort.newest
                ? bStart.compareTo(aStart)
                : aStart.compareTo(bStart);
          }
        }
        return cmp != 0 ? cmp : a.index - b.index;
      });
  for (var i = 0; i < indexed.length; i++) {
    recordings[i] = indexed[i].item;
  }
}

String dvrRecordingSortLabel(AppLocalizations l10n, DvrRecordingSort sort) {
  return switch (sort) {
    DvrRecordingSort.newest => l10n.dvrSortNewest,
    DvrRecordingSort.oldest => l10n.dvrSortOldest,
    DvrRecordingSort.title => l10n.dvrSortTitle,
  };
}

/// The Recordings tab's sort picker, in the same modal style as the media
/// grids' Sort By. Returns null when dismissed.
Future<DvrRecordingSort?> showDvrRecordingSortDialog(
  BuildContext context, {
  required DvrRecordingSort current,
}) {
  final l10n = AppLocalizations.of(context);
  final options = <(IconData, DvrRecordingSort)>[
    (Icons.south, DvrRecordingSort.newest),
    (Icons.north, DvrRecordingSort.oldest),
    (Icons.sort_by_alpha, DvrRecordingSort.title),
  ];
  return showAppDialog<DvrRecordingSort>(
    context: context,
    builder: (dialogContext) {
      final scale = FontSizeScope.scaleOf(dialogContext);
      return AppMenuDialog(
        title: Row(
          children: [
            Icon(Icons.sort, size: 18 * scale),
            SizedBox(width: 8 * scale),
            Expanded(child: Text(l10n.dvrSortDialogTitle)),
          ],
        ),
        children: [
          DpadRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (icon, option) in options)
                  SortOptionRow(
                    icon: icon,
                    label: dvrRecordingSortLabel(l10n, option),
                    isActive: current == option,
                    autofocus: current == option,
                    onTap: () => Navigator.of(dialogContext).pop(option),
                  ),
                SortOptionRow(
                  icon: Icons.close,
                  label: l10n.close,
                  onTap: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Statuses offered as filters, in the order the chips appear.
const List<DvrRecordingStatus> _filterStatuses = <DvrRecordingStatus>[
  DvrRecordingStatus.recording,
  DvrRecordingStatus.scheduled,
  DvrRecordingStatus.postProcessing,
  DvrRecordingStatus.completed,
  DvrRecordingStatus.failed,
  DvrRecordingStatus.cancelled,
];

String _statusFilterLabel(AppLocalizations l10n, DvrRecordingStatus status) {
  return switch (status) {
    DvrRecordingStatus.recording => l10n.dvrStatusRecording,
    DvrRecordingStatus.scheduled => l10n.dvrStatusScheduled,
    DvrRecordingStatus.postProcessing => l10n.dvrStatusProcessing,
    DvrRecordingStatus.completed => l10n.dvrStatusCompleted,
    DvrRecordingStatus.failed => l10n.dvrStatusFailed,
    DvrRecordingStatus.cancelled => l10n.dvrStatusCancelled,
    DvrRecordingStatus.deleted ||
    DvrRecordingStatus.unknown => l10n.dvrFilterAll,
  };
}

/// Status chips (All plus each status the library holds, with counts) and
/// the sort button above the recordings list.
class _RecordingFilterBar extends StatelessWidget {
  const _RecordingFilterBar({
    required this.total,
    required this.counts,
    required this.selected,
    required this.sort,
    required this.onSelect,
    required this.onSort,
    this.onSidebarActivate,
  });

  final int total;
  final Map<DvrRecordingStatus, int> counts;
  final DvrRecordingStatus? selected;
  final DvrRecordingSort sort;
  final ValueChanged<DvrRecordingStatus?> onSelect;
  final VoidCallback onSort;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return DpadRegion(
      memoryKey: 'dvr/recordings-filters',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) onSidebarActivate?.call();
      },
      child: Wrap(
        spacing: 8 * scale,
        runSpacing: 8 * scale,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SelectableChip(
            label: l10n.dvrFilterWithCount(l10n.dvrFilterAll, total),
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final status in _filterStatuses)
            if ((counts[status] ?? 0) > 0 || selected == status)
              SelectableChip(
                label: l10n.dvrFilterWithCount(
                  _statusFilterLabel(l10n, status),
                  counts[status] ?? 0,
                ),
                selected: selected == status,
                onTap: () => onSelect(status),
              ),
          SelectableChip(
            label: l10n.dvrSortButton(dvrRecordingSortLabel(l10n, sort)),
            selected: false,
            onTap: onSort,
          ),
        ],
      ),
    );
  }
}

/// Full-tab message when the library couldn't load and nothing is cached.
class _DvrLoadFailure extends StatelessWidget {
  const _DvrLoadFailure({
    required this.offline,
    this.onRetry,
    this.onSidebarActivate,
  });

  final bool offline;
  final Future<void> Function()? onRetry;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final retry = onRetry;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppCallout(
              message: offline ? l10n.dvrLoadOffline : l10n.dvrLoadError,
              variant: AppCalloutVariant.error,
            ),
            if (retry != null) ...[
              const SizedBox(height: 16),
              DpadRegion(
                horizontalEdge: DpadEdgeBehavior.stop,
                onEdge: (direction) {
                  if (direction == TraversalDirection.left) {
                    onSidebarActivate?.call();
                  }
                },
                child: AppButton(
                  icon: Icons.refresh,
                  label: l10n.dvrRetry,
                  autofocus: true,
                  onPressed: retry,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Banner above a list that is incomplete (older pages missing) or stale (a
/// refresh failed), with Try again.
class _DvrLoadNotice extends StatelessWidget {
  const _DvrLoadNotice({
    required this.message,
    this.onRetry,
    this.onSidebarActivate,
  });

  final String message;
  final Future<void> Function()? onRetry;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final retry = onRetry;
    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) onSidebarActivate?.call();
      },
      child: Row(
        children: [
          Expanded(
            child: AppCallout(
              message: message,
              variant: AppCalloutVariant.warning,
            ),
          ),
          if (retry != null) ...[
            const SizedBox(width: 12),
            AppButton(
              icon: Icons.refresh,
              label: l10n.dvrRetry,
              onPressed: retry,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeriesRulesList extends StatefulWidget {
  const _SeriesRulesList({
    required this.rules,
    required this.inline,
    this.onDelete,
    this.onUpdate,
    this.onSidebarActivate,
    this.onHandleTopLevelBack,
  });

  final List<DvrSeriesRule> rules;
  final bool inline;
  final Future<void> Function(DvrSeriesRule)? onDelete;
  final Future<void> Function(DvrSeriesRule rule, DvrSeriesRuleOptions options)?
  onUpdate;
  final VoidCallback? onSidebarActivate;
  final bool Function()? onHandleTopLevelBack;

  @override
  State<_SeriesRulesList> createState() => _SeriesRulesListState();
}

class _SeriesRulesListState extends State<_SeriesRulesList> {
  final Set<int> _selectedIds = <int>{};
  final FocusNode _railFocusNode = FocusNode(
    debugLabel: 'dvr/series-rules-rail-entry',
  );

  bool get _selectMode => _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _railFocusNode.dispose();
    super.dispose();
  }

  void _toggleSelection(int id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _enterSelectMode(int id) {
    setState(() {
      _selectedIds.add(id);
    });
  }

  void _exitSelectMode() {
    setState(_selectedIds.clear);
  }

  Future<void> _openEdit(BuildContext context, DvrSeriesRule rule) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final options = await openDvrSeriesRuleOptions(
      context,
      show: _showForRule(rule),
      initialRule: rule,
      onBack: widget.onHandleTopLevelBack,
    );
    if (options == null || !context.mounted) return;
    try {
      await widget.onUpdate!(rule, options);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dvrUpdateSeriesRuleSuccess)),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.dvrUpdateSeriesRuleFailed)),
      );
    }
  }

  Future<void> _confirmDeleteSingle(
    BuildContext context,
    DvrSeriesRule rule,
  ) async {
    final delete = widget.onDelete;
    if (delete == null) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDeleteSeriesRuleDialog(context, rule: rule);
    if (confirmed != true) return;
    if (!context.mounted) return;
    await runDvrActionWithFeedback(
      context,
      () => delete(rule),
      successMessage: l10n.dvrDeleteSeriesRuleSuccess,
      failureMessage: l10n.dvrDeleteSeriesRuleFailed,
    );
  }

  Future<void> _deleteSelected() async {
    final delete = widget.onDelete;
    if (delete == null) return;
    final selected = widget.rules.where((r) => _selectedIds.contains(r.id));
    for (final rule in selected) {
      await delete(rule);
    }
    _exitSelectMode();
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

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: DpadRegion(
                  memoryKey: 'dvr/series-rules',
                  horizontalEdge: DpadEdgeBehavior.stop,
                  onEdge: (direction) {
                    if (direction == TraversalDirection.left) {
                      widget.onSidebarActivate?.call();
                    } else if (direction == TraversalDirection.right &&
                        widget.inline &&
                        _selectMode) {
                      _railFocusNode.requestFocus();
                    }
                  },
                  child: ScrollbarListView(
                    itemCount: widget.rules.length,
                    itemBuilder: (context, index) {
                      final rule = widget.rules[index];
                      final selected = _selectedIds.contains(rule.id);
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: MediaBrowsingMetrics.itemGap,
                        ),
                        child: _SeriesRuleCard(
                          rule: rule,
                          autofocus: index == 0,
                          inline: widget.inline,
                          selectMode: _selectMode,
                          selected: selected,
                          onTap: _selectMode
                              ? () => _toggleSelection(rule.id)
                              : null,
                          onLongTap: () => _enterSelectMode(rule.id),
                          onEdit: widget.onUpdate == null
                              ? null
                              : () => _openEdit(context, rule),
                          onDelete: widget.onDelete == null
                              ? null
                              : () => _confirmDeleteSingle(context, rule),
                          onSelect: !_selectMode
                              ? () => _enterSelectMode(rule.id)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (_selectMode && !widget.inline)
                _SelectionActionBar(
                  count: _selectedIds.length,
                  onExit: _exitSelectMode,
                  onDelete: widget.onDelete != null ? _deleteSelected : null,
                ),
            ],
          ),
        ),
        if (_selectMode && widget.inline)
          _SelectionRail(
            count: _selectedIds.length,
            onExit: _exitSelectMode,
            onDelete: widget.onDelete != null ? _deleteSelected : null,
            focusNode: _railFocusNode,
          ),
      ],
    );
  }
}

class _SeriesRuleCard extends StatelessWidget {
  const _SeriesRuleCard({
    required this.rule,
    required this.autofocus,
    required this.inline,
    required this.selectMode,
    required this.selected,
    required this.onTap,
    required this.onLongTap,
    this.onEdit,
    this.onDelete,
    this.onSelect,
  });

  final DvrSeriesRule rule;
  final bool autofocus;
  final bool inline;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final canSelect = onSelect != null;
    // Hidden while selecting: bulk actions live in the selection rail/bar
    // instead, freeing the row's right edge for d-pad traversal to reach it.
    final hasMenu =
        !selectMode && (onEdit != null || canSelect || onDelete != null);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: DpadInkWell(
              autofocus: autofocus,
              onTap: onTap,
              onLongTap: onLongTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(
                  MediaBrowsingMetrics.contentPadding,
                ),
                child: Row(
                  children: [
                    LeadingTile(
                      icon: Icons.fiber_manual_record,
                      selected: selected,
                      selectMode: selectMode,
                      tileColor: theme.colorScheme.primary,
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
                                label: l10n.dvrEpisodeCount(
                                  rule.recordingCount,
                                ),
                              ),
                            ],
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
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                child: RowActionMenu(
                  moreLabel: l10n.dvrMoreActions,
                  inline: inline,
                  actions: [
                    if (onEdit != null)
                      RowAction(
                        icon: Icons.edit,
                        label: l10n.dvrEditSeriesRule,
                        onPressed: onEdit!,
                      ),
                    if (onSelect != null)
                      RowAction(
                        icon: Icons.check,
                        label: l10n.dvrSelect,
                        onPressed: onSelect!,
                      ),
                    if (onDelete != null)
                      RowAction(
                        icon: Icons.delete,
                        label: l10n.dvrDeleteSeriesRule,
                        onPressed: onDelete!,
                        type: RowActionType.danger,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
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

    final usedLabel = formatBytes(info.usedBytes);
    final summary = quotaBytes == null
        ? l10n.dvrStorageUsedUnlimited(usedLabel)
        : l10n.dvrStorageUsedWithQuota(usedLabel, formatBytes(quotaBytes));

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

class _RecordingList extends ConsumerStatefulWidget {
  const _RecordingList({
    super.key,
    required this.recordings,
    required this.onPlay,
    required this.inline,
    this.onCancelRecording,
    this.onCancelAndDeleteRecording,
    this.onDeleteRecording,
    this.onSidebarActivate,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args) onPlay;
  final bool inline;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onCancelAndDeleteRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;
  final VoidCallback? onSidebarActivate;

  @override
  ConsumerState<_RecordingList> createState() => _RecordingListState();
}

class _RecordingListState extends ConsumerState<_RecordingList> {
  final Set<String> _selectedUuids = <String>{};
  final FocusNode _railFocusNode = FocusNode(
    debugLabel: 'dvr/recordings-rail-entry',
  );

  bool get _selectMode => _selectedUuids.isNotEmpty;

  @override
  void dispose() {
    _railFocusNode.dispose();
    super.dispose();
  }

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
    if (!recording.isPlayable) return;
    widget.onPlay(PlayerArgs.dvrRecording(recording));
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
    await confirmDeleteRecording(
      context,
      uuid: recording.uuid,
      onDelete: delete,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: DpadRegion(
                  memoryKey: 'dvr/recordings',
                  horizontalEdge: DpadEdgeBehavior.stop,
                  onEdge: (direction) {
                    if (direction == TraversalDirection.left) {
                      widget.onSidebarActivate?.call();
                    } else if (direction == TraversalDirection.right &&
                        widget.inline &&
                        _selectMode) {
                      _railFocusNode.requestFocus();
                    }
                  },
                  child: ScrollbarListView(
                    itemCount: widget.recordings.length,
                    itemBuilder: (context, index) {
                      final recording = widget.recordings[index];
                      final selected = _selectedUuids.contains(
                        recording.uuid,
                      );
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
                          inline: widget.inline,
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
                          onStop: canStop
                              ? () => _confirmStop(recording)
                              : null,
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
              if (_selectMode && !widget.inline)
                _SelectionActionBar(
                  count: _selectedUuids.length,
                  onExit: _exitSelectMode,
                  onDelete: widget.onDeleteRecording != null
                      ? _deleteSelected
                      : null,
                ),
            ],
          ),
        ),
        if (_selectMode && widget.inline)
          _SelectionRail(
            count: _selectedUuids.length,
            onExit: _exitSelectMode,
            onDelete: widget.onDeleteRecording != null ? _deleteSelected : null,
            focusNode: _railFocusNode,
          ),
      ],
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.recording,
    required this.autofocus,
    required this.inline,
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
  final bool inline;
  final bool selectMode;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongTap;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onDelete;
  final VoidCallback? onSelect;

  static const double _rowHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(colorScheme);
    final canSelect = onSelect != null;
    final scale = FontSizeScope.scaleOf(context);
    // Hidden while selecting: bulk actions live in the selection rail/bar
    // instead, freeing the row's right edge for d-pad traversal to reach it.
    final hasMenu =
        !selectMode &&
        (onPlay != null || canSelect || onStop != null || onDelete != null);

    return SizedBox(
      height: _rowHeight * scale,
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
                      LeadingTile(
                        icon: _recordingStatusIcon(recording.status),
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
                padding: const EdgeInsets.only(left: 8),
                child: Center(
                  child: RowActionMenu(
                    moreLabel: AppLocalizations.of(context).dvrMoreActions,
                    inline: inline,
                    actions: [
                      if (onPlay != null)
                        RowAction(
                          icon: Icons.play_arrow,
                          label: AppLocalizations.of(context).dvrPlay,
                          onPressed: onPlay!,
                        ),
                      if (onSelect != null)
                        RowAction(
                          icon: Icons.check,
                          label: AppLocalizations.of(context).dvrSelect,
                          onPressed: onSelect!,
                        ),
                      if (onStop != null)
                        RowAction(
                          icon: Icons.stop,
                          label: AppLocalizations.of(context).dvrStop,
                          onPressed: onStop!,
                          type: RowActionType.danger,
                        ),
                      if (onDelete != null)
                        RowAction(
                          icon: Icons.delete,
                          label: AppLocalizations.of(context).dvrDelete,
                          onPressed: onDelete!,
                          type: RowActionType.danger,
                        ),
                    ],
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

IconData _recordingStatusIcon(DvrRecordingStatus status) {
  return switch (status) {
    DvrRecordingStatus.recording => Icons.fiber_manual_record,
    DvrRecordingStatus.postProcessing => Icons.sync,
    DvrRecordingStatus.completed => Icons.check_circle,
    DvrRecordingStatus.scheduled => Icons.schedule,
    DvrRecordingStatus.failed => Icons.error,
    DvrRecordingStatus.cancelled => Icons.cancel,
    DvrRecordingStatus.deleted => Icons.delete,
    DvrRecordingStatus.unknown => Icons.radio_button_unchecked,
  };
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
      spans.add(
        TextSpan(
          text: formatRuntime(Duration(seconds: duration)),
          style: muted,
        ),
      );
    }
    if (size != null && size > 0) {
      appendSeparator();
      spans.add(TextSpan(text: formatBytes(size), style: muted));
    }

    return Text.rich(
      TextSpan(style: muted, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
              DpadFocusable(
                onSelect: onExit,
                effects: kStadiumFocusEffects,
                child: IconButton(
                  tooltip: l10n.dvrExitSelection,
                  onPressed: onExit,
                  icon: const Icon(Icons.close),
                ),
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
                AppButton(
                  label: l10n.dvrDelete,
                  icon: Icons.delete,
                  variant: AppButtonVariant.destructive,
                  onPressed: onDelete,
                  // Always on-screen once the selection bar is showing —
                  // see the matching comment in row_action_menu.dart.
                  autoScroll: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// TV/desktop counterpart to [_SelectionActionBar]: a rail docked to the
/// list's right edge instead of a bar below it. A bottom bar only exists
/// after the last row, so reaching it with a d-pad means holding Down
/// through every row above it first — fine for a short touch scroll, a
/// real barrier on a long list navigated one focus stop at a time. Docking
/// beside the list instead means it's always exactly one Right press away
/// from whichever row currently has focus, regardless of scroll position.
/// The enclosing list's `DpadRegion.onEdge` forwards a Right press at its
/// horizontal edge to [focusNode] (the rail's entry point); Left back out
/// of the rail is plain [DpadRegion] cross-region traversal, which restores
/// whichever row was last focused.
class _SelectionRail extends StatelessWidget {
  const _SelectionRail({
    required this.count,
    required this.onExit,
    required this.focusNode,
    this.onDelete,
  });

  final int count;
  final VoidCallback onExit;
  final VoidCallback? onDelete;
  final FocusNode focusNode;

  static const double _railWidth = 88;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: DpadRegion(
        debugLabel: 'dvr/selection-rail',
        verticalEdge: DpadEdgeBehavior.stop,
        child: Container(
          width: _railWidth,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIconButton(
                icon: Icons.close,
                tooltip: l10n.dvrExitSelection,
                onPressed: onExit,
                focusNode: onDelete == null ? focusNode : null,
                // Docked rail is always on-screen — see the matching
                // comment in row_action_menu.dart.
                autoScroll: false,
              ),
              const SizedBox(height: 20),
              Tooltip(
                message: l10n.dvrSelectedCount(count),
                child: Text(
                  '$count',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (onDelete != null)
                AppIconButton(
                  icon: Icons.delete,
                  tooltip: l10n.dvrDelete,
                  variant: AppButtonVariant.destructive,
                  onPressed: onDelete,
                  focusNode: focusNode,
                  autoScroll: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
