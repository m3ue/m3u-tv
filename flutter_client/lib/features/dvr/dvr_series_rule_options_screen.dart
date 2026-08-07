import 'dart:io' show Platform;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Mirrors the tvOS/Android-TV detection in `device_type_resolver.dart`
/// (`Platform.operatingSystem == 'tvos'` / `NavigationMode.directional`),
/// duplicated narrowly here rather than importing `app_shell.dart`'s
/// `DeviceType`/`shouldUseSidebar` — that file imports this one transitively
/// (via `dvr_recordings_screen.dart`), so importing it back would cycle.
bool _isRemoteDrivenEnvironment(BuildContext context) {
  if (!kIsWeb && Platform.operatingSystem == 'tvos') {
    return true;
  }
  return MediaQuery.maybeNavigationModeOf(context) ==
      NavigationMode.directional;
}

const String _anyChannelTabId = '__any__';

/// Opens the series-rule options screen and returns the picked
/// [DvrSeriesRuleOptions] on Save, or null if the user backs out without
/// saving.
///
/// Pushed on the *nearest* navigator — the current tab/detail branch's
/// nested one, not the true app root — so the new page stays inside
/// AppShell's `_buildTvLayout` Stack (the app background gradient, the
/// macOS titlebar inset, and the tvOS overscan-padding removal are all
/// applied once around that branch content, not per-screen). Using
/// `rootNavigator: true` here previously escaped that Stack entirely,
/// which is why the page had no background, sat under the macOS traffic
/// lights, and had a stray top gap on tvOS.
///
/// The [show] parameter carries `channels`, `channelCount`, `nextAiringAt`,
/// and `recentEpisodes` — used to populate the channel picker and compute
/// the default channel selection.
///
/// When [initialRule] is provided the screen pre-fills every field from the
/// existing rule (edit mode). The channel picker is driven by [show]; for
/// the DVR screen's edit path callers construct a minimal [EpgShow] from the
/// rule (channelCount 1 / no recent episodes) so the picker stays hidden and
/// the rule's channel is preserved unless the caller intends otherwise.
Future<DvrSeriesRuleOptions?> openDvrSeriesRuleOptions(
  BuildContext context, {
  required EpgShow show,
  DvrSeriesRule? initialRule,
}) {
  return Navigator.of(context).push<DvrSeriesRuleOptions>(
    PageRouteBuilder<DvrSeriesRuleOptions>(
      // Mirrors go_router_config.dart's `_slidePage`: an opaque backing
      // color (the shared TV-layout gradient's dominant end tone) plus a
      // pure slide, no fade. Without this, a raw MaterialPageRoute uses
      // Material 3's default fade transition over a transparent Scaffold
      // (scaffoldBackgroundColor is transparent app-wide, relying on
      // AppShell's shared gradient to show through) and briefly renders
      // see-through during the push.
      pageBuilder: (context, animation, secondaryAnimation) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF09090b)),
          DvrSeriesRuleOptionsScreen(show: show, initialRule: initialRule),
        ],
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
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

class DvrSeriesRuleOptionsScreen extends StatefulWidget {
  const DvrSeriesRuleOptionsScreen({
    super.key,
    required this.show,
    this.initialRule,
  });

  final EpgShow show;
  final DvrSeriesRule? initialRule;

  @override
  State<DvrSeriesRuleOptionsScreen> createState() =>
      _DvrSeriesRuleOptionsScreenState();
}

