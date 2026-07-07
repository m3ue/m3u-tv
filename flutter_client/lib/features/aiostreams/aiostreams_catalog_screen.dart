import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
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
/// Shows all integrations with their catalogs as horizontal rows.
class AIOStreamsHomeScreen extends StatelessWidget {
  const AIOStreamsHomeScreen({
    super.key,
    required this.integrations,
    required this.apiService,
    required this.onItemSelect,
    this.onSidebarActivate,
  });

  final List<AIOStreamsIntegration> integrations;
  final AIOStreamsApiService apiService;
  final void Function(AIOStreamsItem, int integrationId) onItemSelect;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (integrations.isEmpty) {
      return Scaffold(
        body: Center(child: Text(l.aiostrreamsCatalogEmpty)),
      );
    }

    final rows = <Widget>[];
    for (final integration in integrations) {
      for (final catalog in integration.catalogs) {
        rows.add(
          AIOStreamsCatalogRow(
            catalog: catalog,
            integrationId: integration.id,
            apiService: apiService,
            onItemSelect: (item) => onItemSelect(item, integration.id),
            onSidebarActivate: onSidebarActivate,
          ),
        );
      }
    }

    return Scaffold(
      body: DpadRegion(
        horizontalEdge: DpadEdgeBehavior.stop,
        onEdge: (direction) {
          if (direction == TraversalDirection.left) {
            onSidebarActivate?.call();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.pagePadding),
          children: [
            Text(
              l.navAioStreams,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: MediaBrowsingMetrics.pagePadding),
            ...rows,
          ],
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
