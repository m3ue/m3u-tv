import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Shows the series-rule configure sheet anchored to the given context.
/// Returns the picked [DvrSeriesRuleOptions] on Save, or null if the user
/// dismisses without saving (including Back press).
///
/// The [show] parameter carries `channels`, `channelCount`, `nextAiringAt`, and
/// `recentEpisodes` — used to populate the channel picker and compute the
/// default channel selection.
///
/// When [initialRule] is provided the sheet pre-fills every field from the
/// existing rule (edit mode). The channel picker is driven by [show]; for the
/// DVR screen's edit path callers construct a minimal [EpgShow] from the rule
/// (channelCount 1 / no recent episodes) so the picker stays hidden and the
/// rule's channel is preserved unless the caller intends otherwise.
Future<DvrSeriesRuleOptions?> showDvrSeriesRuleSheet(
  BuildContext context, {
  required EpgShow show,
  DvrSeriesRule? initialRule,
}) {
  return showModalBottomSheet<DvrSeriesRuleOptions>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _DvrSeriesRuleSheet(
      show: show,
      initialRule: initialRule,
    ),
  );
}

/// Finds the channel that matches the next airing — looks in
/// `show.recentEpisodes` for the episode whose `startTime` matches
/// `show.nextAiringAt` and returns its channelId. Returns null if no match
/// is found (falls back to "any channel").
int? nextAiringChannelId(EpgShow show) {
  final next = show.nextAiringAt;
  if (next == null) return null;
  for (final ep in show.recentEpisodes) {
    if (ep.startTime.toUtc() == next.toUtc()) {
      // Sanity-check: only accept if this channel is in show.channels.
      if (show.channels.any((c) => c.channelId == ep.channelId)) {
        return ep.channelId;
      }
    }
  }
  return null;
}

class _DvrSeriesRuleSheet extends StatefulWidget {
  const _DvrSeriesRuleSheet({required this.show, this.initialRule});

  final EpgShow show;
  final DvrSeriesRule? initialRule;

  @override
  State<_DvrSeriesRuleSheet> createState() => _DvrSeriesRuleSheetState();
}

class _DvrSeriesRuleSheetState extends State<_DvrSeriesRuleSheet> {
  late int? _selectedChannelId;
  late DvrSeriesMode? _selectedSeriesMode;
  late DvrMatchMode _selectedMatchMode;

  // Controllers for numeric TextFields (0 is a valid value; empty = omit).
  late TextEditingController _keepLastController;
  late TextEditingController _priorityController;
  late TextEditingController _startEarlyController;
  late TextEditingController _endLateController;

  bool get _isAllEpisodesWarningVisible =>
      _selectedChannelId == null && _selectedSeriesMode == DvrSeriesMode.all;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    if (rule == null) {
      _selectedChannelId = nextAiringChannelId(widget.show);
      _selectedSeriesMode = null; // Use default = omit
      _selectedMatchMode = DvrMatchMode.contains;
    } else {
      _selectedChannelId = rule.channelId == 0 ? null : rule.channelId;
      _selectedSeriesMode = rule.seriesMode;
      _selectedMatchMode = rule.matchMode;
    }

    _keepLastController = TextEditingController(
      text: rule?.keepLast?.toString() ?? '',
    );
    _priorityController = TextEditingController(
      text: rule?.priority?.toString() ?? '',
    );
    _startEarlyController = TextEditingController(
      text: rule?.startEarlySeconds?.toString() ?? '',
    );
    _endLateController = TextEditingController(
      text: rule?.endLateSeconds?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _keepLastController.dispose();
    _priorityController.dispose();
    _startEarlyController.dispose();
    _endLateController.dispose();
    super.dispose();
  }

