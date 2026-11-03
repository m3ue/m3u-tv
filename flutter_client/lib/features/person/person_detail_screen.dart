import 'package:dpad/dpad.dart' show DpadEdgeBehavior, DpadRegion;
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_detail_scaffold.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/poster_strip.dart';
import 'package:material_ui/material_ui.dart';

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

  // Tapping the actor image toggles the bio between its truncated preview
  // and the full text - see the DpadInkWell in _actorImage().
  bool _bioExpanded = false;

  // Lets the wide-layout _FilmographyStrip send D-pad Up back to the actor
  // image, since the strip is a single locked focus stop that intercepts
  // every arrow key itself rather than letting dpad's spatial traversal find
  // it (see _FilmographyStrip's doc comment).
  final FocusNode _imageFocusNode = FocusNode(debugLabel: 'personImage');

  @override
  void dispose() {
    _scrollController.dispose();
    _imageFocusNode.dispose();
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

  static const int _maxBioLength = 500;

  String _truncatedBio(String bio) {
    if (bio.length <= _maxBioLength) return bio;
    return '${bio.substring(0, _maxBioLength).trimRight()}...';
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
    // Below this, stack the actor image above the bio instead of side by
    // side - matches the compact breakpoint used by MovieDetailBody.
    final compact = MediaQuery.sizeOf(context).width < 600;
    final bio = person?.bio?.trim();
    final bioText = (bio?.isNotEmpty ?? false)
        ? (_bioExpanded ? bio! : _truncatedBio(bio!))
        : l.personDetailsBioUnavailable;

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
                    ? const Center(child: AppLoadingIndicator())
                    : widget.hasError
                    ? Text(l.personDetailsError)
                    : compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _actorImage(person, scale),
                          const SizedBox(height: 16),
                          _animatedBio(context, bioText),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _actorImage(person, scale),
                          const SizedBox(width: 16),
                          Expanded(child: _animatedBio(context, bioText)),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DetailRowHeader(
                      icon: Icons.movie,
                      label: l.personDetailsFilmography,
                    ),
                    if (widget.includeLibraryFilter && allCredits.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _LibraryFilterSwitch(
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
            if (compact)
              SliverLayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth =
                      constraints.crossAxisExtent -
                      MediaBrowsingMetrics.contentPadding * 2;
                  final columnCount = _posterColumnCount(
                    availableWidth,
                    scale,
                  );
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
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(
                  MediaBrowsingMetrics.contentPadding,
                ),
                sliver: SliverToBoxAdapter(
                  // Keyed by filter state so toggling starts the strip with
                  // fresh internal focus/scroll state for what is now a
                  // different item at the same index.
                  child: PosterStrip<FilmographyCredit>(
                    key: ValueKey('person/filmography-strip/$filterActive'),
                    debugLabel: 'personFilmographyStrip',
                    items: credits,
                    itemKey: (credit) => credit.tmdbId,
                    title: (credit) => credit.title,
                    subtitle: (credit) => credit.year,
                    posterUrl: (credit) => credit.posterUrl,
                    fallbackIcon: (credit) =>
                        credit.isSeries ? Icons.tv : Icons.movie,
                    // See _creditCard - `inLibrary` only means anything when
                    // includeLibraryFilter is true (Xtream callers);
                    // AIOStreams callers treat every credit as available.
                    available: (credit) =>
                        !widget.includeLibraryFilter || credit.inLibrary,
                    onTap: (credit) => widget.onOpenCredit?.call(credit),
                    onNavigateUp: _imageFocusNode.requestFocus,
                    autofocus: true,
                  ),
                ),
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

  Widget _animatedBio(BuildContext context, String bioText) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topLeft,
      child: Text(bioText, style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  // Styled like a Continue Watching poster tile (MediaPreviewCard) rather
  // than a plain circular avatar - same corner radius, and the outer
  // DpadInkWell's clip (not a raw ClipOval) does the rounding so the focus
  // glow matches the image edge. Also focusable so D-pad Up from the grid's
  // top row has a target to land on above it - the Focus wrapper around the
  // header owns scrolling it back into view (full scroll-to-top, not "just
  // enough to reveal"), which is why autoScroll stays false here: DpadInkWell's
  // default autoScroll fires its own ensureVisible (partial-reveal) scroll on
  // the same focus change, and that second animateTo overrides the tail of
  // the Focus wrapper's animateTo(0) before it settles, so the page stops
  // short of the top. Same fix as AppButton's autoScroll: false inside
  // RowScrollRegion (series_detail_widgets.dart) - exactly one thing may own
  // this ScrollController's animation.
  //
  // Tapping it toggles the bio (rendered alongside/below it) between its
  // truncated preview and the full text.
  Widget _actorImage(PersonDetails? person, double scale) {
    return DpadInkWell(
      focusNode: _imageFocusNode,
      autoScroll: false,
      onTap: () => setState(() => _bioExpanded = !_bioExpanded),
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
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

/// Switch toggle above the filmography grid, filtering credits down to what
/// exists in the caller's playlist library. Matches the real-`Switch` style
/// used by `SettingsSwitchRow` (`lib/features/settings/settings_ui.dart`)
/// instead of the project's stadium-pill idiom, at the user's request.
class _LibraryFilterSwitch extends StatelessWidget {
  const _LibraryFilterSwitch({
    required this.showLibraryOnly,
    required this.onChanged,
  });

  final bool showLibraryOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    return DpadInkWell(
      onTap: () => onChanged(!showLibraryOnly),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 12 * scale,
          vertical: 8 * scale,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.personDetailsFilterInLibrary,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
            AppSwitch(value: showLibraryOnly, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
