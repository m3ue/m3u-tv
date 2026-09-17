import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Actor filmography screen: TMDB bio/photo header over a poster grid of
/// their other movies/TV credits, mirroring m3u-editor's own
/// `ActorFilmography` Filament page. Reached by tapping a cast member on the
/// VOD, Series, or AIOStreams detail screens (they all share the same cast
/// widgets - see `CastStrip`/`CastMemberRow`).
///
/// Data fetch mirrors `VodDetailsScreen`'s plain-Future pattern (no Riverpod
/// provider, no `FutureBuilder` boilerplate at the call site) - this screen
/// is reached from three different sources so it stays deliberately
/// self-contained rather than depending on a route-specific provider.
class PersonDetailScreen extends StatefulWidget {
  const PersonDetailScreen({
    super.key,
    required this.name,
    this.personId,
    this.xtreamService,
    this.onSidebarActivate,
    this.onOpenCredit,
    this.includeLibraryFilter = true,
  });

  /// The cast member's display name - always known up front (from
  /// `CastMember.name`), so it can be the AppBar title immediately without
  /// waiting on the fetch.
  final String name;

  /// The TMDB person id, when known (`CastMember.id`). Falls back to a
  /// server-side TMDB person-name search when null.
  final int? personId;

  final XtreamService? xtreamService;
  final VoidCallback? onSidebarActivate;

  /// Opens a filmography credit. For Xtream callers (`includeLibraryFilter`
  /// true) this only fires for credits already in the caller's playlist
  /// library (`FilmographyCredit.inLibrary`) - credits not in the library
  /// render disabled, since there is no "request from Discover" flow here
  /// (that's Filament-specific, out of scope for this app). For AIOStreams
  /// callers (`includeLibraryFilter` false) every credit is available and
  /// this always fires - AIOStreams is on-demand, not library-driven.
  final ValueChanged<FilmographyCredit>? onOpenCredit;

  /// Shows the All/In Library filter toggle above the filmography grid, and
  /// gates whether `FilmographyCredit.inLibrary` is used to disable a
  /// credit's tap/opacity. `inLibrary` is resolved against the caller's
  /// Xtream playlist library (Series/VOD channels) - that concept doesn't
  /// apply to AIOStreams content, so the AIOStreams route pushes this as
  /// `false` to both hide the filter and treat every credit as available.
  final bool includeLibraryFilter;

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  late final Future<ActorFilmography?>? _future = widget.xtreamService
      ?.fetchActorFilmography(personId: widget.personId, name: widget.name);

  @override
  Widget build(BuildContext context) {
    return ItemDetailScaffold(
      title: widget.name,
      onSidebarActivate: widget.onSidebarActivate,
      body: _future == null
          ? _PersonDetailBody(
              name: widget.name,
              onOpenCredit: widget.onOpenCredit,
            )
          : FutureBuilder<ActorFilmography?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint(
                    'PersonDetailScreen: fetchActorFilmography failed for '
                    'personId=${widget.personId} name="${widget.name}": '
                    '${snapshot.error}',
                  );
                }
                return _PersonDetailBody(
                  name: widget.name,
                  filmography: snapshot.hasError ? null : snapshot.data,
                  isLoading: snapshot.connectionState != ConnectionState.done,
                  hasError: snapshot.hasError,
                  onOpenCredit: widget.onOpenCredit,
                  includeLibraryFilter: widget.includeLibraryFilter,
                );
              },
            ),
    );
  }
}

class _PersonDetailBody extends StatefulWidget {
  const _PersonDetailBody({
    required this.name,
    this.filmography,
    this.isLoading = false,
    this.hasError = false,
    this.onOpenCredit,
    this.includeLibraryFilter = true,
  });

  final String name;
  final ActorFilmography? filmography;
  final bool isLoading;
  final bool hasError;
  final ValueChanged<FilmographyCredit>? onOpenCredit;
  final bool includeLibraryFilter;

