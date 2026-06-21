import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

class CategoryTabData {
  const CategoryTabData({required this.id, required this.name});

  final String id;
  final String name;
}

class MediaBrowsingMetrics {
  const MediaBrowsingMetrics._();

  static const double pagePadding = 24;
  static const double contentPadding = 16;
  static const double itemGap = 12;
  static const double chipGap = 8;
  static const double chipRadius = 20;
  static const double cardRadius = 12;
  static const double posterRadius = 8;
  static const double logoSize = 56;
  static const double previewCardWidth = 172;
  static const double previewCardHeight = 148;
  static const double posterCardWidth = 180;
  static const double posterCardHeight = 300;
  // Landscape "Continue Watching" cards: 16:9 thumbnail + text area.
  static const double landscapeCardWidth = 280;
  static const double landscapeCardHeight = 205; // 157.5 (9/16×280) + 47 text
}

class InlineMediaSearchField extends StatefulWidget {
  const InlineMediaSearchField({
    required this.query,
    required this.onChanged,
    this.hintText = 'Search...',
    this.autofocus = false,
    this.focusNode,
    this.textInputAction = TextInputAction.search,
    super.key,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final String hintText;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction textInputAction;

  @override
  State<InlineMediaSearchField> createState() => _InlineMediaSearchFieldState();
}

class _InlineMediaSearchFieldState extends State<InlineMediaSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(InlineMediaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: widget.query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: _clear,
              ),
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

class ResilientMediaImage extends StatelessWidget {
  const ResilientMediaImage({
    required this.imageUrl,
    required this.fallbackIcon,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.aspectRatio,
    this.fallbackTitle,
    this.borderRadius = MediaBrowsingMetrics.posterRadius,
    this.backgroundColor,
    super.key,
  });

  final String? imageUrl;
  final IconData fallbackIcon;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double? aspectRatio;
  final String? fallbackTitle;
  final double borderRadius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = _MediaImageFallback(
      icon: fallbackIcon,
      title: fallbackTitle,
    );
    final url = imageUrl;

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor ?? colorScheme.surfaceContainerHighest,
          ),
          child: url == null || url.isEmpty
              ? fallback
              : Image.network(
                  url,
                  fit: fit,
                  width: width,
                  height: height,
                  gaplessPlayback: true,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                        if (wasSynchronouslyLoaded || frame != null) {
                          return child;
                        }
                        return fallback;
                      },
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return fallback;
                  },
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
    if (aspectRatio == null) return image;
    return AspectRatio(aspectRatio: aspectRatio!, child: image);
  }
}

class _MediaImageFallback extends StatelessWidget {
  const _MediaImageFallback({required this.icon, this.title});

