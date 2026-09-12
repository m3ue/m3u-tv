import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Screen space [ItemDetailScaffold]'s floating AppBar actually occupies
/// (toolbar + status bar/notch inset), scaled the same way the AppBar itself
/// is. The Scaffold renders `extendBodyBehindAppBar: true` with a
/// transparent bar so the hero backdrop can show through and scroll behind
/// it - detail bodies need this to reserve a matching *scrollable* top inset
/// (not a fixed one) so content can carry on scrolling up behind the bar
/// instead of stopping at a padded container short of it.
double detailAppBarHeight(BuildContext context) {
  final scale = FontSizeScope.scaleOf(context);
  return kToolbarHeight * scale + MediaQuery.paddingOf(context).top;
}

/// Shared outer chrome for standalone item detail screens (VOD, Series,
/// AIOStreams movie/series). Provides the back-button AppBar and the
/// sidebar-edge DpadRegion wiring.
///
/// Keeping this in one place means layout/behavior changes here (e.g.
/// adding a rating or cast row) show up consistently across every detail
/// screen instead of needing to be copied into each one.
///
/// The sidebar-hide/full-screen transition itself is *not* driven from here
/// — AppShell's `_pushDetail(..., fullScreen: true)` flips that state
/// synchronously around the push/pop instead of this widget announcing
/// itself from initState/dispose, which is unavoidably a frame (or more)
/// behind the moment navigation was requested and reads as a layout snap
/// mid-transition rather than one smooth motion.
class ItemDetailScaffold extends StatelessWidget {
  const ItemDetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.onSidebarActivate,
    this.onBackButtonFocused,
  });

  final String title;
  final Widget body;
  final VoidCallback? onSidebarActivate;

  /// Fires when the back button takes D-pad focus - callers whose body owns
  /// a page-level [ScrollController] (Series' full-page scroll) use this to
  /// snap back to the top, since the button sits outside that scroll region
  /// entirely and would otherwise leave the page stranded wherever it was.
  final VoidCallback? onBackButtonFocused;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        // The AppBar floats transparently over the hero backdrop instead of
        // sitting in its own opaque strip, so the poster/backdrop can scroll
        // up directly behind it (see `detailAppBarHeight`) rather than being
        // clipped by a padded container short of it.
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
          elevation: 0,
          // AppBar's default toolbarHeight (kToolbarHeight, 56) is fixed and
          // unscaled - without scaling it too, the leading button's now
          // larger padding + icon (below) get squeezed into that fixed
          // height, and the GradientBorderEffect stadium border sizes to
          // the squeezed/clipped bounds instead of the button's real size.
          toolbarHeight: kToolbarHeight * scale,
          leadingWidth: 56 * scale,
          leading: Padding(
            padding: EdgeInsets.all(8 * scale),
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) onBackButtonFocused?.call();
              },
              child: DpadFocusable(
                onSelect: () => Navigator.of(context).maybePop(),
                effects: const [
                  GradientBorderEffect(
                    borderRadius: BorderRadius.all(Radius.circular(50)),
                  ),
                ],
                child: IconButton(
                  icon: Icon(Icons.arrow_back, size: 24 * scale),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ),
        body: body,
      ),
    );
  }
}