  @override
  State<_PersonDetailBody> createState() => _PersonDetailBodyState();
}

class _PersonDetailBodyState extends State<_PersonDetailBody> {
  static const double _minPosterCardWidth = 120;
  static const double _maxPosterCardWidth = 220;

  // Owned here (not RowScrollRegion) - this screen is a single plain
  // CustomScrollView, not the locked-row vertical navigation RowScrollRegion
  // is built for (see MovieDetailBody/SeriesDetailBody). Same offset/
  // duration/curve as RowScrollRegionState.scrollToTop() so the feel matches
  // every other detail screen's "focus the header -> snap to top" behavior.
  final ScrollController _scrollController = ScrollController();

  bool _showLibraryOnly = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  int _posterColumnCount(double availableWidth, double scale) {
    final maxCardWidth = _maxPosterCardWidth * scale;
    final minCardWidth = _minPosterCardWidth * scale;
    final minimumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (maxCardWidth + MediaBrowsingMetrics.itemGap))
            .ceil();
    final maximumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (minCardWidth + MediaBrowsingMetrics.itemGap))
            .floor();
    return minimumColumns.clamp(1, maximumColumns.clamp(1, 100));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final person = widget.filmography?.person;
    final allCredits =
        widget.filmography?.credits ?? const <FilmographyCredit>[];
    final filterActive = widget.includeLibraryFilter && _showLibraryOnly;
    final credits = filterActive
        ? allCredits.where((c) => c.inLibrary).toList(growable: false)
        : allCredits;
    final scale = FontSizeScope.scaleOf(context);

    return SafeArea(
      top: false,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              MediaBrowsingMetrics.contentPadding,
              detailAppBarHeight(context) + MediaBrowsingMetrics.contentPadding,
              MediaBrowsingMetrics.contentPadding,
              0,
            ),
            sliver: SliverToBoxAdapter(
              // Scrolls the page back to the top whenever anything in this
              // header block takes D-pad focus - same offset/duration/curve
              // RowScrollRegionState.scrollToTop() uses on every other detail
              // screen, so the "focus header -> snap to top" feel matches.
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (hasFocus) {
                  if (hasFocus) _scrollToTop();
                },
                child: widget.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : widget.hasError
                    ? Text(l.personDetailsError)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Focusable but not clickable (onTap: null) -
                          // purely so D-pad Up from the grid's top row has a
                          // target to land on above it; the Focus wrapper
                          // above owns scrolling it back into view (full
                          // scroll-to-top, not "just enough to reveal").
                          // autoScroll: false is required here - DpadInkWell's
                          // default autoScroll fires its own ensureVisible
                          // (partial-reveal) scroll on the same focus change,
                          // and that second animateTo overrides the tail of
                          // the Focus wrapper's animateTo(0) before it
                          // settles, so the page stops short of the top. Same
                          // fix as AppButton's autoScroll: false inside
                          // RowScrollRegion (series_detail_widgets.dart) -
                          // exactly one thing may own this ScrollController's
                          // animation.
                          // Styled like a Continue Watching poster tile
                          // (MediaPreviewCard) rather than a plain circular
                          // avatar - same corner radius, and the outer
                          // DpadInkWell's clip (not a raw ClipOval) does the
                          // rounding so the focus glow matches the image edge.
                          DpadInkWell(
                            autoScroll: false,
                            borderRadius: BorderRadius.circular(
                              MediaBrowsingMetrics.cardRadius,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 140 * scale,
                              height: 210 * scale,
                              child: ResilientMediaImage(
                                imageUrl: person?.photo,
                                fallbackIcon: Icons.person,
                                borderRadius: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              (person?.bio?.trim().isNotEmpty ?? false)
                                  ? person!.bio!
                                  : l.personDetailsBioUnavailable,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          if (!widget.isLoading && !widget.hasError)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                MediaBrowsingMetrics.contentPadding,
                MediaBrowsingMetrics.contentPadding,
                MediaBrowsingMetrics.contentPadding,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    DetailRowHeader(
                      icon: Icons.movie,
                      label: l.personDetailsFilmography,
                    ),
                    if (widget.includeLibraryFilter && allCredits.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: _LibraryFilterToggle(
                          showLibraryOnly: _showLibraryOnly,
                          onChanged: (value) =>
                              setState(() => _showLibraryOnly = value),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (!widget.isLoading && !widget.hasError && credits.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(
                MediaBrowsingMetrics.contentPadding,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  filterActive
                      ? l.personDetailsNoLibraryMatches
                      : l.personDetailsEmpty,
                ),
              ),
            ),
          if (!widget.isLoading && !widget.hasError && credits.isNotEmpty)
            SliverLayoutBuilder(
              builder: (context, constraints) {
                final availableWidth =
                    constraints.crossAxisExtent -
                    MediaBrowsingMetrics.contentPadding * 2;
                final columnCount = _posterColumnCount(availableWidth, scale);
                return SliverPadding(
                  padding: const EdgeInsets.all(
                    MediaBrowsingMetrics.contentPadding,
                  ),
                  sliver: DpadRegion(
                    // Keyed by filter state so toggling rebuilds a fresh
                    // region instead of reusing D-pad focus/scroll memory
                    // for what is now a different item at the same index.
                    memoryKey: 'person/filmography-grid/$filterActive',
                    horizontalEdge: DpadEdgeBehavior.stop,
                    child: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnCount,
                        childAspectRatio: 0.6,
                        mainAxisSpacing: MediaBrowsingMetrics.itemGap,
                        crossAxisSpacing: MediaBrowsingMetrics.itemGap,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _creditCard(
                          credits[index],
                          autofocus: index == 0,
                        ),
                        childCount: credits.length,
                      ),
                    ),
                  ),
                );
              },
            ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _creditCard(FilmographyCredit credit, {required bool autofocus}) {
    // `inLibrary` is resolved against the Xtream playlist's Series/VOD
    // library - meaningless for AIOStreams, which is on-demand and has no
    // "library" concept, so every credit is available there regardless of
    // what the backend annotated. `includeLibraryFilter` doubles as that
    // signal (the AIOStreams route pushes it `false`, see route_names.dart).
    final available = !widget.includeLibraryFilter || credit.inLibrary;
    return Opacity(
      opacity: available ? 1 : 0.4,
      child: MediaPreviewCard(
        posterStyle: true,
        keepAlive: false,
        autofocus: autofocus,
        item: MediaPreviewItem(
          title: credit.title,
          imageUrl: credit.posterUrl,
          subtitle: credit.year,
          fallbackIcon: credit.isSeries ? Icons.tv : Icons.movie,
          onTap: available ? () => widget.onOpenCredit?.call(credit) : () {},
        ),
      ),
    );
  }
}

/// Pill toggle above the filmography grid, filtering credits down to what
/// exists in the caller's playlist library. Mirrors the project's stadium
/// pill-button convention (`circular(50)`, per m3u-tv/CLAUDE.md's TV
/// interaction rules) and the selected/unselected color-swap idiom used by
/// `_SeasonToggle` (`lib/features/requests/request_detail_screen.dart`) -
/// there's no shared segmented-control widget yet, so this is a small
/// bespoke one rather than introducing a new abstraction for a single use.
class _LibraryFilterToggle extends StatelessWidget {
  const _LibraryFilterToggle({
    required this.showLibraryOnly,
    required this.onChanged,
  });

  final bool showLibraryOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterOption(
          label: l.personDetailsFilterAll,
          selected: !showLibraryOnly,
          onTap: () => onChanged(false),
        ),
        const SizedBox(width: 8),
        _FilterOption(
          label: l.personDetailsFilterInLibrary,
          selected: showLibraryOnly,
          onTap: () => onChanged(true),
        ),
      ],
    );
  }
}

class _FilterOption extends StatelessWidget {
  const _FilterOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