  final IconData icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallbackTitle = title;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Icon(icon, size: 48, color: colorScheme.onSurfaceVariant),
        ),
        if (fallbackTitle != null && fallbackTitle.isNotEmpty)
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    colorScheme.surface.withValues(alpha: 0.82),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
                child: Text(
                  fallbackTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ScrollableCategoryBar extends StatefulWidget {
  const ScrollableCategoryBar({
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    this.leading,
    super.key,
  });

  final List<CategoryTabData> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Widget? leading;

  @override
  State<ScrollableCategoryBar> createState() => _ScrollableCategoryBarState();
}

class _ScrollableCategoryBarState extends State<ScrollableCategoryBar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MediaBrowsingMetrics.contentPadding,
        vertical: 8,
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: MediaBrowsingMetrics.chipGap),
          ],
          Expanded(
            child: SizedBox(
              height: 36,
              child: ExcludeSemantics(
                child: ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: widget.tabs.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: MediaBrowsingMetrics.chipGap),
                  itemBuilder: (context, index) {
                    final tab = widget.tabs[index];
                    return CategoryFilterChip(
                      label: tab.name,
                      isSelected: widget.selectedId == tab.id,
                      onTap: () => widget.onSelected(tab.id),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryFilterChip extends StatelessWidget {
  const CategoryFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadFocusable(
      onSelect: onTap,
      effects: const [
        GradientBorderEffect(
          borderRadius: BorderRadius.all(
            Radius.circular(MediaBrowsingMetrics.chipRadius),
          ),
        ),
      ],
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.chipRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MediaBrowsingMetrics.chipRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScrollbarGridView extends StatefulWidget {
  const ScrollbarGridView({
    required this.itemCount,
    required this.itemBuilder,
    required this.gridDelegate,
    this.padding = const EdgeInsets.all(MediaBrowsingMetrics.contentPadding),
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry padding;

  @override
  State<ScrollbarGridView> createState() => _ScrollbarGridViewState();
}

class _ScrollbarGridViewState extends State<ScrollbarGridView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: GridView.builder(
          controller: _controller,
          padding: widget.padding,
          gridDelegate: widget.gridDelegate,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}

class ScrollbarListView extends StatefulWidget {
  const ScrollbarListView({
    required this.itemCount,
    required this.itemBuilder,
    this.padding,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry? padding;

  @override
  State<ScrollbarListView> createState() => _ScrollbarListViewState();
}

class _ScrollbarListViewState extends State<ScrollbarListView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        trackVisibility: true,
        child: ListView.builder(
          controller: _controller,
          padding: widget.padding,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}

class MediaPreviewItem {
  const MediaPreviewItem({
    required this.title,
    required this.fallbackIcon,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
    this.imageFit = BoxFit.cover,
    this.imageAspectRatio,
    this.fallbackTitle,
    this.imagePadding = EdgeInsets.zero,
    this.imageBackgroundColor,
    this.progressFraction,
    this.overlayBadges = const <String>[],
    this.overlayLabel,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final IconData fallbackIcon;
  final VoidCallback onTap;
  final BoxFit imageFit;
  final double? imageAspectRatio;
  final String? fallbackTitle;
  final EdgeInsets imagePadding;
  final Color? imageBackgroundColor;

  /// 0.0–1.0 progress shown as a bar along the bottom of the image.
  final double? progressFraction;

  /// Short text labels rendered as chips overlaid on the image (right-aligned).
  final List<String> overlayBadges;

  /// Optional label shown left-aligned opposite the overlay badges.
  final String? overlayLabel;
}

class MediaPreviewSection extends StatefulWidget {
  const MediaPreviewSection({
    required this.title,
    required this.emptyLabel,
    required this.items,
    this.posterStyle = false,
    this.landscapeStyle = false,
    this.onSidebarActivate,
    super.key,
  });

  final String title;
  final String emptyLabel;
  final List<MediaPreviewItem> items;
  final bool posterStyle;
  final bool landscapeStyle;
  final VoidCallback? onSidebarActivate;

  @override
  State<MediaPreviewSection> createState() => _MediaPreviewSectionState();
}

class _MediaPreviewSectionState extends State<MediaPreviewSection> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = widget.items.take(12).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scale card dimensions proportionally on wide TV screens (e.g. tvOS
        // logical 1920px → scale 1.5). Clamped to 1.0 minimum so mobile and
        // standard-density Android TV are unaffected.
        final scale = (constraints.maxWidth / 1280.0).clamp(1.0, 2.0);
        final double baseWidth;
        final double baseHeight;
        if (widget.landscapeStyle) {
          baseWidth = MediaBrowsingMetrics.landscapeCardWidth;
          baseHeight = MediaBrowsingMetrics.landscapeCardHeight;
        } else if (widget.posterStyle) {
          baseWidth = MediaBrowsingMetrics.posterCardWidth;
          baseHeight = MediaBrowsingMetrics.posterCardHeight;
        } else {
          baseWidth = MediaBrowsingMetrics.previewCardWidth;
          baseHeight = MediaBrowsingMetrics.previewCardHeight;
        }
        final cardWidth = baseWidth * scale;
        final cardHeight = baseHeight * scale;

        return Padding(
          padding: const EdgeInsets.only(bottom: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: MediaBrowsingMetrics.chipGap),
              if (visibleItems.isEmpty)
                Text(widget.emptyLabel)
              else
                SizedBox(
                  height: cardHeight + 16,
                  // ExcludeSemantics prevents the tvOS framework bug where
                  // ScrollableState.setIgnorePointer calls markNeedsSemanticsUpdate
                  // during the semantics flush phase, causing an assertion crash
                  // when scrolling quickly.
                  child: ExcludeSemantics(
                    child: DpadRegion(
                      memoryKey: 'preview-row/${widget.title}',
                      horizontalEdge: DpadEdgeBehavior.stop,
                      onEdge: (direction) {
                        if (direction == TraversalDirection.left) {
                          widget.onSidebarActivate?.call();
                        }
                      },
                      child: Scrollbar(
                        controller: _controller,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: ListView.separated(
                          controller: _controller,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: visibleItems.length,
                          separatorBuilder: (_, _) => const SizedBox(
                            width: MediaBrowsingMetrics.itemGap,
                          ),
                          itemBuilder: (context, index) => MediaPreviewCard(
                            item: visibleItems[index],
                            posterStyle: widget.posterStyle,
                            landscapeStyle: widget.landscapeStyle,
                            autofocus: index == 0,
                            cardWidth: cardWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MediaPreviewCard extends StatefulWidget {
  const MediaPreviewCard({
    required this.item,
    this.posterStyle = false,
    this.landscapeStyle = false,
    this.autofocus = false,
    this.cardWidth,
    super.key,
  });

  final MediaPreviewItem item;
  final bool posterStyle;
  final bool landscapeStyle;
  final bool autofocus;
  final double? cardWidth;

  @override
  State<MediaPreviewCard> createState() => _MediaPreviewCardState();
}

class _MediaPreviewCardState extends State<MediaPreviewCard> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final isRating = item.subtitle?.startsWith('★') ?? false;
    final width =
        widget.cardWidth ??
        (widget.landscapeStyle
            ? MediaBrowsingMetrics.landscapeCardWidth
            : widget.posterStyle
            ? MediaBrowsingMetrics.posterCardWidth
            : MediaBrowsingMetrics.previewCardWidth);

    final card = Material(
      color: colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // Explicitly request focus so that navigation (pushNamed / player
          // open) can snapshot primaryFocus and restore it on pop/close.
          // DpadFocusable.onTapDown also calls requestFocus, but that fires
          // asynchronously and may lose the race on fast taps.
          _focusNode.requestFocus();
          item.onTap();
        },
        child: widget.landscapeStyle
            ? _buildLandscapeContent(context, colorScheme, width)
            : _buildDefaultContent(context, colorScheme, isRating),
      ),
    );

    return DpadFocusable(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onSelect: item.onTap,
      child: SizedBox(width: width, child: card),
    );
  }

  Widget _buildLandscapeContent(
    BuildContext context,
    ColorScheme colorScheme,
    double width,
  ) {
    final item = widget.item;
    final imageHeight = width * 9 / 16;
    final hasBadges = widget.item.overlayBadges.isNotEmpty;
    final hasProgress = widget.item.progressFraction != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: widget.item.imagePadding,
          child: SizedBox(
            width: width,
            height: imageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ResilientMediaImage(
                  imageUrl: item.imageUrl,
                  fallbackIcon: item.fallbackIcon,
                  width: width,
                  height: imageHeight,
                  fit: item.imageFit,
                  fallbackTitle: item.fallbackTitle,
                  backgroundColor: item.imageBackgroundColor,
                  borderRadius: 0,
                ),
                if (hasBadges || hasProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: imageHeight * 0.45,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (widget.item.overlayLabel != null)
                  Positioned(
                    left: 6,
                    bottom: hasProgress ? 9 : 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          widget.item.overlayLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                if (hasBadges)
                  Positioned(
                    right: 6,
                    bottom: hasProgress ? 9 : 6,
                    child: Row(
                      children: [
                        for (final badge in widget.item.overlayBadges)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                child: Text(
                                  badge,
                                  style:
                                      Theme.of(
                                        context,
                                      ).textTheme.labelSmall?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (hasProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: widget.item.progressFraction,
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      color: colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultContent(
    BuildContext context,
    ColorScheme colorScheme,
    bool isRating,
  ) {
    final item = widget.item;
    final posterStyle = widget.posterStyle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: widget.item.imagePadding,
            child: ResilientMediaImage(
              imageUrl: item.imageUrl,
              fallbackIcon: item.fallbackIcon,
              fit: item.imageFit,
              aspectRatio: item.imageAspectRatio,
              fallbackTitle: item.fallbackTitle,
              backgroundColor: item.imageBackgroundColor,
              borderRadius: 0,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: posterStyle ? FontWeight.normal : FontWeight.w700,
                ),
                maxLines: posterStyle ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: posterStyle && isRating
                        ? const Color(0xFFFFCC00)
                        : colorScheme.onSurfaceVariant,
                    fontWeight: posterStyle && isRating
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
