import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Searches across every searchable AIOStreams catalog with All/Movies/Series tabs.
class AIOStreamsSearchScreen extends StatefulWidget {
  const AIOStreamsSearchScreen({
    super.key,
    required this.integrations,
    required this.apiService,
    required this.onItemSelect,
    this.favoritesService,
    this.onSidebarActivate,
  });

  final List<AIOStreamsIntegration> integrations;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsItem item, int integrationId) onItemSelect;
  final AIOStreamsFavoritesService? favoritesService;
  final VoidCallback? onSidebarActivate;

  @override
  State<AIOStreamsSearchScreen> createState() => _AIOStreamsSearchScreenState();
}

class _AIOStreamsSearchScreenState extends State<AIOStreamsSearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  bool _loading = false;
  String _query = '';
  List<_SearchResult> _allResults = const [];
  Set<String> _favoriteIds = const {};

  late final List<(AIOStreamsIntegration, AIOStreamsCatalog)> _searchable = [
    for (final integration in widget.integrations)
      for (final catalog in integration.catalogs)
        if (catalog.searchable) (integration, catalog),
  ];

  List<_SearchResult> get _movieResults =>
      _allResults.where((r) => r.item.type == 'movie').toList(growable: false);

  List<_SearchResult> get _seriesResults =>
      _allResults.where((r) => r.item.type == 'series').toList(growable: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
    widget.favoritesService?.addListener(_onFavoritesChanged);
    unawaited(_loadFavorites());
  }

  @override
  void didUpdateWidget(AIOStreamsSearchScreen old) {
    super.didUpdateWidget(old);
    if (old.favoritesService != widget.favoritesService) {
      old.favoritesService?.removeListener(_onFavoritesChanged);
      widget.favoritesService?.addListener(_onFavoritesChanged);
      unawaited(_loadFavorites());
    }
  }

  @override
  void dispose() {
    widget.favoritesService?.removeListener(_onFavoritesChanged);
    _tabController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFavoritesChanged() => unawaited(_loadFavorites());

  Future<void> _loadFavorites() async {
    final favs = await widget.favoritesService?.all() ?? const [];
    if (mounted) setState(() => _favoriteIds = favs.map((f) => f.id).toSet());
  }

  Future<void> _toggleFavorite(_SearchResult result) async {
    await widget.favoritesService?.toggle(
      AIOStreamsFavoriteItem(
        id: result.item.id,
        type: result.item.type,
        name: result.item.name,
        integrationId: result.integrationId,
        poster: result.item.poster,
      ),
    );
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value == _query) return;
    if (value.isEmpty) {
      setState(() {
        _query = '';
        _allResults = const [];
        _loading = false;
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
      _loading = true;
      _allResults = const [];
    });

    final futures = _searchable.map((
      (AIOStreamsIntegration, AIOStreamsCatalog) pair,
    ) {
      final (integration, catalog) = pair;
      return widget.apiService
          .getCatalog(
            integration.id,
            catalog.type,
            catalog.id,
            search: query,
          )
          .then(
            (items) => items.map(
              (item) =>
                  _SearchResult(item: item, integrationId: integration.id),
            ),
          )
          .catchError((_) => const Iterable<_SearchResult>.empty());
    });

    final grouped = await Future.wait(futures);
    if (!mounted || _query != query) return;

    final merged = grouped.expand((r) => r).toList()
      ..sort((a, b) => a.item.name.compareTo(b.item.name));

    setState(() {
      _allResults = merged;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 32, 24, 8),
              child: Row(
                children: [
                  DpadInkWell(
                    borderRadius: const BorderRadius.all(Radius.circular(50)),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InlineMediaSearchField(
                      query: _query,
                      hintText: l.aiostreamsSearchHint,
                      focusNode: _searchFocus,
                      onChanged: _onQueryChanged,
                    ),
                  ),
                ],
              ),
            ),
            DpadTabBar(
              controller: _tabController,
              tabs: [
                l.aiostreamsSearchAll,
                l.searchSectionMovies,
                l.searchSectionSeries,
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildResults(l, theme, _allResults),
                  _buildResults(l, theme, _movieResults),
                  _buildResults(l, theme, _seriesResults),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
    AppLocalizations l,
    ThemeData theme,
    List<_SearchResult> results,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_query.isEmpty) {
      return Center(
        child: Text(l.aiostreamsSearchHint, style: theme.textTheme.bodyLarge),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(l.aiostreamsNoResults, style: theme.textTheme.bodyLarge),
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
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return DpadInkWell(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          autofocus: index == 0,
          onTap: () => widget.onItemSelect(result.item, result.integrationId),
          onLongTap: widget.favoritesService == null
              ? null
              : () => unawaited(_toggleFavorite(result)),
          child: _ResultCard(
            item: result.item,
            isFavorite: _favoriteIds.contains(result.item.id),
          ),
        );
      },
    );
  }
}

class _SearchResult {
  const _SearchResult({required this.item, required this.integrationId});

  final AIOStreamsItem item;
  final int integrationId;
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.item, this.isFavorite = false});

  final AIOStreamsItem item;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ResilientMediaImage(
                imageUrl: item.poster,
                fallbackIcon: item.type == 'series' ? Icons.tv : Icons.movie,
              ),
              if (isFavorite)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    Icons.star,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          item.name,
          style: theme.textTheme.bodySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
