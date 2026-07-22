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
    required this.onSubmit,
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
  final Future<MediaRequestSummary> Function({
    required String type,
    required int integrationId,
    required String externalId,
  })
  onSubmit;
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
  bool _isSearching = false;
  String? _searchError;
  List<ContentRequestSearchResult> _results = const [];
  final Set<String> _submittingKeys = <String>{};
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
      final results = await widget.onSearch(query.trim());
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

  Future<void> _submit(ContentRequestSearchResult result) async {
    final l = AppLocalizations.of(context);
    final key = '${result.type}:${result.externalId}';
    setState(() => _submittingKeys.add(key));
    try {
      final request = await widget.onSubmit(
        type: result.type,
        integrationId: result.integrationId,
        externalId: result.externalId,
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
      if (mounted) setState(() => _submittingKeys.remove(key));
    }
  }

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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
          child: InlineMediaSearchField(
            query: _query,
            hintText: l.requestsSearchHint,
            onChanged: _onQueryChanged,
          ),
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
    return GridView.builder(
      padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        final key = '${result.type}:${result.externalId}';
        return _SearchResultCard(
          result: result,
          l: l,
          autofocus: index == 0,
          isSubmitting: _submittingKeys.contains(key),
          isAlreadyRequested: _isAlreadyRequested(result, myRequests),
          onRequest: () => unawaited(_submit(result)),
        );
      },
    );
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

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.l,
    required this.onRequest,
    this.autofocus = false,
    this.isSubmitting = false,
    this.isAlreadyRequested = false,
  });

  final ContentRequestSearchResult result;
  final AppLocalizations l;
  final VoidCallback onRequest;
  final bool autofocus;
  final bool isSubmitting;
  final bool isAlreadyRequested;

  bool get _actionable =>
      !result.alreadyAvailable && !isAlreadyRequested && !isSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DpadInkWell(
      autofocus: autofocus,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      onTap: _actionable ? onRequest : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ResilientMediaImage(
                  imageUrl: result.poster,
                  fallbackIcon: result.type == 'series'
                      ? Icons.tv
                      : Icons.movie,
                ),
                if (isSubmitting)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (result.alreadyAvailable || isAlreadyRequested)
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 4,
                    child: _StatusPill(
                      label: result.alreadyAvailable
                          ? l.requestsAlreadyAvailable
                          : l.requestsAlreadyRequested,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            result.title,
            style: theme.textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
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
