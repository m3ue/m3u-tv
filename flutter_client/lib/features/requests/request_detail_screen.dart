import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

// M3 buttons use StadiumBorder — a large radius keeps the D-pad focus
// border matching the pill shape regardless of the button's height. Mirrors
// _kStadiumEffect in settings_screen.dart.
const _kStadiumEffect = [
  GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

/// Detail screen for a single `request_search` result — mirrors
/// VodDetailsScreen/AIOStreamsDetailScreen's backdrop layout (same metadata
/// chip row, same wide/narrow breakpoint), since all the metadata needed is
/// already present on [result] from the search response — no separate fetch.
class RequestDetailScreen extends ConsumerStatefulWidget {
  const RequestDetailScreen({
    super.key,
    required this.result,
    required this.onSubmit,
  });

  final ContentRequestSearchResult result;
  final Future<MediaRequestSummary> Function({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
  })
  onSubmit;

  @override
  ConsumerState<RequestDetailScreen> createState() =>
      _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _isSubmitting = false;

  /// Seasons the guest wants to request, initialized to every season the
  /// library doesn't already have a file for — matching Sonarr's own
  /// "monitor missing" default so a plain tap of Request just fills gaps.
  late final Set<int> _selectedSeasons = widget.result.seasons
      .where((season) => !season.hasFile)
      .map((season) => season.seasonNumber)
      .toSet();

  String _errorMessage(Object error) =>
      error is XtreamRequestException ? error.message : error.toString();

  void _toggleSeason(int seasonNumber) {
    setState(() {
      if (!_selectedSeasons.remove(seasonNumber)) {
        _selectedSeasons.add(seasonNumber);
      }
    });
  }

  void _selectAllSeasons() {
    setState(() {
      _selectedSeasons
        ..clear()
        ..addAll(widget.result.seasons.map((season) => season.seasonNumber));
    });
  }

  void _clearAllSeasons() {
    setState(_selectedSeasons.clear);
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final result = widget.result;
    setState(() => _isSubmitting = true);
    try {
      final request = await widget.onSubmit(
        type: result.type,
        integrationId: result.integrationId,
        externalId: result.externalId,
        seasons: result.type == 'series'
            ? (_selectedSeasons.toList()..sort())
            : null,
      );
      if (!mounted) return;
      final message = request.status == MediaRequestStatus.pendingApproval
          ? l.requestsSubmittedPendingApproval(result.title)
          : l.requestsSubmitted(result.title);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.requestsSubmitFailed(result.title, _errorMessage(error)),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myRequests = ref.watch(mediaRequestsProvider);
    final existing = myRequests
        .where(
          (request) =>
              request.type == widget.result.type &&
              request.externalId == widget.result.externalId &&
              (request.status == MediaRequestStatus.pendingApproval ||
                  request.status == MediaRequestStatus.approved ||
                  request.status == MediaRequestStatus.completed),
        )
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.result.title),
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: DpadFocusable(
            onSelect: () => Navigator.of(context).maybePop(),
            effects: const [
              GradientBorderEffect(
                borderRadius: BorderRadius.all(Radius.circular(50)),
              ),
            ],
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: _Body(
        result: widget.result,
        existing: existing,
        isSubmitting: _isSubmitting,
        selectedSeasons: _selectedSeasons,
        onSubmit: () => unawaited(_submit()),
        onToggleSeason: _toggleSeason,
        onSelectAllSeasons: _selectAllSeasons,
        onClearAllSeasons: _clearAllSeasons,
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _Body extends StatelessWidget {
  const _Body({
    required this.result,
    required this.existing,
    required this.isSubmitting,
    required this.selectedSeasons,
    required this.onSubmit,
    required this.onToggleSeason,
    required this.onSelectAllSeasons,
    required this.onClearAllSeasons,
  });

  final ContentRequestSearchResult result;
  final MediaRequestSummary? existing;
  final bool isSubmitting;
  final Set<int> selectedSeasons;
  final VoidCallback onSubmit;
  final ValueChanged<int> onToggleSeason;
  final VoidCallback onSelectAllSeasons;
  final VoidCallback onClearAllSeasons;

  /// The season picker only makes sense while a request can still be
  /// submitted — once approved/rejected/completed or already in the
  /// library, the selection is moot.
  bool get _showSeasonPicker =>
      result.type == 'series' &&
      result.seasons.isNotEmpty &&
      existing == null &&
      !result.alreadyAvailable;

  static const double _wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return _buildNarrow(context);
        }
        return _buildWide(context);
      },
    );
  }

  Widget _buildWide(BuildContext context) {
    final theme = Theme.of(context);
    final backdrop = result.fanart;
    final content = Padding(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          SizedBox(
            width: 220,
            child: AspectRatio(
              aspectRatio: 0.68,
              child: Hero(
                tag: 'request_poster_${result.type}_${result.externalId}',
                child: ResilientMediaImage(
                  imageUrl: result.poster,
                  fallbackIcon: result.type == 'series'
                      ? Icons.tv
                      : Icons.movie,
                  borderRadius: MediaBrowsingMetrics.cardRadius,
                  fallbackTitle: result.title,
                ),
              ),
            ),
          ),
          const SizedBox(width: MediaBrowsingMetrics.pagePadding),
          Expanded(
            child: SingleChildScrollView(
              child: _infoColumn(context, theme),
            ),
          ),
        ],
      ),
    );

    if (backdrop == null) return content;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(backdrop, fit: BoxFit.cover),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.85),
                theme.colorScheme.surface,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.sizeOf(context).height * 0.1,
            ),
            child: content,
          ),
        ),
      ],
    );
  }

  Widget _buildNarrow(BuildContext context) {
    final theme = Theme.of(context);
    final backdrop = result.fanart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null)
                Image.network(backdrop, fit: BoxFit.cover)
              else
                ResilientMediaImage(
                  imageUrl: result.poster,
                  fallbackIcon: result.type == 'series'
                      ? Icons.tv
                      : Icons.movie,
                  borderRadius: 0,
                  fallbackTitle: result.title,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, theme.colorScheme.surface],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                bottom: 16,
                child: SizedBox(
                  width: 80,
                  child: AspectRatio(
                    aspectRatio: 0.68,
                    child: Hero(
                      tag: 'request_poster_${result.type}_${result.externalId}',
                      child: ResilientMediaImage(
                        imageUrl: result.poster,
                        fallbackIcon: result.type == 'series'
                            ? Icons.tv
                            : Icons.movie,
                        fallbackTitle: result.title,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _infoColumn(context, theme, fullWidthButton: true),
          ),
        ),
      ],
    );
  }

  Widget _infoColumn(
    BuildContext context,
    ThemeData theme, {
    bool fullWidthButton = false,
  }) {
    final l = AppLocalizations.of(context);
    final rating = result.rating;
    final button = _actionButton(l, fullWidth: fullWidthButton);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(result.title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: MediaBrowsingMetrics.itemGap),
        Wrap(
          spacing: MediaBrowsingMetrics.itemGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            if (result.year != null) _MetadataChip(label: result.year!),
            if (result.certification != null)
              _MetadataChip(label: result.certification!),
            if (rating != null)
              _MetadataChip(
                label: rating.source == null
                    ? '★ ${rating.value.toStringAsFixed(1)}'
                    : '★ ${rating.value.toStringAsFixed(1)} ${rating.source!.toUpperCase()}',
              ),
            if (result.runtimeMinutes != null)
              _MetadataChip(label: _formatRuntime(result.runtimeMinutes!)),
            ...result.genres
                .take(3)
                .map((genre) => _MetadataChip(label: genre)),
          ],
        ),
        if (_showSeasonPicker) ...[
          const SizedBox(height: MediaBrowsingMetrics.contentPadding),
          _SeasonsSection(
            seasons: result.seasons,
            selectedSeasons: selectedSeasons,
            onToggleSeason: onToggleSeason,
          ),
        ],
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        _actionRow(l, button, fullWidthButton: fullWidthButton),
        const SizedBox(height: MediaBrowsingMetrics.pagePadding),
        if (result.overview != null && result.overview!.isNotEmpty)
          Text(
            result.overview!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// Places Select All/Clear right next to the Request button — rather than
  /// up by the season chips — so keyboard/D-pad users hit them in the same
  /// focus neighborhood as the action they actually affect.
  Widget _actionRow(
    AppLocalizations l,
    Widget button, {
    required bool fullWidthButton,
  }) {
    if (!_showSeasonPicker) {
      return fullWidthButton
          ? SizedBox(width: double.infinity, child: button)
          : button;
    }

    final selectAll = DpadFocusable(
      onSelect: onSelectAllSeasons,
      effects: _kStadiumEffect,
      child: FilledButton.tonal(
        onPressed: onSelectAllSeasons,
        child: Text(l.requestsSelectAllSeasons),
      ),
    );
    final clear = DpadFocusable(
      onSelect: onClearAllSeasons,
      effects: _kStadiumEffect,
      child: FilledButton.tonal(
        onPressed: onClearAllSeasons,
        child: Text(l.requestsClearSeasons),
      ),
    );

    if (fullWidthButton) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          button,
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          Row(
            children: [
              Expanded(child: selectAll),
              const SizedBox(width: MediaBrowsingMetrics.chipGap),
              Expanded(child: clear),
            ],
          ),
        ],
      );
    }

    return Wrap(
      spacing: MediaBrowsingMetrics.chipGap,
      runSpacing: MediaBrowsingMetrics.chipGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [button, selectAll, clear],
    );
  }

  Widget _actionButton(AppLocalizations l, {required bool fullWidth}) {
    if (result.alreadyAvailable) {
      return DpadFocusable(
        effects: _kStadiumEffect,
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(l.requestsAlreadyAvailable),
        ),
      );
    }
    final request = existing;
    if (request != null) {
      return DpadFocusable(
        effects: _kStadiumEffect,
        child: FilledButton.tonalIcon(
          onPressed: null,
          icon: const Icon(Icons.check),
          label: Text(_statusLabel(l, request.status)),
        ),
      );
    }
    final noSeasonsSelected = _showSeasonPicker && selectedSeasons.isEmpty;
    final onPressed = isSubmitting || noSeasonsSelected ? null : onSubmit;
    return DpadFocusable(
      autofocus: true,
      onSelect: onPressed,
      effects: _kStadiumEffect,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(l.requestsRequestButton),
      ),
    );
  }

  String _statusLabel(AppLocalizations l, MediaRequestStatus status) =>
      switch (status) {
        MediaRequestStatus.pendingApproval => l.requestsStatusPendingApproval,
        MediaRequestStatus.approved => l.requestsStatusApproved,
        MediaRequestStatus.rejected => l.requestsStatusRejected,
        MediaRequestStatus.completed => l.requestsStatusCompleted,
        MediaRequestStatus.unknown => l.requestsStatusUnknown,
      };

  String _formatRuntime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0 && mins > 0) return '${hours}h ${mins}m';
    if (hours > 0) return '${hours}h';
    return '${mins}m';
  }
}

