import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Browse and search EPG shows. The screen delegates the actual
/// `searchEpgShows` call to [onSearch] (wired by AppShell against
/// `XtreamService.searchEpgShows`) so the search happens behind the
/// AppStateController boundary, never as a direct service call from the widget.
class ShowsScreen extends ConsumerStatefulWidget {
  const ShowsScreen({
    super.key,
    required this.onSearch,
    this.onSidebarActivate,
    this.searchFocusNode,
    this.onShowSelect,
  });

  final Future<List<EpgShow>> Function(String query) onSearch;
  final VoidCallback? onSidebarActivate;

  /// Wired from AppShell so opening a show pushes through
  /// `AppShell._pushDetail(..., fullScreen: true)` — the same immersive,
  /// nav-hiding push used by VOD/Series/AIOStreams detail. Falls back to a
  /// plain `context.push` (no immersive treatment) when absent, e.g. in
  /// tests that render `ShowsScreen` without the full AppShell above it.
  final void Function(EpgShow show)? onShowSelect;

  /// When provided, the search field attaches to this [FocusNode] instead
  /// of auto-focusing on first build. Lets the parent (e.g. DvrRecordingsScreen)
  /// hand focus to the search field only when its tab is actually selected
  /// — TabBarView builds every child up front, so a plain `autofocus: true`
  /// would steal focus from whichever tab the user landed on.
  final FocusNode? searchFocusNode;

  @override
  ConsumerState<ShowsScreen> createState() => _ShowsScreenState();
}

class _ShowsScreenState extends ConsumerState<ShowsScreen> {
  String _query = '';
  Timer? _debounce;
  List<EpgShow> _results = const <EpgShow>[];
  bool _isLoading = false;
  String? _error;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    setState(() => _query = value);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const <EpgShow>[];
        _isLoading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(trimmed),
    );
  }

  Future<void> _runSearch(String trimmed) async {
    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await widget.onSearch(trimmed);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _openShow(EpgShow show) {
    if (widget.onShowSelect != null) {
      widget.onShowSelect!(show);
      return;
    }
    unawaited(
      context.push(
        RouteNames.showDetailsFor(show.normalizedTitle),
        extra: show,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isConfigured = ref.watch(isConfiguredProvider);
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    // Watching so the screen rebuilds when the foundation agent's
    // setDvrSeriesRules invalidates after a new rule is created elsewhere
    // (e.g. from the EPG long-press menu).
    ref.watch(dvrSeriesRulesProvider);

    if (isBootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!isConfigured) {
      return Center(
        child: Text(
          l10n.appNotConfigured,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    // ShowsScreen is embedded as DVR tab content — the host (DvrRecordingsScreen)
    // already supplies the Scaffold, tab bar, and page padding, so this returns
    // bare content rather than wrapping it in another Scaffold/pagePadding.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            bottom: MediaBrowsingMetrics.contentPadding,
          ),
          child: InlineMediaSearchField(
            query: _query,
            hintText: l10n.showsSearchHint,
            autofocus: widget.searchFocusNode == null,
            focusNode: widget.searchFocusNode,
            onChanged: _onQueryChanged,
          ),
        ),
        Expanded(child: _buildBody(l10n)),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          l10n.showsSearchError,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    final trimmed = _query.trim();
    if (trimmed.isEmpty) {
      return _Prompt(l10n: l10n);
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          l10n.showsNoResults,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return DpadRegion(
      memoryKey: 'shows/results',
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          widget.onSidebarActivate?.call();
        }
      },
      child: ScrollbarListView(
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final show = _results[index];
          return Padding(
            padding: const EdgeInsets.only(
              bottom: MediaBrowsingMetrics.itemGap,
            ),
            child: _ShowCard(
              show: show,
              autofocus: index == 0,
              onTap: () => _openShow(show),
            ),
          );
        },
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        l10n.showsSearchHint,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ShowCard extends StatelessWidget {
  const _ShowCard({
    required this.show,
    required this.onTap,
    this.autofocus = false,
  });

  final EpgShow show;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final localized = Localizations.localeOf(context).toLanguageTag();
    final nextAiring = show.nextAiringAt;
    final nextAiringLabel = nextAiring == null
        ? l10n.showAiringNone
        : '${l10n.showAiringNext} ${DateFormat.yMMMd(localized).add_jm().format(nextAiring.toLocal())}';

    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.tv,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    show.displayTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (show.channels.isNotEmpty)
                    Text(
                      l10n.showChannelCount(show.channelCount),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _Badge(label: l10n.showEpisodesCount(show.episodeCount)),
                      _Badge(label: nextAiringLabel),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MediaBrowsingMetrics.contentPadding),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
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