  int? _parseInt(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  DvrSeriesRuleOptions _buildOptions() {
    return DvrSeriesRuleOptions(
      channelId: _selectedChannelId,
      matchMode: _selectedMatchMode,
      seriesMode: _selectedSeriesMode,
      keepLast: _parseInt(_keepLastController),
      priority: _parseInt(_priorityController),
      startEarlySeconds: _parseInt(_startEarlyController),
      endLateSeconds: _parseInt(_endLateController),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final show = widget.show;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.dvrSeriesOptions,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              DpadFocusable(
                onSelect: () => Navigator.of(context).pop(),
                effects: kStadiumFocusEffects,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Channel picker ──────────────────────────────────────
                  if (show.channelCount > 1) ...[
                    _SectionLabel(label: l10n.dvrSeriesChannel),
                    const SizedBox(height: 8),
                    DpadRegion(
                      memoryKey: 'dvr-series-rule-sheet/channels',
                      horizontalEdge: DpadEdgeBehavior.stop,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // "Any channel" pill
                          _ChannelPill(
                            label: l10n.dvrSeriesAnyChannel,
                            isSelected: _selectedChannelId == null,
                            onSelect: () =>
                                setState(() => _selectedChannelId = null),
                          ),
                          // Per-channel pills
                          for (final channel in show.channels)
                            _ChannelPill(
                              label:
                                  channel.channelName ??
                                  'Ch ${channel.channelId}',
                              isSelected:
                                  _selectedChannelId == channel.channelId,
                              onSelect: () => setState(
                                () => _selectedChannelId = channel.channelId,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Series mode ─────────────────────────────────────────
                  _SectionLabel(label: l10n.dvrSeriesMode),
                  const SizedBox(height: 8),
                  DpadRegion(
                    memoryKey: 'dvr-series-rule-sheet/series-mode',
                    horizontalEdge: DpadEdgeBehavior.stop,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ModePill<DvrSeriesMode?>(
                          label: l10n.dvrSeriesModeUseDefault,
                          value: null,
                          selectedValue: _selectedSeriesMode,
                          onSelect: (v) =>
                              setState(() => _selectedSeriesMode = v),
                        ),
                        _ModePill<DvrSeriesMode?>(
                          label: l10n.dvrSeriesModeAll,
                          value: DvrSeriesMode.all,
                          selectedValue: _selectedSeriesMode,
                          onSelect: (v) =>
                              setState(() => _selectedSeriesMode = v),
                        ),
                        _ModePill<DvrSeriesMode?>(
                          label: l10n.dvrSeriesModeNewFlag,
                          value: DvrSeriesMode.newFlag,
                          selectedValue: _selectedSeriesMode,
                          onSelect: (v) =>
                              setState(() => _selectedSeriesMode = v),
                        ),
                        _ModePill<DvrSeriesMode?>(
                          label: l10n.dvrSeriesModeUniqueSe,
                          value: DvrSeriesMode.uniqueSe,
                          selectedValue: _selectedSeriesMode,
                          onSelect: (v) =>
                              setState(() => _selectedSeriesMode = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Match mode ──────────────────────────────────────────
                  _SectionLabel(label: l10n.dvrSeriesMatchMode),
                  const SizedBox(height: 8),
                  DpadRegion(
                    memoryKey: 'dvr-series-rule-sheet/match-mode',
                    horizontalEdge: DpadEdgeBehavior.stop,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ModePill<DvrMatchMode>(
                          label: l10n.dvrSeriesMatchModeContains,
                          value: DvrMatchMode.contains,
                          selectedValue: _selectedMatchMode,
                          onSelect: (v) =>
                              setState(() => _selectedMatchMode = v),
                        ),
                        _ModePill<DvrMatchMode>(
                          label: l10n.dvrSeriesMatchModeExact,
                          value: DvrMatchMode.exact,
                          selectedValue: _selectedMatchMode,
                          onSelect: (v) =>
                              setState(() => _selectedMatchMode = v),
                        ),
                        _ModePill<DvrMatchMode>(
                          label: l10n.dvrSeriesMatchModeStartsWith,
                          value: DvrMatchMode.startsWith,
                          selectedValue: _selectedMatchMode,
                          onSelect: (v) =>
                              setState(() => _selectedMatchMode = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Numeric fields row ─────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Keep last
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesKeepLast,
                          hint: l10n.dvrSeriesUseDefault,
                          controller: _keepLastController,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Priority
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesPriority,
                          hint: '50',
                          controller: _priorityController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Start early
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesStartEarly,
                          hint: l10n.dvrSeriesUseDefault,
                          controller: _startEarlyController,
                          suffix: l10n.dvrSeriesSecondsSuffix,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // End late
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesEndLate,
                          hint: l10n.dvrSeriesUseDefault,
                          controller: _endLateController,
                          suffix: l10n.dvrSeriesSecondsSuffix,
                        ),
                      ),
                    ],
                  ),

                  // ── Inline warning ─────────────────────────────────────
                  if (_isAllEpisodesWarningVisible) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.dvrSeriesAllEpisodesWarning,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Action row ────────────────────────────────────────────────
          DpadRegion(
            memoryKey: 'dvr-series-rule-sheet/actions',
            horizontalEdge: DpadEdgeBehavior.stop,
            child: OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                AppButton(
                  label: l10n.dvrSeriesCancel,
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                AppButton(
                  label: l10n.dvrSeriesSave,
                  variant: AppButtonVariant.primary,
                  onPressed: () => Navigator.of(context).pop(_buildOptions()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A simple section-header label.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A focusable pill for channel selection.
class _ChannelPill extends StatelessWidget {
  const _ChannelPill({
    required this.label,
    required this.isSelected,
    required this.onSelect,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DpadInkWell(
      borderRadius: BorderRadius.circular(50),
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// A focusable pill for enum-mode selection (series mode, match mode).
class _ModePill<T> extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onSelect,
  });

  final String label;
  final T value;
  final T selectedValue;
  final ValueChanged<T> onSelect;

  bool get _isSelected => value == selectedValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DpadInkWell(
      borderRadius: BorderRadius.circular(50),
      color: _isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      onTap: () => onSelect(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: _isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: _isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

/// A labeled number input field for the sheet.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.hint,
    required this.controller,
    this.suffix,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 40,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
            ],
            decoration: InputDecoration(
              hintText: hint,
              suffixText: suffix,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
