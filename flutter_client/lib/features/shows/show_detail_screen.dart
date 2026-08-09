import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/dvr/dvr_series_rule_options_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dvr_action_dialogs.dart';
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

  @override
  ConsumerState<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends ConsumerState<ShowDetailScreen> {
  bool _isSubmitting = false;

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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.showDetailTitle),
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.all(8),
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
            ...show.recentEpisodes.map(
              (episode) => Padding(
                padding: const EdgeInsets.only(
                  bottom: MediaBrowsingMetrics.chipGap,
                ),
                child: _EpisodeRow(episode: episode, localeTag: localized),
              ),
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

  // Below this width the title + action buttons no longer fit on one row —
  // on a phone, forcing them into a Row starves the title's Expanded column
  // down to a sliver, wrapping every word onto its own line.
  static const double _narrowBreakpoint = 420;

  Widget? _buildActions(AppLocalizations l10n) {
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

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.episode, required this.localeTag});
  final EpgShowEpisode episode;
  final String localeTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = DateFormat.yMMMd(
      localeTag,
    ).add_jm().format(episode.startTime.toLocal());

    return DpadInkWell(
      borderRadius: BorderRadius.circular(8),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.play_arrow,
                color: theme.colorScheme.onTertiaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${episode.channelName} $timeLabel',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
