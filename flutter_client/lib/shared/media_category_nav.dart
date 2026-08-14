import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Search + category filter UI shared by media-browsing screens (VOD,
/// Series, Live TV, Requests), with two presentations selected by
/// [useSidebarLayout] — mirrors `RowActionMenu`'s caller-supplied boolean
/// rather than resolving device type internally:
///
/// * **Sidebar layout** (`true` — TV/desktop): a persistent vertical strip
///   rendered between the app's sidebar and the screen's content grid, so
///   both are one d-pad press away instead of requiring a scroll to the top
///   of the grid to reach search/category filtering.
/// * **Stacked layout** (`false` — mobile): the search field stays at the
///   top of the screen as before, and the horizontal category chip bar is
///   replaced by a "Filter" button that pushes [MediaCategoryFilterScreen].
///
/// Callers own their content grid's own [FocusScopeNode]/[DpadRegion] (grid
/// rendering is screen-specific) and pass it as [gridFocusScopeNode] so this
/// widget's strip can hand focus off to it on the right edge; symmetrically,
/// the screen's grid region should call `GlobalKey<MediaCategoryNavState>`'s
/// [MediaCategoryNavState.requestFocus] on its own left edge instead of
/// activating the sidebar directly, deferring that to [onSidebarActivate]
/// which only the strip's own left edge should trigger.
class MediaCategoryNav extends StatefulWidget {
  const MediaCategoryNav({
    super.key,
    required this.useSidebarLayout,
    required this.query,
    required this.onQueryChanged,
    required this.searchHint,
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    required this.filterButtonLabel,
    required this.filterScreenTitle,
    this.categoryCounts,
    this.leading,
    this.trailing,
    this.onSidebarActivate,
    this.gridFocusScopeNode,
    this.memoryKeyPrefix = 'media-category-nav',
    this.searchAutofocus = false,
    this.onEntryFocusScopeReady,
  });

  final bool useSidebarLayout;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String searchHint;
  final bool searchAutofocus;

  /// Empty ⇒ search-only mode: no vertical list on TV, no Filter button on
  /// mobile.
  final List<CategoryTabData> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final String filterButtonLabel;
  final String filterScreenTitle;

  /// Per-tab item counts (by [CategoryTabData.id]) shown on
  /// [MediaCategoryFilterScreen]'s rows. Screens compute this themselves —
  /// the underlying category models carry no count field.
  final Map<String, int>? categoryCounts;

  /// e.g. Live TV's view-mode toggle icon.
  final Widget? leading;

  /// e.g. Live TV's Multiview pill button.
  final Widget? trailing;

  /// TV/desktop only: the strip's own left edge activates the sidebar.
  final VoidCallback? onSidebarActivate;

  /// TV/desktop only: the caller's content-grid region, so the strip's
  /// right edge can hand focus back to it.
  final FocusScopeNode? gridFocusScopeNode;

  final String memoryKeyPrefix;

  /// TV/desktop only: called once with the strip's own [FocusScopeNode] so
  /// the caller (ultimately AppShell) can always re-enter here first when
  /// the sidebar deactivates, instead of wherever focus was last restored to
  /// by Flutter's own sibling-scope memory. See
  /// `AppShell._deactivateSidebar` for why that matters.
  final ValueChanged<FocusScopeNode>? onEntryFocusScopeReady;

  @override
  State<MediaCategoryNav> createState() => MediaCategoryNavState();
}

class MediaCategoryNavState extends State<MediaCategoryNav> {
  final FocusScopeNode _stripFocusNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    if (widget.useSidebarLayout) {
      widget.onEntryFocusScopeReady?.call(_stripFocusNode);
    }
  }

  @override
  void dispose() {
    _stripFocusNode.dispose();
    super.dispose();
  }

  /// Moves d-pad focus into the strip, restoring whichever item was last
  /// focused inside it. Call from a content grid's own left-edge `onEdge`
  /// when [MediaCategoryNav.useSidebarLayout] is true.
  void requestFocus() => _stripFocusNode.requestFocus();

  void _handleStripEdge(TraversalDirection direction) {
    if (direction == TraversalDirection.left) {
      widget.onSidebarActivate?.call();
    } else if (direction == TraversalDirection.right) {
      widget.gridFocusScopeNode?.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.useSidebarLayout
        ? _buildSidebarLayout(context)
        : _buildStackedLayout(context);
  }

  Widget _buildSidebarLayout(BuildContext context) {
    return SizedBox(
      width: MediaBrowsingMetrics.interstitialNavWidth,
      child: FocusScope(
        node: _stripFocusNode,
        child: DpadRegion(
          memoryKey: '${widget.memoryKeyPrefix}/strip',
          horizontalEdge: DpadEdgeBehavior.stop,
          onEdge: _handleStripEdge,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              MediaBrowsingMetrics.contentPadding,
              MediaBrowsingMetrics.contentPadding,
              MediaBrowsingMetrics.contentPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InlineMediaSearchField(
                  query: widget.query,
                  hintText: widget.searchHint,
                  onChanged: widget.onQueryChanged,
                  autofocus: widget.searchAutofocus,
                  // TV/desktop only: this field sits in the same d-pad
                  // strip as the category list, so plain d-pad traversal
                  // passing over it must not open the keyboard — see
                  // InlineMediaSearchField.activateOnSelect.
                  activateOnSelect: true,
                ),
                if (widget.leading != null) ...[
                  const SizedBox(height: MediaBrowsingMetrics.chipGap),
                  widget.leading!,
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(height: MediaBrowsingMetrics.chipGap),
                  widget.trailing!,
                ],
                if (widget.tabs.isNotEmpty) ...[
                  const SizedBox(height: MediaBrowsingMetrics.itemGap),
                  Expanded(
                    child: VerticalCategoryList(
                      tabs: widget.tabs,
                      selectedId: widget.selectedId,
                      onSelected: widget.onSelected,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStackedLayout(BuildContext context) {
    final hasControls =
        widget.leading != null ||
        widget.trailing != null ||
        widget.tabs.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        MediaBrowsingMetrics.contentPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InlineMediaSearchField(
            query: widget.query,
            hintText: widget.searchHint,
            onChanged: widget.onQueryChanged,
            autofocus: widget.searchAutofocus,
          ),
          if (hasControls) ...[
            const SizedBox(height: MediaBrowsingMetrics.chipGap),
            Row(
              children: [
                if (widget.leading != null) ...[
                  Expanded(child: widget.leading!),
                  const SizedBox(width: MediaBrowsingMetrics.chipGap),
                ],
                if (widget.tabs.isNotEmpty)
                  Expanded(
                    child: AppButton(
                      label: widget.filterButtonLabel,
                      icon: Icons.filter_list,
                      onPressed: () => _openFilterScreen(context),
                    ),
                  ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: MediaBrowsingMetrics.chipGap),
                  Expanded(child: widget.trailing!),
                ],
              ],
            ),
            const SizedBox(height: MediaBrowsingMetrics.chipGap),
          ],
        ],
      ),
    );
  }

  Future<void> _openFilterScreen(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      PageRouteBuilder<String>(
        // Mirrors go_router_config.dart's `_slidePage`: an opaque backing
        // color (the shared TV-layout gradient's dominant end tone) plus a
        // pure slide, no fade. Without this, a raw MaterialPageRoute uses
        // Material 3's default fade transition over a transparent Scaffold
        // (scaffoldBackgroundColor is transparent app-wide, relying on
        // AppShell's shared gradient to show through) and briefly renders
        // see-through during the push.
        pageBuilder: (context, animation, secondaryAnimation) => Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF09090b)),
            MediaCategoryFilterScreen(
              title: widget.filterScreenTitle,
              tabs: widget.tabs,
              selectedId: widget.selectedId,
              counts: widget.categoryCounts,
            ),
          ],
        ),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    );
    if (result != null) widget.onSelected(result);
  }
}

