import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/aiostreams_progress_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Returns a display-friendly title for a catalog, appending the media type
/// label when the catalog name doesn't already imply it.
String _catalogDisplayTitle(AppLocalizations l, AIOStreamsCatalog catalog) {
  final name = catalog.name;
  final lower = name.toLowerCase();
  final hasTypeHint =
      lower.contains('movie') ||
      lower.contains('series') ||
      lower.contains('film') ||
      lower.contains('show') ||
      lower.contains(' tv');
  if (hasTypeHint) return name;
  final suffix = catalog.type == 'series' ? l.navSeries : l.navVod;
  return '$name $suffix';
}

/// Full-screen catalog browser for a single AIOStreams catalog.
/// Supports lazy pagination and optional text search.
class AIOStreamsCatalogScreen extends StatefulWidget {
  const AIOStreamsCatalogScreen({
    super.key,
    required this.integrationId,
    required this.catalog,
    required this.apiService,
    required this.onItemSelect,
    this.onSidebarActivate,
  });

  final int integrationId;
  final AIOStreamsCatalog catalog;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsItem) onItemSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<AIOStreamsCatalogScreen> createState() =>
      _AIOStreamsCatalogScreenState();
}

class _AIOStreamsCatalogScreenState extends State<AIOStreamsCatalogScreen> {
  static const int _pageSize = 20;

