import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/formatters.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/movie_detail_body.dart';

/// Detail screen for a single `request_search` result — built directly on
/// [MovieDetailBody], the same shared body VOD/AIOStreams movie details use
/// (poster/backdrop hero, colour-match fade-in, primary button styling,
/// synopsis measure). A change to that shared body shows up here too instead
/// of needing to be copied in - only the request-specific bits (season
/// picker, submit/status button state) live in this file. All the metadata
/// needed is already present on [result] from the search response - no
/// separate fetch.
class RequestDetailScreen extends ConsumerStatefulWidget {
  const RequestDetailScreen({
    super.key,
    required this.result,
    required this.onSubmit,
    this.isOwnerCurrent = true,
  });

  final ContentRequestSearchResult result;
  final Future<MediaRequestSummary> Function({
    required String type,
    required int integrationId,
    required String externalId,
    List<int>? seasons,
  })
  onSubmit;
  final bool isOwnerCurrent;

  @override
  ConsumerState<RequestDetailScreen> createState() =>
      _RequestDetailScreenState();
}

class _RequestDetailScreenState extends ConsumerState<RequestDetailScreen> {
  bool _isSubmitting = false;

  /// Seasons the guest wants to request, initialized to every season the
  /// library doesn't already have a file for — matching Sonarr's own
  /// "monitor missing" default so a plain tap of Request just fills gaps.
  /// Season 0 ("Specials") is excluded from that default, same as the
  /// m3u-editor web UI (ArrSearch::openDetail) — guests can still opt in
  /// via its chip.
  late final Set<int> _selectedSeasons = widget.result.seasons
      .where((season) => !season.hasFile && season.seasonNumber != 0)
      .map((season) => season.seasonNumber)
      .toSet();

  Color? _dominantColor;

  /// True once the palette extraction has resolved (with a colour or not).
  /// Gates the hero's backdrop reveal so the art and its colour-match fade
  /// in together - see VodDetailsScreen's matching field.
  bool _colorMatchResolved = false;

  @override
  void initState() {
    super.initState();
    final result = widget.result;
    unawaited(_resolveDominantColor(result.fanart ?? result.poster));
  }

  Future<void> _resolveDominantColor(String? url) async {
    final color = await resolveDominantBackdropColor(url);
    if (!mounted) return;
    setState(() {
      if (color != null) _dominantColor = color;
      _colorMatchResolved = true;
    });
  }

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
    if (!widget.isOwnerCurrent) return;
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
    if (!widget.isOwnerCurrent) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final result = widget.result;
    final myRequests = ref.watch(mediaRequestsProvider);
    final existing = myRequests
        .where(
          (request) =>
              request.type == result.type &&
              request.externalId == result.externalId &&
              (request.status == MediaRequestStatus.pendingApproval ||
                  request.status == MediaRequestStatus.approved ||
                  request.status == MediaRequestStatus.completed),
        )
        .firstOrNull;

    final showSeasonPicker =
        result.type == 'series' &&
        result.seasons.isNotEmpty &&
        existing == null &&
        !result.alreadyAvailable;
    final rating = result.rating;
    final chips = [
      if (result.year != null) result.year!,
      if (result.certification != null) result.certification!,
      if (rating != null) formatRating(rating.value, source: rating.source),
      if (result.runtimeMinutes != null)
        formatRuntime(Duration(minutes: result.runtimeMinutes!)),
      ...result.genres.take(3),
    ];

    return ItemDetailScaffold(
      title: result.title,
      body: MovieDetailBody(
        name: result.title,
        posterUrl: result.poster,
        backdropUrl: result.fanart,
        fallbackIcon: result.type == 'series' ? Icons.tv : Icons.movie,
        chips: chips,
        plot: result.overview,
        credits: const [],
        castSemanticLabel: '',
        primaryButtonLabel: _primaryLabel(l, existing),
        primaryIcon: _primaryIcon(existing),
        onPrimary: _primaryAction(
          existing: existing,
          showSeasonPicker: showSeasonPicker,
        ),
        isLoading: _isSubmitting,
        dominantColor: _dominantColor,
        colorMatchReady: _colorMatchResolved,
        extraContent: !showSeasonPicker
            ? null
            : _SeasonsSection(
                seasons: result.seasons,
                selectedSeasons: _selectedSeasons,
                onToggleSeason: _toggleSeason,
                onSelectAll: _selectAllSeasons,
                onClear: _clearAllSeasons,
              ),
      ),
    );
  }

  String _primaryLabel(AppLocalizations l, MediaRequestSummary? existing) {
    if (widget.result.alreadyAvailable) return l.requestsAlreadyAvailable;
    if (existing != null) return _statusLabel(l, existing.status);
    return l.requestsRequestButton;
  }

  IconData _primaryIcon(MediaRequestSummary? existing) {
    if (widget.result.alreadyAvailable) return Icons.check_circle_outline;
    if (existing != null) return Icons.check;
    return Icons.add;
  }

  VoidCallback? _primaryAction({
    required MediaRequestSummary? existing,
    required bool showSeasonPicker,
  }) {
    if (widget.result.alreadyAvailable || existing != null) return null;
    final noSeasonsSelected = showSeasonPicker && _selectedSeasons.isEmpty;
    if (noSeasonsSelected) return null;
    return () => unawaited(_submit());
  }

  String _statusLabel(AppLocalizations l, MediaRequestStatus status) =>
      switch (status) {
        MediaRequestStatus.pendingApproval => l.requestsStatusPendingApproval,
        MediaRequestStatus.approved => l.requestsStatusApproved,
        MediaRequestStatus.rejected => l.requestsStatusRejected,
        MediaRequestStatus.completed => l.requestsStatusCompleted,
        MediaRequestStatus.unknown => l.requestsStatusUnknown,
      };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ---------------------------------------------------------------------------
// Season picker — lets the guest request every season, or just the ones
// missing from the library (the default selection). This is a multi-select
// "which missing seasons to request" affordance for a title not yet in the
// library, distinct in purpose from series_detail_widgets.dart's season
// picker (single-select, for browsing a title already owned) — it is not a
// drift case, just a different interaction over the same "season" concept.
// ---------------------------------------------------------------------------

class _SeasonsSection extends StatelessWidget {
  const _SeasonsSection({
    required this.seasons,
    required this.selectedSeasons,
    required this.onToggleSeason,
    required this.onSelectAll,
    required this.onClear,
  });

  final List<ContentRequestSeason> seasons;
  final Set<int> selectedSeasons;
  final ValueChanged<int> onToggleSeason;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

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
                label: season.seasonNumber == 0
                    ? l.requestsSeasonSpecials
                    : l.homeSeason(season.seasonNumber),
                isSelected: selectedSeasons.contains(season.seasonNumber),
                hasFile: season.hasFile,
                onTap: () => onToggleSeason(season.seasonNumber),
              ),
          ],
        ),
        const SizedBox(height: MediaBrowsingMetrics.contentPadding),
        Wrap(
          spacing: MediaBrowsingMetrics.chipGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            AppButton(
              label: l.requestsSelectAllSeasons,
              onPressed: onSelectAll,
            ),
            AppButton(label: l.requestsClearSeasons, onPressed: onClear),
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
