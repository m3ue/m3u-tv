import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/features/epg/epg_program_details.dart'
    show epgDurationLabel, epgTimeLabel;
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cached_backdrop_image.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// The swipeable spotlight carousel touch layouts can show at the top of
/// Home: a few Continue Watching entries, then the newest movies and series,
/// one full-width slide each. Opt-in (Settings > Layout); TV/desktop use the
/// focus-driven `RichHomeLayout` hero instead.
class HomeSpotlightCarousel extends ConsumerStatefulWidget {
  const HomeSpotlightCarousel({
    super.key,
    required this.enricher,
    required this.includeMovies,
    required this.includeSeries,
    required this.onVodSelect,
    required this.onSeriesSelect,
    required this.onProgressSelect,
    this.autoAdvance = const Duration(seconds: 8),
  });

  final HomeSpotlightEnricher enricher;

  /// Whether Home shows the Movies / Series sections, so the carousel never
  /// features a section the user turned off.
  final bool includeMovies;
  final bool includeSeries;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;
  final void Function(Progress) onProgressSelect;

  /// How long a slide stays before the next one slides in.
  final Duration autoAdvance;

  static const int _continueWatchingSlides = 3;
  static const int _newestPerSection = 4;
  static const int _maxSlides = 8;

  /// Continue Watching first, then movies and series interleaved, capped at
  /// [_maxSlides]. Pure, so the order is testable.
  @visibleForTesting
  static List<HomeSpotlightTarget> buildTargets({
    required List<Progress> progress,
    required List<VodItem> movies,
    required List<Series> series,
  }) {
    final newest = <HomeSpotlightTarget>[];
    for (var i = 0; i < movies.length || i < series.length; i++) {
      if (i < movies.length) newest.add(VodSpotlightTarget(movies[i]));
      if (i < series.length) newest.add(SeriesSpotlightTarget(series[i]));
    }
    return [
      for (final entry in progress.take(_continueWatchingSlides))
        ProgressSpotlightTarget(entry),
      ...newest,
    ].take(_maxSlides).toList(growable: false);
  }

  @override
  ConsumerState<HomeSpotlightCarousel> createState() =>
      _HomeSpotlightCarouselState();
}

class _HomeSpotlightCarouselState extends ConsumerState<HomeSpotlightCarousel> {
  final PageController _pageController = PageController();
  final ValueNotifier<int> _page = ValueNotifier(0);
  Timer? _advance;
  bool _dragging = false;

  Object? _fetchedFor;
  List<VodItem> _movies = const [];
  List<Series> _series = const [];
  List<HomeSpotlightTarget> _targets = const [];

