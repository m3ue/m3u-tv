import 'dart:async';

import 'package:flutter/material.dart';
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
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: heroHeight),
                ?header,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      MediaBrowsingMetrics.pagePadding,
                      MediaBrowsingMetrics.contentPadding,
                      MediaBrowsingMetrics.pagePadding,
                      MediaBrowsingMetrics.pagePadding,
                    ),
                    children: [
                      for (final row in rows) _DockOnFocus(child: row),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Scrolls the row list so the focused row sits directly under the hero
/// (top-aligned), the way streaming apps dock the active rail.
///
/// The card's own DpadFocusable auto-scroll also animates this list
/// (minimally, just into view) from a post-frame callback; the microtask
/// queued here runs after every post-frame callback, so this alignment is
/// the one that wins instead of the two animations fighting.
class _DockOnFocus extends StatelessWidget {
  const _DockOnFocus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scheduleMicrotask(() {
            if (!context.mounted) return;
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          });
        });
      },
      child: child,
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
    if (url == null) return;
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
    final surface = Theme.of(context).colorScheme.surface;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _tone ?? Colors.transparent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, tone, child) {
        final wash = tone ?? Colors.transparent;
        // Gradients fade into the wash where there is one, and into the
        // page surface before the first tone resolves.
        final fade = (tone == null || tone.a == 0) ? surface : wash;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: wash),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: widget.artHeight,
              child: child!,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: widget.artHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        fade.withValues(alpha: 0.96),
                        fade.withValues(alpha: 0.7),
                        fade.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.42, 0.75],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: widget.artHeight,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        fade.withValues(alpha: 0),
                        fade.withValues(alpha: 0.35),
                        fade,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: Align(
        alignment: Alignment.topRight,
        child: FractionallySizedBox(
          widthFactor: 0.72,
          child: _CrossfadeBackdrop(url: widget.spotlight?.backdropUrl),
        ),
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
      return;
    }
    // Drop any layer that never finished loading (focus moved on before it
    // decoded); keep the newest loaded one underneath as the hold frame.
    final base = _layers.lastWhere(_loaded.contains, orElse: () => '');
    _layers
      ..clear()
      ..addAll([if (base.isNotEmpty && base != url) base, url]);
    _loaded.removeWhere((loaded) => !_layers.contains(loaded));
  }

  void _onLoaded(String url) {
    if (!mounted || !_layers.contains(url)) return;
    setState(() => _loaded.add(url));
  }

  void _onFadeEnd(String url) {
    if (!mounted || _layers.isEmpty || _layers.last != url) return;
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
            opacity: _loaded.contains(url) ? 1 : 0,
            duration: _fade,
            curve: Curves.easeOut,
            onEnd: () => _onFadeEnd(url),
            child: CachedBackdropImage(url, onLoaded: () => _onLoaded(url)),
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
