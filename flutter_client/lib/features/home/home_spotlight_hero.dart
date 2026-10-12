import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/features/epg/epg_program_details.dart'
    show epgDurationLabel, epgTimeLabel;
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/shared/cached_backdrop_image.dart';
import 'package:m3u_tv/shared/dominant_backdrop_color.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/system_clock.dart';

/// The rich Home layout: a fixed spotlight hero (backdrop, colour-matched
/// wash, title and metadata for the focused card) over the scrolling [rows].
/// The backdrop bleeds full-width behind everything and fades into the
/// colour wash; only [rows] scroll, the hero never moves.
class RichHomeLayout extends StatelessWidget {
  const RichHomeLayout({
    super.key,
    required this.controller,
    required this.enricher,
    required this.rows,
    this.header,
  });

  final HomeSpotlightController controller;
  final HomeSpotlightEnricher enricher;
  final List<Widget> rows;

  /// Pinned above the rows (the offline banner).
  final Widget? header;

  /// Share of the pane the hero's text area takes.
  static const double heroFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = FontSizeScope.scaleOf(context);
        final heroHeight = (constraints.maxHeight * heroFraction).clamp(
          180.0 * scale,
          constraints.maxHeight * 0.55,
        );
        // Only the hero layers listen to the spotlight; the rows sit in a
        // sibling layer so a focus change never rebuilds the row list.
        return Stack(
          fit: StackFit.expand,
          children: [
            _SpotlightScope(
              controller: controller,
              enricher: enricher,
              builder: (context, spotlight) => Stack(
                fit: StackFit.expand,
                children: [
                  _SpotlightBackground(
                    spotlight: spotlight,
                    artHeight: heroHeight + constraints.maxHeight * 0.22,
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: heroHeight,
                    child: _SpotlightInfo(spotlight: spotlight),
                  ),
                  Positioned(
                    top: MediaBrowsingMetrics.pagePadding,
                    right: MediaBrowsingMetrics.pagePadding,
                    child: _SpotlightClock(spotlight: spotlight),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: heroHeight),
                ?header,
                Expanded(child: _DockedRows(rows: rows)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// The rows under the hero, docked so the focused row sits directly below
/// it (top-aligned), the way streaming apps lock the active rail.
///
/// Deliberately not a vertical [Scrollable]: every DpadFocusable card runs
/// its own padded auto-scroll on all scrollable ancestors, and a second
/// scroller animating the same list to a different target made rows jump
/// (worst moving up, and on desktop whenever focus was re-applied). Here the
/// cards' auto-scroll only reaches their own horizontal row, and one animated
/// offset owned by this widget positions the column. Mouse wheel / trackpad
/// drive the same offset; focus that follows the mouse (a click, or a rested
/// hover) doesn't re-dock, so nothing shifts under the cursor - only focus
/// moved by a key (remote / keyboard) docks.
class _DockedRows extends StatefulWidget {
  const _DockedRows({required this.rows});

  final List<Widget> rows;

  @override
  State<_DockedRows> createState() => _DockedRowsState();
}

class _DockedRowsState extends State<_DockedRows> {
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    MediaBrowsingMetrics.pagePadding,
    MediaBrowsingMetrics.contentPadding,
    MediaBrowsingMetrics.pagePadding,
    MediaBrowsingMetrics.pagePadding,
  );
  static const Duration _dockDuration = Duration(milliseconds: 280);
  static const Duration _wheelDuration = Duration(milliseconds: 120);

  final GlobalKey _columnKey = GlobalKey();
  final List<GlobalKey> _rowKeys = [];
  double _offset = 0;
  double _viewportHeight = 0;
  Duration _duration = _dockDuration;

  /// Whether the most recent input was the mouse rather than a key. A hover
  /// moves focus long after the pointer last moved, so a time window can't
  /// tell the two apart; the last input type can.
  bool _pointerIsLastInput = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _pointerIsLastInput = false;
    return false;
  }

  GlobalKey _rowKey(int index) {
    while (_rowKeys.length <= index) {
      _rowKeys.add(GlobalKey());
    }
    return _rowKeys[index];
  }

  double get _maxOffset {
    final column = _columnKey.currentContext?.findRenderObject();
    if (column is! RenderBox || !column.hasSize) return 0;
    final content = column.size.height + _padding.vertical;
    return (content - _viewportHeight).clamp(0.0, double.infinity);
  }

  void _setOffset(double offset, Duration duration) {
    final clamped = offset.clamp(0.0, _maxOffset);
    if ((clamped - _offset).abs() < 0.5) return;
    setState(() {
      _offset = clamped;
      _duration = duration;
    });
  }

  void _onRowFocused(int index) {
    if (_pointerIsLastInput) return;
    // After layout, so a row that just built (first autofocus) has a size.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final row = _rowKeys[index].currentContext?.findRenderObject();
      final column = _columnKey.currentContext?.findRenderObject();
      if (row is! RenderBox || column is! RenderBox) return;
      if (!row.hasSize || !column.hasSize) return;
      final top = row.localToGlobal(Offset.zero, ancestor: column).dy;
      _setOffset(top, _dockDuration);
    });
  }

  void _notePointer(PointerEvent _) => _pointerIsLastInput = true;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _setOffset(_offset + event.scrollDelta.dy, _wheelDuration);
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _notePointer(event);
    _setOffset(_offset - event.localPanDelta.dy, Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: _notePointer,
      onPointerDown: _notePointer,
      onPointerSignal: _onPointerSignal,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewportHeight = constraints.maxHeight;
            return OverflowBox(
              alignment: Alignment.topCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _offset),
                duration: _duration,
                curve: Curves.easeOutCubic,
                builder: (context, offset, child) => Transform.translate(
                  offset: Offset(0, -offset),
                  child: child,
                ),
                child: Padding(
                  padding: _padding,
                  child: Column(
                    key: _columnKey,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.rows.length; i++)
                        Focus(
                          key: _rowKey(i),
                          canRequestFocus: false,
                          skipTraversal: true,
                          onFocusChange: (hasFocus) {
                            if (hasFocus) _onRowFocused(i);
                          },
                          child: widget.rows[i],
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Resolves the controller's target into a [HomeSpotlight], fetching any
/// extras it needs and re-resolving live targets as the EPG and the clock
/// move on.
class _SpotlightScope extends ConsumerStatefulWidget {
  const _SpotlightScope({
    required this.controller,
    required this.enricher,
    required this.builder,
  });

  final HomeSpotlightController controller;
  final HomeSpotlightEnricher enricher;
  final Widget Function(BuildContext context, HomeSpotlight? spotlight) builder;

  @override
  ConsumerState<_SpotlightScope> createState() => _SpotlightScopeState();
}

class _SpotlightScopeState extends ConsumerState<_SpotlightScope> {
  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTargetChanged);
    _onTargetChanged();
  }

  @override
  void didUpdateWidget(_SpotlightScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTargetChanged);
      widget.controller.addListener(_onTargetChanged);
      _onTargetChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTargetChanged);
    _liveTicker?.cancel();
    super.dispose();
  }

  void _onTargetChanged() {
    final target = widget.controller.value;
    // Live programmes roll over and their progress advances; nothing else
    // in the hero is time-based.
    _liveTicker?.cancel();
    _liveTicker = target is ChannelSpotlightTarget
        ? Timer.periodic(const Duration(seconds: 30), (_) {
            if (mounted) setState(() {});
          })
        : null;
    if (mounted) setState(() {});
    if (target == null || !widget.enricher.needsFetch(target)) return;
    unawaited(
      widget.enricher.fetch(target).then((_) {
        if (mounted && widget.controller.value?.key == target.key) {
          setState(() {});
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.controller.value;
    // Only live targets read the EPG; watching it unconditionally would
    // rebuild the hero on every guide sweep chunk.
    final epgService = target is ChannelSpotlightTarget
        ? ref.watch(epgServiceProvider)
        : null;
    final l = AppLocalizations.of(context);
    final spotlight = target == null
        ? null
        : resolveHomeSpotlight(
            target,
            format: HomeSpotlightFormat(
              l10n: l,
              timeOfDay: (time) => epgTimeLabel(context, time),
              duration: (duration) => epgDurationLabel(l, duration),
            ),
            enricher: widget.enricher,
            epgLookup: epgService?.lookupForChannel,
            now: epgService?.now ?? DateTime.now(),
          );
    return widget.builder(context, spotlight);
  }
}

/// Colour wash plus the cross-fading backdrop, anchored top-right and faded
/// out to the left (behind the text) and toward the bottom (behind the
/// rows) with gradients in the wash colour.
class _SpotlightBackground extends StatefulWidget {
  const _SpotlightBackground({
    required this.spotlight,
    required this.artHeight,
  });

  final HomeSpotlight? spotlight;
  final double artHeight;

  @override
  State<_SpotlightBackground> createState() => _SpotlightBackgroundState();
}

class _SpotlightBackgroundState extends State<_SpotlightBackground> {
  Color? _tone;
  String? _toneUrl;

  @override
  void initState() {
    super.initState();
    _resolveTone();
  }

  @override
  void didUpdateWidget(_SpotlightBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveTone();
  }

  void _resolveTone() {
    final url = widget.spotlight?.toneUrl;
    if (url == _toneUrl) return;
    _toneUrl = url;
    // No image at all: fade the glow out rather than keep the last item's
    // colour. (A failed extraction below still keeps it, which reads better
    // than flashing to nothing.) Called from initState/didUpdateWidget, so
    // the build that follows picks this up without a setState.
    if (url == null) {
      _tone = null;
      return;
    }
    unawaited(
      resolveDominantBackdropColor(url).then((color) {
        // Keep the previous tone on failure rather than snapping to black.
        if (!mounted || _toneUrl != url || color == null) return;
        setState(() => _tone = deepBackdropTone(color));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = RepaintBoundary(
      child: _EdgeFade(
        child: _CrossfadeBackdrop(url: widget.spotlight?.backdropUrl),
      ),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // The colour-match wash is a glow strongest behind the art (top
        // right) that fades to nothing toward the rows and the sidebar, so
        // the app's own gradient background shows through instead of a
        // solid fill with hard edges.
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: _tone ?? Colors.transparent),
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          builder: (context, tone, _) {
            final glow = tone ?? Colors.transparent;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.55, -1.1),
                  radius: 1.35,
                  colors: [
                    glow.withValues(alpha: glow.a * 0.95),
                    glow.withValues(alpha: glow.a * 0.55),
                    glow.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.45, 1],
                ),
              ),
            );
          },
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: widget.artHeight,
          child: Align(
            alignment: Alignment.topRight,
            child: FractionallySizedBox(widthFactor: 0.72, child: backdrop),
          ),
        ),
        // Keeps the title/plot legible where they overlap the faded-in art.
        // Smooth on every edge, so it adds no seam of its own.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0x73000000),
                  Color(0x33000000),
                  Color(0x00000000),
                ],
                stops: [0, 0.35, 0.6],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Alpha-masks the backdrop so it dissolves into whatever is behind it: a
/// long fade on the left (under the title and metadata) and toward the
/// bottom (under the rows), plus a short one on the right edge. A plain
/// colour overlay can't do this without leaving a visible seam wherever its
/// colour doesn't exactly match what sits beside the image.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0xFFFFFFFF)],
        stops: [0, 0.3, 0.55],
      ).createShader(bounds),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
          stops: [0, 0.5, 1],
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// Holds the previous backdrop on screen until the next one has decoded,
/// then fades the new one in over it, so moving focus never flashes an
/// empty frame. At most two images are mounted at once.
class _CrossfadeBackdrop extends StatefulWidget {
  const _CrossfadeBackdrop({required this.url});

  final String? url;

  @override
  State<_CrossfadeBackdrop> createState() => _CrossfadeBackdropState();
}

class _CrossfadeBackdropState extends State<_CrossfadeBackdrop> {
  static const Duration _fade = Duration(milliseconds: 380);

  /// Bottom to top. The last entry is the wanted URL.
  final List<String> _layers = [];
  final Set<String> _loaded = {};

  /// URLs that failed to load. A failed top layer fades the held frame out
  /// instead of leaving the previous item's art under the new title - dead
  /// EPG icon URLs (the Live TV fallback) make this common.
  final Set<String> _failed = {};

  bool get _topFailed => _layers.isNotEmpty && _failed.contains(_layers.last);

  @override
  void initState() {
    super.initState();
    final url = widget.url;
    if (url != null) _layers.add(url);
  }

  @override
  void didUpdateWidget(_CrossfadeBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final url = widget.url;
    if (url == oldWidget.url) return;
    if (url == null) {
      _layers.clear();
      _loaded.clear();
      _failed.clear();
      return;
    }
    // Drop any layer that never finished loading (focus moved on before it
    // decoded); keep the newest loaded one underneath as the hold frame.
    final base = _layers.lastWhere(_loaded.contains, orElse: () => '');
    _layers
      ..clear()
      ..addAll([if (base.isNotEmpty && base != url) base, url]);
    _loaded.removeWhere((loaded) => !_layers.contains(loaded));
    _failed.removeWhere((failed) => !_layers.contains(failed));
  }

  void _onError(String url) {
    if (!mounted || !_layers.contains(url)) return;
    setState(() => _failed.add(url));
  }

  void _onLoaded(String url) {
    if (!mounted || !_layers.contains(url)) return;
    setState(() => _loaded.add(url));
  }

  void _onFadeEnd(String url) {
    if (!mounted || _layers.isEmpty) return;
    if (_topFailed) {
      // The held frame has faded out; drop it along with the failed layer.
      setState(() {
        _layers.clear();
        _loaded.clear();
        _failed.clear();
      });
      return;
    }
    if (_layers.last != url) return;
    if (_layers.length == 1) return;
    setState(() {
      _layers.removeRange(0, _layers.length - 1);
      _loaded.removeWhere((loaded) => loaded != url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final url in _layers)
          AnimatedOpacity(
            key: ValueKey(url),
            opacity: !_topFailed && _loaded.contains(url) ? 1 : 0,
            duration: _fade,
            curve: Curves.easeOut,
            onEnd: () => _onFadeEnd(url),
            child: CachedBackdropImage(
              url,
              onLoaded: () => _onLoaded(url),
              onError: () => _onError(url),
            ),
          ),
      ],
    );
  }
}

class _SpotlightInfo extends StatelessWidget {
  const _SpotlightInfo({required this.spotlight});

  final HomeSpotlight? spotlight;

  @override
  Widget build(BuildContext context) {
    final current = spotlight;
    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          MediaBrowsingMetrics.pagePadding * 1.5,
          MediaBrowsingMetrics.pagePadding,
          MediaBrowsingMetrics.pagePadding,
          0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomLeft,
            children: [...previousChildren, ?currentChild],
          ),
          child: current == null
              ? const SizedBox.expand()
              : LayoutBuilder(
                  key: ValueKey(current.key),
                  builder: (context, constraints) => _SpotlightDetails(
                    spotlight: current,
                    maxHeight: constraints.maxHeight,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SpotlightDetails extends StatelessWidget {
  const _SpotlightDetails({required this.spotlight, required this.maxHeight});

  final HomeSpotlight spotlight;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasKicker =
        spotlight.badge != null ||
        spotlight.kicker != null ||
        spotlight.kickerLogoUrl != null;

    return Align(
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width * 0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasKicker) ...[
              _SpotlightKicker(spotlight: spotlight),
              SizedBox(height: 8 * scale),
            ],
            ItemTitleHeading(
              name: spotlight.title,
              clearLogoUrl: spotlight.clearLogoUrl,
              logoMaxHeight: (maxHeight * 0.32).clamp(40.0, 120.0 * scale),
              maxLines: 2,
            ),
            if (spotlight.secondaryTitle != null) ...[
              SizedBox(height: 4 * scale),
              Text(
                spotlight.secondaryTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ],
            if (spotlight.chips.isNotEmpty) ...[
              const SizedBox(height: MediaBrowsingMetrics.itemGap),
              Wrap(
                spacing: MediaBrowsingMetrics.chipGap,
                runSpacing: MediaBrowsingMetrics.chipGap,
                children: [
                  for (final chip in spotlight.chips) MetadataChip(label: chip),
                ],
              ),
            ],
            if (spotlight.progress != null ||
                spotlight.progressLabel != null) ...[
              const SizedBox(height: MediaBrowsingMetrics.itemGap),
              _SpotlightProgress(spotlight: spotlight),
            ],
            if (spotlight.plot != null) ...[
              const SizedBox(height: MediaBrowsingMetrics.itemGap),
              Flexible(
                child: Text(
                  spotlight.plot!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                ),
              ),
            ],
            if (spotlight.footnote != null) ...[
              SizedBox(height: 6 * scale),
              Text(
                spotlight.footnote!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpotlightKicker extends StatelessWidget {
  const _SpotlightKicker({required this.spotlight});

  final HomeSpotlight spotlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final logo = spotlight.kickerLogoUrl;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (spotlight.badge != null) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 6 * scale,
                vertical: 2 * scale,
              ),
              child: Text(
                spotlight.badge!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(width: 10 * scale),
        ],
        if (logo != null) ...[
          ResilientMediaImage(
            imageUrl: logo,
            fallbackIcon: Icons.live_tv,
            width: 40 * scale,
            height: 24 * scale,
            fit: BoxFit.contain,
            borderRadius: 0,
            backgroundColor: Colors.transparent,
          ),
          SizedBox(width: 8 * scale),
        ],
        if (spotlight.kicker != null)
          Flexible(
            child: Text(
              spotlight.kicker!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _SpotlightProgress extends StatelessWidget {
  const _SpotlightProgress({required this.spotlight});

  final HomeSpotlight spotlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final progress = spotlight.progress;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (progress != null) ...[
          SizedBox(
            width: 160 * scale,
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
          SizedBox(width: 12 * scale),
        ],
        if (spotlight.progressLabel != null)
          Flexible(
            child: Text(
              spotlight.progressLabel!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Top-right time readout, matching the player's header: the current time
/// and, when the highlighted item can be played straight away, when it would
/// end ("Ends at"). Sits on a frosted pill so it stays legible over bright
/// backdrops.
class _SpotlightClock extends StatelessWidget {
  const _SpotlightClock({required this.spotlight});

  final HomeSpotlight? spotlight;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF09090b).withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12 * scale),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12 * scale,
              vertical: 6 * scale,
            ),
            child: SystemClock(
              builder: (context, now) {
                final endsAt = _endsAt();
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatClockTime(context, now),
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (endsAt != null)
                      Text(
                        AppLocalizations.of(
                          context,
                        ).playerEndsAt(formatClockTime(context, endsAt)),
                        key: const Key('home-spotlight-ends-at'),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Read against the real current time rather than the clock's
  /// minute-aligned tick, so switching items mid-minute doesn't lag by up to
  /// a minute.
  DateTime? _endsAt() {
    final current = spotlight;
    if (current == null) return null;
    final now = DateTime.now();
    final fixed = current.endsAt?.toLocal();
    if (fixed != null) return fixed.isAfter(now) ? fixed : null;
    final length = current.playLength;
    return length == null || length <= Duration.zero ? null : now.add(length);
  }
}
