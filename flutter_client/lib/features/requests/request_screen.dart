import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Guest content requests against the owner's Sonarr/Radarr integrations.
///
/// Mirrors the DVR screen's real-time wiring: AppStateController keeps
/// [mediaRequestsProvider] warm via `request_history` on connect and
/// `request.status` Reverb pushes (see MediaRequestStatusEvent on the
/// server), so this screen only owns transient search state.
class RequestScreen extends ConsumerStatefulWidget {
  const RequestScreen({
    super.key,
    required this.isConfigured,
    required this.onSearch,
    required this.onResultSelect,
    required this.onDismiss,
    required this.onRefreshRequests,
    this.onSidebarActivate,
  });

  final bool isConfigured;
  final Future<List<ContentRequestSearchResult>> Function(
    String query, {
    String? type,
  })
  onSearch;
  final void Function(ContentRequestSearchResult result) onResultSelect;
  final Future<void> Function(int requestId) onDismiss;
  final Future<void> Function() onRefreshRequests;
  final VoidCallback? onSidebarActivate;

  @override
  ConsumerState<RequestScreen> createState() => _RequestScreenState();
}

class _RequestScreenState extends ConsumerState<RequestScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  Timer? _debounce;

  String _query = '';
  String _typeFilter = '';
  bool _isSearching = false;
  String? _searchError;
  List<ContentRequestSearchResult> _results = const [];
  final Set<int> _dismissingIds = <int>{};

  @override
  void initState() {
    super.initState();
    if (widget.isConfigured) unawaited(widget.onRefreshRequests());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value == _query) return;
    if (value.trim().length < 2) {
      setState(() {
        _query = value;
        _results = const [];
        _isSearching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_search(value));
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _query = query;
      _isSearching = true;
      _searchError = null;
    });
    try {
      final results = await widget.onSearch(
        query.trim(),
        type: _typeFilter.isEmpty ? null : _typeFilter,
      );
      if (!mounted || _query != query) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } on Object catch (error) {
      if (!mounted || _query != query) return;
      setState(() {
        _isSearching = false;
        _searchError = _errorMessage(error);
      });
    }
  }

  String _errorMessage(Object error) =>
      error is XtreamRequestException ? error.message : error.toString();

  void _onTypeFilterChanged(String type) {
    if (type == _typeFilter) return;
    setState(() => _typeFilter = type);
    if (_query.trim().length >= 2) unawaited(_search(_query));
  }

  bool _isAlreadyRequested(
    ContentRequestSearchResult result,
    List<MediaRequestSummary> myRequests,
  ) => myRequests.any(
    (request) =>
        request.type == result.type &&
        request.externalId == result.externalId &&
        (request.status == MediaRequestStatus.pendingApproval ||
            request.status == MediaRequestStatus.approved),
  );

  Future<void> _dismiss(MediaRequestSummary request) async {
    final l = AppLocalizations.of(context);
    setState(() => _dismissingIds.add(request.id));
    try {
      await widget.onDismiss(request.id);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.requestsDismissFailed(_errorMessage(error)))),
      );
    } finally {
      if (mounted) setState(() => _dismissingIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (!widget.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: Text(l.navRequests)),
        body: Center(
          child: Text(
            l.appNotConfigured,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    final myRequests = ref.watch(mediaRequestsProvider);

    return Scaffold(
      body: DpadRegion(
        memoryKey: 'requests/screen',
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            widget.onSidebarActivate?.call();
          }
        },
        child: Column(
          children: [
            DpadTabBar(
              controller: _tabController,
              tabs: [l.requestsTabSearch, l.requestsTabMyRequests],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSearchTab(l, myRequests),
                  _buildMyRequestsTab(l, myRequests),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(
    AppLocalizations l,
    List<MediaRequestSummary> myRequests,
  ) {
    final contentTypes =
        ref.watch(requestsCapabilityProvider)?.contentTypes ?? const [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            MediaBrowsingMetrics.contentPadding,
            MediaBrowsingMetrics.contentPadding,
            MediaBrowsingMetrics.contentPadding,
            0,
          ),
          child: InlineMediaSearchField(
            query: _query,
            hintText: l.requestsSearchHint,
            onChanged: _onQueryChanged,
          ),
        ),
        if (contentTypes.length > 1)
          ScrollableCategoryBar(
            tabs: [
              CategoryTabData(id: '', name: l.aiostreamsSearchAll),
              if (contentTypes.contains('movie'))
                CategoryTabData(id: 'movie', name: l.searchSectionMovies),
              if (contentTypes.contains('series'))
                CategoryTabData(id: 'series', name: l.searchSectionSeries),
            ],
            selectedId: _typeFilter,
            onSelected: _onTypeFilterChanged,
          ),
        Expanded(child: _buildSearchResults(l, myRequests)),
      ],
    );
  }

  Widget _buildSearchResults(
    AppLocalizations l,
    List<MediaRequestSummary> myRequests,
  ) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.trim().length < 2) {
      return Center(
        child: Text(
          l.searchTypeToSearch,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          child: Text(
            _searchError!,
            style:
                Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          l.requestsNoResults,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
        final columnCount = _posterColumnCount(availableWidth);
        return ScrollbarGridView(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columnCount,
            childAspectRatio: 0.6,
            mainAxisSpacing: MediaBrowsingMetrics.itemGap,
            crossAxisSpacing: MediaBrowsingMetrics.itemGap,
          ),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final result = _results[index];
            return _RequestResultCard(
              result: result,
              autofocus: index == 0,
              isAlreadyRequested: _isAlreadyRequested(result, myRequests),
              onTap: () => widget.onResultSelect(result),
            );
          },
        );
      },
    );
  }

  static const double _minPosterCardWidth = 120;
  static const double _maxPosterCardWidth = 220;

  int _posterColumnCount(double availableWidth) {
    final minimumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (_maxPosterCardWidth + MediaBrowsingMetrics.itemGap))
            .ceil();
    final maximumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (_minPosterCardWidth + MediaBrowsingMetrics.itemGap))
            .floor();
    return minimumColumns.clamp(1, maximumColumns.clamp(1, 100));
  }

  Widget _buildMyRequestsTab(
    AppLocalizations l,
    List<MediaRequestSummary> myRequests,
  ) {
    if (myRequests.isEmpty) {
      return Center(
        child: Text(
          l.requestsMyRequestsEmpty,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return ScrollbarListView(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      itemCount: myRequests.length,
      itemBuilder: (context, index) {
        final request = myRequests[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: MediaBrowsingMetrics.itemGap),
          child: _MyRequestCard(
            request: request,
            l: l,
            isDismissing: _dismissingIds.contains(request.id),
            onDismiss: request.canDismiss
                ? () => unawaited(_dismiss(request))
                : null,
          ),
        );
      },
    );
  }
}

/// Mirrors _VodCard in vod_screen.dart: same Hero tag convention, same
/// image/title/rating layout, same corner-badge position — just swapping
/// the favorite star for an already-requested/already-available indicator.
class _RequestResultCard extends StatelessWidget {
  const _RequestResultCard({
    required this.result,
    required this.onTap,
    this.autofocus = false,
    this.isAlreadyRequested = false,
  });

  final ContentRequestSearchResult result;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isAlreadyRequested;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flagged = result.alreadyAvailable || isAlreadyRequested;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Hero(
                  tag: 'request_poster_${result.type}_${result.externalId}',
                  child: ResilientMediaImage(
                    imageUrl: result.poster,
                    fallbackIcon: result.type == 'series'
                        ? Icons.tv
                        : Icons.movie,
                    borderRadius: 0,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (result.rating != null)
                      Text(
                        '★ ${result.rating!.value.toStringAsFixed(1)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFFFFCC00),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (flagged)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  result.alreadyAvailable
                      ? Icons.check_circle_outline
                      : Icons.hourglass_top,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MyRequestCard extends StatelessWidget {
  const _MyRequestCard({
    required this.request,
    required this.l,
    this.onDismiss,
    this.isDismissing = false,
  });

  final MediaRequestSummary request;
  final AppLocalizations l;
  final VoidCallback? onDismiss;
  final bool isDismissing;

  String _statusLabel() => switch (request.status) {
    MediaRequestStatus.pendingApproval => l.requestsStatusPendingApproval,
    MediaRequestStatus.approved => l.requestsStatusApproved,
    MediaRequestStatus.rejected => l.requestsStatusRejected,
    MediaRequestStatus.completed => l.requestsStatusCompleted,
    MediaRequestStatus.unknown => l.requestsStatusUnknown,
  };

  Color _statusColor(ColorScheme colorScheme) => switch (request.status) {
    MediaRequestStatus.pendingApproval => colorScheme.secondary,
    MediaRequestStatus.approved => colorScheme.primary,
    MediaRequestStatus.rejected => colorScheme.error,
    MediaRequestStatus.completed => colorScheme.primary,
    MediaRequestStatus.unknown => colorScheme.onSurfaceVariant,
  };

  IconData _statusIcon() => switch (request.status) {
    MediaRequestStatus.pendingApproval => Icons.hourglass_top,
    MediaRequestStatus.approved => Icons.downloading,
    MediaRequestStatus.rejected => Icons.cancel,
    MediaRequestStatus.completed => Icons.check_circle,
    MediaRequestStatus.unknown => Icons.radio_button_unchecked,
  };

  String? _episodeLabel() {
    final season = request.seasonNumber;
    final episode = request.episodeNumber;
    if (season != null && episode != null) return 'S$season E$episode';
    if (season != null) return 'Season $season';
    if (episode != null) return 'Episode $episode';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _statusColor(theme.colorScheme);
    final episodeLabel = _episodeLabel();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_statusIcon(), color: color),
          ),
          const SizedBox(width: MediaBrowsingMetrics.contentPadding),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _Badge(label: _statusLabel()),
                    if (request.integrationName != null)
                      _Badge(label: request.integrationName!),
                    if (episodeLabel != null) _Badge(label: episodeLabel),
                  ],
                ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            if (isDismissing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              DpadFocusable(
                onSelect: onDismiss,
                child: IconButton(
                  tooltip: l.requestsDismiss,
                  icon: const Icon(Icons.close),
                  onPressed: onDismiss,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(label, style: theme.textTheme.labelMedium),
      ),
    );
  }
}
