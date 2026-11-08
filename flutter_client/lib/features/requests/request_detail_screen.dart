import 'dart:async';

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
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/movie_detail_body.dart';
import 'package:m3u_tv/shared/selectable_chip.dart';
import 'package:material_ui/material_ui.dart';

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
  /// Statuses that mean this guest already asked an integration for the
  /// title (the button shows the status instead of Request).
  static const Set<MediaRequestStatus> _requestedStatuses =
      <MediaRequestStatus>{
        MediaRequestStatus.pendingApproval,
        MediaRequestStatus.approved,
        MediaRequestStatus.completed,
      };

  bool _isSubmitting = false;

  /// The integration to request from. Starts on the first one that can
  /// still take the request, so one that already has the title doesn't
  /// hide another that could (#137).
  late int _providerId = _initialProviderId();

  /// Seasons the guest wants to request from the selected integration,
  /// initialized to every season it doesn't already have a file for —
  /// matching Sonarr's own "monitor missing" default so a plain tap of
  /// Request just fills gaps. Season 0 ("Specials") is excluded from that
  /// default, same as the m3u-editor web UI (ArrSearch::openDetail) — guests
  /// can still opt in via its chip.
  late Set<int> _selectedSeasons = _defaultSeasons(_provider);

  int _initialProviderId() {
    final requestable = widget.result.requestableProviders(
      ref.read(mediaRequestsProvider),
      _requestedStatuses,
    );
    return requestable.isNotEmpty
        ? requestable.first.integrationId
        : widget.result.integrationId;
  }

  ContentRequestProvider get _provider {
    final providers = widget.result.providers;
    for (final provider in providers) {
      if (provider.integrationId == _providerId) return provider;
    }
    return providers.first;
  }

  static Set<int> _defaultSeasons(ContentRequestProvider provider) => provider
      .seasons
      .where((season) => !season.hasFile && season.seasonNumber != 0)
      .map((season) => season.seasonNumber)
      .toSet();

  void _selectProvider(ContentRequestProvider provider) {
    if (provider.integrationId == _providerId) return;
    setState(() {
      _providerId = provider.integrationId;
      _selectedSeasons = _defaultSeasons(provider);
    });
  }

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
        ..addAll(_provider.seasons.map((season) => season.seasonNumber));
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
        integrationId: _provider.integrationId,
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
    final provider = _provider;
    final existing = result.requestFor(
      provider,
      myRequests,
      _requestedStatuses,
    );
    final available = provider.alreadyAvailable;
    final providers = result.providers;

    final showSeasonPicker =
        result.type == 'series' &&
        provider.seasons.isNotEmpty &&
        existing == null &&
        !available;
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
        clearLogoUrl: result.clearLogo,
        fallbackIcon: result.type == 'series' ? Icons.tv : Icons.movie,
        chips: chips,
        plot: result.overview,
        credits: [
          if (result.directors.isNotEmpty)
            MetaCreditLine(
              label: l.vodDirector,
              value: result.directors.join(', '),
            ),
        ],
        richCast: result.castList,
        castSemanticLabel: l.vodCast,
        primaryButtonLabel: _primaryLabel(l, existing, available: available),
        primaryIcon: _primaryIcon(existing, available: available),
        onPrimary: _primaryAction(
          existing: existing,
          available: available,
          showSeasonPicker: showSeasonPicker,
        ),
        isLoading: _isSubmitting,
        dominantColor: _dominantColor,
        colorMatchReady: _colorMatchResolved,
        extraContent: providers.length < 2 && !showSeasonPicker
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (providers.length > 1)
                    _ProviderPicker(
                      providers: providers,
                      selectedId: provider.integrationId,
                      onSelect: _selectProvider,
                    ),
                  if (providers.length > 1 && showSeasonPicker)
                    const SizedBox(
                      height: MediaBrowsingMetrics.contentPadding,
                    ),
                  if (showSeasonPicker)
                    _SeasonsSection(
                      // Keyed so switching integration rebuilds the toggles
                      // for that integration's own season list.
                      key: ValueKey<int>(provider.integrationId),
                      seasons: provider.seasons,
                      selectedSeasons: _selectedSeasons,
                      onToggleSeason: _toggleSeason,
                      onSelectAll: _selectAllSeasons,
                      onClear: _clearAllSeasons,
                    ),
                ],
              ),
      ),
    );
  }

  String _primaryLabel(
    AppLocalizations l,
    MediaRequestSummary? existing, {
    required bool available,
  }) {
    if (available) return l.requestsAlreadyAvailable;
    if (existing != null) return _statusLabel(l, existing.status);
    return l.requestsRequestButton;
  }

  IconData _primaryIcon(
    MediaRequestSummary? existing, {
    required bool available,
  }) {
    if (available) return Icons.check_circle_outline;
    if (existing != null) return Icons.check;
    return Icons.add;
  }

  VoidCallback? _primaryAction({
    required MediaRequestSummary? existing,
    required bool available,
    required bool showSeasonPicker,
  }) {
    if (available || existing != null) return null;
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

/// "Request from" chips, one per integration that returned the title. Only
/// shown when there is more than one; the button above reflects the selected
/// integration's own state (available, requested, or Request).
class _ProviderPicker extends StatelessWidget {
  const _ProviderPicker({
    required this.providers,
    required this.selectedId,
    required this.onSelect,
  });

  final List<ContentRequestProvider> providers;
  final int selectedId;
  final ValueChanged<ContentRequestProvider> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.requestsProviderHeading,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: MediaBrowsingMetrics.chipGap),
        Wrap(
          spacing: MediaBrowsingMetrics.chipGap,
          runSpacing: MediaBrowsingMetrics.chipGap,
          children: [
            for (final provider in providers)
              SelectableChip(
                label: provider.integrationName,
                selected: provider.integrationId == selectedId,
                onTap: () => onSelect(provider),
              ),
          ],
        ),
      ],
    );
  }
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
    super.key,
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