  @override
  void didUpdateWidget(HomeSpotlightCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoAdvance != widget.autoAdvance) _restartAdvance();
  }

  @override
  void dispose() {
    _advance?.cancel();
    _pageController.dispose();
    _page.dispose();
    super.dispose();
  }

  void _fetch(Object key, CatalogRepository repo) {
    _fetchedFor = key;
    unawaited(() async {
      var movies = const <VodItem>[];
      var series = const <Series>[];
      try {
        if (widget.includeMovies) {
          movies = await repo.pageActiveItems<VodItem>(
            kind: kCatalogKindVod,
            sort: CatalogSort.recentDesc,
            offset: 0,
            limit: HomeSpotlightCarousel._newestPerSection,
          );
        }
        if (widget.includeSeries) {
          series = await repo.pageActiveItems<Series>(
            kind: kCatalogKindSeries,
            sort: CatalogSort.recentDesc,
            offset: 0,
            limit: HomeSpotlightCarousel._newestPerSection,
          );
        }
      } on Object catch (error) {
        debugPrint('Home: could not read spotlight items: $error');
      }
      if (!mounted || _fetchedFor != key) return;
      setState(() {
        _movies = movies;
        _series = series;
      });
    }());
  }

  void _syncTargets(List<Progress> progress) {
    final next = HomeSpotlightCarousel.buildTargets(
      progress: progress,
      movies: _movies,
      series: _series,
    );
    final changed = !listEquals(
      next.map((target) => target.key).toList(),
      _targets.map((target) => target.key).toList(),
    );
    _targets = next;
    if (!changed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_page.value >= _targets.length) {
        _page.value = 0;
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      }
      _enrichAround(_page.value);
      _restartAdvance();
    });
  }

  /// Movies only carry a poster until `get_vod_info` lands, so fetch the
  /// shown slide and the next one ahead of the swipe.
  void _enrichAround(int index) {
    for (final i in [index, index + 1]) {
      if (_targets.isEmpty) return;
      final target = _targets[i % _targets.length];
      if (!widget.enricher.needsFetch(target)) continue;
      unawaited(
        widget.enricher.fetch(target).then((_) {
          if (mounted) setState(() {});
        }),
      );
    }
  }

  void _restartAdvance() {
    _advance?.cancel();
    if (_targets.length < 2) return;
    _advance = Timer.periodic(widget.autoAdvance, (_) => _advanceOnce());
  }

  void _advanceOnce() {
    // Home stays mounted behind the other tabs; only move while it shows.
    if (!mounted ||
        _dragging ||
        !_pageController.hasClients ||
        !TickerMode.valuesOf(context).enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final next = (_page.value + 1) % _targets.length;
    if (next == 0) {
      _pageController.jumpToPage(0);
    } else {
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _open(HomeSpotlightTarget target) {
    switch (target) {
      case VodSpotlightTarget(:final item):
        widget.onVodSelect(item);
      case SeriesSpotlightTarget(:final series):
        widget.onSeriesSelect(series);
      case ProgressSpotlightTarget(:final progress):
        widget.onProgressSelect(progress);
      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(catalogRepositoryProvider);
    final vodCategories = ref.watch(vodCategoriesProvider);
    final seriesCategories = ref.watch(seriesCategoriesProvider);
    final dvrContentRevision = ref.watch(dvrContentRevisionProvider);
    final key = (
      repo,
      vodCategories,
      seriesCategories,
      dvrContentRevision,
      widget.includeMovies,
      widget.includeSeries,
    );
    if (key != _fetchedFor) _fetch(key, repo);
    _syncTargets(ref.watch(progressListProvider));

    final targets = _targets;
    // Home leaves the status bar inset to the carousel.
    final statusBarInset = MediaQuery.paddingOf(context).top;
    if (targets.isEmpty) return SizedBox(height: statusBarInset);
    final l = AppLocalizations.of(context);
    final format = HomeSpotlightFormat(
      l10n: l,
      timeOfDay: (time) => epgTimeLabel(context, time),
      duration: (duration) => epgDurationLabel(l, duration),
    );
    final now = DateTime.now();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        final height =
            statusBarInset +
            (constraints.maxWidth * 0.9).clamp(280.0, screenHeight * 0.55);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    _dragging = true;
                  } else if (notification is ScrollEndNotification &&
                      _dragging) {
                    _dragging = false;
                    // A swipe starts the slide's full time over.
                    _restartAdvance();
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: targets.length,
                  onPageChanged: (index) {
                    _page.value = index;
                    _enrichAround(index);
                  },
                  itemBuilder: (context, index) {
                    final target = targets[index];
                    return _CarouselSlide(
                      key: ValueKey(target.key),
                      spotlight: resolveHomeSpotlight(
                        target,
                        format: format,
                        enricher: widget.enricher,
                        now: now,
                      ),
                      isResume: target is ProgressSpotlightTarget,
                      topInset: statusBarInset,
                      onOpen: () => _open(target),
                    );
                  },
                ),
              ),
            ),
            if (targets.length > 1)
              Padding(
                padding: const EdgeInsets.only(
                  top: MediaBrowsingMetrics.itemGap,
                ),
                child: ValueListenableBuilder<int>(
                  valueListenable: _page,
                  builder: (context, page, _) =>
                      _PageDots(count: targets.length, current: page),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CarouselSlide extends StatelessWidget {
  const _CarouselSlide({
    super.key,
    required this.spotlight,
    required this.isResume,
    required this.onOpen,
    this.topInset = 0,
  });

  final HomeSpotlight spotlight;
  final bool isResume;

  /// The status bar the slide's art runs up behind; text stays below it.
  final double topInset;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final art = spotlight.backdropUrl ?? spotlight.toneUrl;
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final hasKicker = spotlight.badge != null || spotlight.kicker != null;

    return DpadInkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null)
            // Fades into the app background rather than a solid colour, so
            // there is no seam where the slide meets the rows.
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.55, 1],
              ).createShader(bounds),
              child: CachedBackdropImage(art),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x99000000)],
                stops: [0.35, 1],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              MediaBrowsingMetrics.pagePadding,
              MediaBrowsingMetrics.pagePadding + topInset,
              MediaBrowsingMetrics.pagePadding,
              MediaBrowsingMetrics.itemGap,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasKicker) ...[
                  Text(
                    [spotlight.badge, spotlight.kicker].nonNulls.join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                ItemTitleHeading(
                  name: spotlight.title,
                  clearLogoUrl: spotlight.clearLogoUrl,
                  logoMaxHeight: wide ? 90 : 60,
                  maxLines: 2,
                ),
                if (spotlight.secondaryTitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    spotlight.secondaryTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ],
                if (spotlight.chips.isNotEmpty) ...[
                  const SizedBox(height: MediaBrowsingMetrics.chipGap),
                  OneLineChips(
                    gap: MediaBrowsingMetrics.chipGap,
                    children: [
                      for (final chip in spotlight.chips)
                        MetadataChip.fromData(shortSpotlightGenre(chip)),
                    ],
                  ),
                ],
                if (spotlight.progress case final progress?) ...[
                  const SizedBox(height: MediaBrowsingMetrics.itemGap),
                  SizedBox(
                    width: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
                if (wide && spotlight.plot != null) ...[
                  const SizedBox(height: MediaBrowsingMetrics.itemGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Text(
                      spotlight.plot!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: MediaBrowsingMetrics.itemGap),
                AppButton(
                  label: isResume ? l.playerResume : l.homeSpotlightMoreInfo,
                  icon: isResume ? Icons.play_arrow : Icons.info_outline,
                  variant: AppButtonVariant.primaryInverted,
                  autoScroll: false,
                  onPressed: onOpen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == current
                  ? colors.primary
                  : colors.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

/// A phone-width slide has room for few genres; the details page lists all.
@visibleForTesting
MetaChipData shortSpotlightGenre(MetaChipData chip) {
  if (chip.kind != MetaChipKind.genre) return chip;
  final genres = chip.label
      .split(',')
      .map((genre) => genre.trim())
      .where((genre) => genre.isNotEmpty)
      .toList();
  if (genres.length <= 2) return chip;
  return MetaChipData.genre(genres.take(2).join(', '));
}

/// Chips on a single line, showing only those that fit whole: a chip too
/// wide for the space left is skipped rather than cut off at the edge.
@visibleForTesting
class OneLineChips extends MultiChildRenderObjectWidget {
  const OneLineChips({required this.gap, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderOneLineChips(gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderOneLineChips renderObject,
  ) {
    renderObject.gap = gap;
  }
}

class _OneLineChipsParentData extends ContainerBoxParentData<RenderBox> {
  bool shown = false;
}

class RenderOneLineChips extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _OneLineChipsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _OneLineChipsParentData> {
  RenderOneLineChips(this._gap);

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _OneLineChipsParentData) {
      child.parentData = _OneLineChipsParentData();
    }
  }

  @override
  void performLayout() {
    final maxWidth = constraints.maxWidth;
    var x = 0.0;
    var height = 0.0;
    final shown = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _OneLineChipsParentData;
      child.layout(const BoxConstraints(), parentUsesSize: true);
      final start = shown.isEmpty ? 0.0 : x + _gap;
      data.shown = start + child.size.width <= maxWidth;
      if (data.shown) {
        data.offset = Offset(start, 0);
        x = start + child.size.width;
        height = math.max(height, child.size.height);
        shown.add(child);
      }
      child = data.nextSibling;
    }
    // Chips of different heights share a centre line.
    for (final chip in shown) {
      final data = chip.parentData! as _OneLineChipsParentData;
      data.offset = Offset(data.offset.dx, (height - chip.size.height) / 2);
    }
    size = constraints.constrain(Size(x, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _OneLineChipsParentData;
      if (data.shown) context.paintChild(child, offset + data.offset);
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _OneLineChipsParentData;
      if (data.shown &&
          result.addWithPaintOffset(
            offset: data.offset,
            position: position,
            hitTest: (result, transformed) =>
                child!.hitTest(result, position: transformed),
          )) {
        return true;
      }
      child = data.previousSibling;
    }
    return false;
  }
}