  final List<AIOStreamsItem> _items = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = false;
  bool _hasMore = true;
  int _skip = 0;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadPage() async {
    if (_loading) return;
    setState(() => _loading = true);

    final results = await widget.apiService.getCatalog(
      widget.integrationId,
      widget.catalog.type,
      widget.catalog.id,
      skip: _skip,
      search: _search.isEmpty ? null : _search,
    );

    if (mounted) {
      setState(() {
        _items.addAll(results);
        _skip += results.length;
        _hasMore = results.length >= _pageSize;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    await _loadPage();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && query != _search) {
        setState(() {
          _search = query;
          _items.clear();
          _skip = 0;
          _hasMore = true;
        });
        unawaited(_loadPage());
      }
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
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        DpadInkWell(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(50),
                          ),
                          onTap: () => Navigator.of(context).maybePop(),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _catalogDisplayTitle(l, widget.catalog),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.catalog.searchable) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: l.aiostreamsSearchHint,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_items.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(l.aiostrreamsCatalogEmpty)),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    childCount: _items.length,
                    (context, index) {
                      final item = _items[index];
                      return DpadInkWell(
                        borderRadius: const BorderRadius.all(
                          Radius.circular(8),
                        ),
                        onTap: () => widget.onItemSelect(item),
                        autofocus: index == 0,
                        child: _CatalogItemCard(item: item),
                      );
                    },
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2 / 3,
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_hasMore && !_loading && _items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: DpadInkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      onTap: () => unawaited(_loadMore()),
                      child: FilledButton(
                        onPressed: () => unawaited(_loadMore()),
                        child: Text(l.aiostreamsLoadMore),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CatalogItemCard extends StatelessWidget {
  const _CatalogItemCard({required this.item});

  final AIOStreamsItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ResilientMediaImage(
            imageUrl: item.poster,
            fallbackIcon: item.type == 'series' ? Icons.tv : Icons.movie,
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

/// Top-level screen for the AIOStreams nav tab.
/// Shows all integrations with their catalogs as horizontal rows,
/// plus optional Continue Watching, My Favorites, and Search sections.
class AIOStreamsHomeScreen extends StatefulWidget {
  const AIOStreamsHomeScreen({
    super.key,
    required this.integrations,
    required this.apiService,
    required this.onItemSelect,
    this.favoritesService,
    this.progressService,
    this.onSidebarActivate,
  });

  final List<AIOStreamsIntegration> integrations;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsItem, int integrationId) onItemSelect;
  final AIOStreamsFavoritesService? favoritesService;
  final AIOStreamsProgressService? progressService;
  final VoidCallback? onSidebarActivate;

  @override
  State<AIOStreamsHomeScreen> createState() => _AIOStreamsHomeScreenState();
}

class _AIOStreamsHomeScreenState extends State<AIOStreamsHomeScreen> {
  List<AIOStreamsFavoriteItem> _favorites = const [];

  bool get _hasSearchableCatalog => widget.integrations.any(
    (i) => i.catalogs.any((c) => c.searchable),
  );

  @override
  void initState() {
    super.initState();
    widget.favoritesService?.addListener(_onFavoritesChanged);
    widget.progressService?.addListener(_onProgressChanged);
    unawaited(_loadFavorites());
  }

  @override
  void didUpdateWidget(AIOStreamsHomeScreen old) {
    super.didUpdateWidget(old);
    if (old.favoritesService != widget.favoritesService) {
      old.favoritesService?.removeListener(_onFavoritesChanged);
      widget.favoritesService?.addListener(_onFavoritesChanged);
      unawaited(_loadFavorites());
    }
    if (old.progressService != widget.progressService) {
      old.progressService?.removeListener(_onProgressChanged);
      widget.progressService?.addListener(_onProgressChanged);
    }
  }

  @override
  void dispose() {
    widget.favoritesService?.removeListener(_onFavoritesChanged);
    widget.progressService?.removeListener(_onProgressChanged);
    super.dispose();
  }

  void _onFavoritesChanged() => unawaited(_loadFavorites());

  void _onProgressChanged() => setState(() {});

  Future<void> _loadFavorites() async {
    final favs = await widget.favoritesService?.all() ?? const [];
    if (mounted) setState(() => _favorites = favs);
  }

  void _openSearch(BuildContext context) {
    context.go(RouteNames.aiostreamsSearchPath);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (widget.integrations.isEmpty) {
      return Scaffold(
        body: Center(child: Text(l.aiostrreamsCatalogEmpty)),
      );
    }

    final continueWatching =
        widget.progressService?.continueWatching ?? const [];
    final logoUrl = widget.integrations.firstOrNull?.logoUrl;

    return Scaffold(
      body: DpadRegion(
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            widget.onSidebarActivate?.call();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          children: [
            // Header row: logo + title + optional search button
            Row(
              children: [
                if (logoUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      logoUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    l.navAioStreams,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                if (_hasSearchableCatalog)
                  DpadFocusable(
                    onSelect: () => _openSearch(context),
                    effects: const [
                      GradientBorderEffect(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                      ),
                    ],
                    child: IconButton(
                      tooltip: l.aiostreamsSearch,
                      icon: const Icon(Icons.search),
                      onPressed: () => _openSearch(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: MediaBrowsingMetrics.pagePadding),

            // Continue Watching row
            if (continueWatching.isNotEmpty) ...[
              _SectionHeader(title: l.aiostreamsContinueWatching),
              MediaPreviewSection(
                title: '',
                emptyLabel: '',
                posterStyle: true,
                items: continueWatching
                    .map(
                      (p) => MediaPreviewItem(
                        title: p.name,
                        imageUrl: p.poster,
                        subtitle: p.type,
                        fallbackIcon: p.type == 'series'
                            ? Icons.tv
                            : Icons.movie,
                        fallbackTitle: p.name,
                        onTap: () => widget.onItemSelect(
                          AIOStreamsItem(
                            id: p.itemId,
                            type: p.type,
                            name: p.name,
                            poster: p.poster,
                          ),
                          p.integrationId,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onSidebarActivate: widget.onSidebarActivate,
              ),
            ],

            // My Favorites row
            if (_favorites.isNotEmpty) ...[
              _SectionHeader(title: l.aiostreamsMyFavorites),
              MediaPreviewSection(
                title: '',
                emptyLabel: '',
                posterStyle: true,
                items: _favorites
                    .map(
                      (fav) => MediaPreviewItem(
                        title: fav.name,
                        imageUrl: fav.poster,
                        subtitle: fav.type,
                        fallbackIcon: fav.type == 'series'
                            ? Icons.tv
                            : Icons.movie,
                        fallbackTitle: fav.name,
                        onTap: () => widget.onItemSelect(
                          AIOStreamsItem(
                            id: fav.id,
                            type: fav.type,
                            name: fav.name,
                            poster: fav.poster,
                          ),
                          fav.integrationId,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onSidebarActivate: widget.onSidebarActivate,
              ),
            ],

            // Catalog rows
            for (final integration in widget.integrations)
              for (final catalog in integration.catalogs)
                AIOStreamsCatalogRow(
                  catalog: catalog,
                  integrationId: integration.id,
                  apiService: widget.apiService,
                  onItemSelect: (item) =>
                      widget.onItemSelect(item, integration.id),
                  onSidebarActivate: widget.onSidebarActivate,
                ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A single horizontal catalog row shown on the AIOStreams home tab.
class AIOStreamsCatalogRow extends StatefulWidget {
  const AIOStreamsCatalogRow({
    super.key,
    required this.catalog,
    required this.integrationId,
    required this.apiService,
    required this.onItemSelect,
    this.onSidebarActivate,
  });

  final AIOStreamsCatalog catalog;
  final int integrationId;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsItem) onItemSelect;
  final VoidCallback? onSidebarActivate;

  @override
  State<AIOStreamsCatalogRow> createState() => _AIOStreamsCatalogRowState();
}

class _AIOStreamsCatalogRowState extends State<AIOStreamsCatalogRow> {
  late final Future<List<AIOStreamsItem>> _future = widget.apiService
      .getCatalog(
        widget.integrationId,
        widget.catalog.type,
        widget.catalog.id,
      );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<AIOStreamsItem>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _CatalogRowSkeleton(
            title: _catalogDisplayTitle(l, widget.catalog),
          );
        }
        final items = snapshot.data ?? const [];
        return MediaPreviewSection(
          title: _catalogDisplayTitle(l, widget.catalog),
          emptyLabel: AppLocalizations.of(context).aiostrreamsCatalogEmpty,
          posterStyle: true,
          items: items
              .map(
                (item) => MediaPreviewItem(
                  title: item.name,
                  imageUrl: item.poster,
                  subtitle: item.year ?? item.type,
                  fallbackIcon: item.type == 'series' ? Icons.tv : Icons.movie,
                  fallbackTitle: item.name,
                  onTap: () => widget.onItemSelect(item),
                ),
              )
              .toList(growable: false),
          onSidebarActivate: widget.onSidebarActivate,
        );
      },
    );
  }
}

class _CatalogRowSkeleton extends StatelessWidget {
  const _CatalogRowSkeleton({required this.title});

  final String title;

  // Mirrors MediaPreviewSection._previewCardScale.
  double _scale(double availableWidth) {
    if (availableWidth >= 1600) return 1;
    return (availableWidth / 1280.0).clamp(1.0, 1.15);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: MediaBrowsingMetrics.chipGap),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = _scale(constraints.maxWidth);
              final cardWidth = MediaBrowsingMetrics.posterCardWidth * scale;
              final cardHeight = MediaBrowsingMetrics.posterCardHeight * scale;
              return SizedBox(
                height: cardHeight + 16,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 6,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MediaBrowsingMetrics.chipGap),
                  itemBuilder: (_, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: cardWidth,
                      child: ColoredBox(color: color),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