// ---------------------------------------------------------------------------
// Season picker — lets the guest request every season, or just the ones
// missing from the library (the default selection).
// ---------------------------------------------------------------------------

class _SeasonsSection extends StatelessWidget {
  const _SeasonsSection({
    required this.seasons,
    required this.selectedSeasons,
    required this.onToggleSeason,
  });

  final List<ContentRequestSeason> seasons;
  final Set<int> selectedSeasons;
  final ValueChanged<int> onToggleSeason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.requestsSeasonsHeading, style: theme.textTheme.titleMedium),
        const SizedBox(height: MediaBrowsingMetrics.chipGap),
        Wrap(
          spacing: MediaBrowsingMetrics.chipGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            for (final season in seasons)
              _SeasonToggle(
                label: l.homeSeason(season.seasonNumber),
                isSelected: selectedSeasons.contains(season.seasonNumber),
                hasFile: season.hasFile,
                onTap: () => onToggleSeason(season.seasonNumber),
              ),
          ],
        ),
      ],
    );
  }
}

class _SeasonToggle extends StatelessWidget {
  const _SeasonToggle({
    required this.label,
    required this.isSelected,
    required this.hasFile,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool hasFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = isSelected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return DpadInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.chipRadius),
      color: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (hasFile) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle, size: 14, color: colorScheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chip widget (mirrors _MetadataChip in vod_details_screen.dart /
// aiostreams_detail_screen.dart)
// ---------------------------------------------------------------------------

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant),
    );
  }
}