class _DvrSeriesRuleOptionsScreenState
    extends State<DvrSeriesRuleOptionsScreen> {
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

    return Scaffold(
      resizeToAvoidBottomInset: !_isRemoteDrivenEnvironment(context),
      appBar: AppBar(
        title: Text(l10n.dvrSeriesOptionsFor(show.displayTitle)),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: AppIconButton(
            icon: Icons.arrow_back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Channel picker ──────────────────────────────────────
            if (show.channelCount > 1) ...[
              _SectionLabel(label: l10n.dvrSeriesChannel),
              const SizedBox(height: 8),
              // Zero horizontal padding here (vs. the bar's own default
              // 16px, meant for full-bleed use on Series/VOD) so it lines
              // up flush with sibling form fields inside this page's own
              // 24px page padding instead of doubling up.
              ScrollableCategoryBar(
                padding: const EdgeInsets.symmetric(vertical: 8),
                selectedId: _selectedChannelId?.toString() ?? _anyChannelTabId,
                tabs: [
                  CategoryTabData(
                    id: _anyChannelTabId,
                    name: l10n.dvrSeriesAnyChannel,
                  ),
                  for (final channel in show.channels)
                    CategoryTabData(
                      id: channel.channelId.toString(),
                      name: channel.channelName ?? 'Ch ${channel.channelId}',
                    ),
                ],
                onSelected: (id) => setState(
                  () => _selectedChannelId = id == _anyChannelTabId
                      ? null
                      : int.parse(id),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Series mode ─────────────────────────────────────────
            _SectionLabel(label: l10n.dvrSeriesMode),
            const SizedBox(height: 8),
            DpadRegion(
              memoryKey: 'dvr-series-rule-options/series-mode',
              horizontalEdge: DpadEdgeBehavior.stop,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // "Use Default" only makes sense on create: update_dvr_series_rule
                  // omits absent fields to mean "leave unchanged", so there is no way
                  // to tell the server "reset this field to the DVR default" once a
                  // rule already has an explicit series_mode stored.
                  if (widget.initialRule == null)
                    CategoryFilterChip(
                      label: l10n.dvrSeriesModeUseDefault,
                      isSelected: _selectedSeriesMode == null,
                      onTap: () => setState(() => _selectedSeriesMode = null),
                    ),
                  CategoryFilterChip(
                    label: l10n.dvrSeriesModeAll,
                    isSelected: _selectedSeriesMode == DvrSeriesMode.all,
                    onTap: () =>
                        setState(() => _selectedSeriesMode = DvrSeriesMode.all),
                  ),
                  CategoryFilterChip(
                    label: l10n.dvrSeriesModeNewFlag,
                    isSelected: _selectedSeriesMode == DvrSeriesMode.newFlag,
                    onTap: () => setState(
                      () => _selectedSeriesMode = DvrSeriesMode.newFlag,
                    ),
                  ),
                  CategoryFilterChip(
                    label: l10n.dvrSeriesModeUniqueSe,
                    isSelected: _selectedSeriesMode == DvrSeriesMode.uniqueSe,
                    onTap: () => setState(
                      () => _selectedSeriesMode = DvrSeriesMode.uniqueSe,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Match mode ──────────────────────────────────────────
            _SectionLabel(label: l10n.dvrSeriesMatchMode),
            const SizedBox(height: 8),
            DpadRegion(
              memoryKey: 'dvr-series-rule-options/match-mode',
              horizontalEdge: DpadEdgeBehavior.stop,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CategoryFilterChip(
                    label: l10n.dvrSeriesMatchModeContains,
                    isSelected: _selectedMatchMode == DvrMatchMode.contains,
                    onTap: () => setState(
                      () => _selectedMatchMode = DvrMatchMode.contains,
                    ),
                  ),
                  CategoryFilterChip(
                    label: l10n.dvrSeriesMatchModeExact,
                    isSelected: _selectedMatchMode == DvrMatchMode.exact,
                    onTap: () =>
                        setState(() => _selectedMatchMode = DvrMatchMode.exact),
                  ),
                  CategoryFilterChip(
                    label: l10n.dvrSeriesMatchModeStartsWith,
                    isSelected: _selectedMatchMode == DvrMatchMode.startsWith,
                    onTap: () => setState(
                      () => _selectedMatchMode = DvrMatchMode.startsWith,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Numeric fields ──────────────────────────────────────
            // Grouped in its own DpadRegion like every other section above
            // — without one, these fields sit outside any region's
            // candidate set and d-pad down/up navigation from the
            // match-mode pills to the action row can skip over them
            // instead of landing here.
            DpadRegion(
              memoryKey: 'dvr-series-rule-options/numeric-fields',
              horizontalEdge: DpadEdgeBehavior.stop,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesKeepLast,
                          hint: l10n.dvrSeriesUseDefault,
                          controller: _keepLastController,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                      Expanded(
                        child: _NumberField(
                          label: l10n.dvrSeriesStartEarly,
                          hint: l10n.dvrSeriesUseDefault,
                          controller: _startEarlyController,
                          suffix: l10n.dvrSeriesSecondsSuffix,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                ],
              ),
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
            const SizedBox(height: 24),

            // ── Action row ────────────────────────────────────────────────
            DpadRegion(
              memoryKey: 'dvr-series-rule-options/actions',
              horizontalEdge: DpadEdgeBehavior.stop,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: l10n.dvrSeriesCancel,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: l10n.dvrSeriesSave,
                    variant: AppButtonVariant.primaryInverted,
                    onPressed: () => Navigator.of(context).pop(_buildOptions()),
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

/// A simple section-header label.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style:
          Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

/// A labeled number input field for the screen. Matches the standard input
/// look used elsewhere (e.g. the Settings viewer-name field): labelText
/// inside the decoration, plain OutlineInputBorder, no isDense/custom
/// height/custom radius.
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
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*'))],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
