import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/gradient_border_effect.dart';

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
  });

  final String title;
  final Widget body;
  final VoidCallback? onSidebarActivate;

  @override
  Widget build(BuildContext context) {
    return DpadRegion(
      horizontalEdge: DpadEdgeBehavior.stop,
      onEdge: (direction) {
        if (direction == TraversalDirection.left) {
          onSidebarActivate?.call();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          automaticallyImplyLeading: false,
          leadingWidth: 56,
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: DpadFocusable(
              onSelect: () => Navigator.of(context).maybePop(),
              effects: const [
                GradientBorderEffect(
                  borderRadius: BorderRadius.all(Radius.circular(50)),
                ),
              ],
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
        body: body,
      ),
    );
  }
}