/// Vertical counterpart to [ScrollableCategoryBar] for the TV/desktop strip
/// — a dedicated widget rather than a `scrollDirection` parameter on
/// [ScrollableCategoryBar], since that widget's horizontal-specific `Row` +
/// fixed 36px height layout doesn't translate to a vertical list.
class VerticalCategoryList extends StatelessWidget {
  const VerticalCategoryList({
    required this.tabs,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<CategoryTabData> tabs;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: tabs.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: MediaBrowsingMetrics.chipGap),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return SizedBox(
            width: double.infinity,
            child: CategoryFilterChip(
              label: tab.name,
              isSelected: selectedId == tab.id,
              onTap: () => onSelected(tab.id),
            ),
          );
        },
      ),
    );
  }
}

/// Mobile-only pushed screen listing categories with their item counts,
/// opened from [MediaCategoryNav]'s "Filter" button. Pops with the tapped
/// [CategoryTabData.id], or `null` if dismissed without a selection.
class MediaCategoryFilterScreen extends StatelessWidget {
  const MediaCategoryFilterScreen({
    super.key,
    required this.title,
    required this.tabs,
    required this.selectedId,
    this.counts,
  });

  final String title;
  final List<CategoryTabData> tabs;
  final String selectedId;
  final Map<String, int>? counts;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final count = counts?[tab.id];
          return ListTile(
            title: Text(tab.name),
            selected: tab.id == selectedId,
            trailing: count == null
                ? const Icon(Icons.chevron_right)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$count',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
            onTap: () => Navigator.of(context).pop(tab.id),
          );
        },
      ),
    );
  }
}
