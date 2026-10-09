import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:dpad/dpad.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:m3u_tv/services/desktop_fullscreen_service.dart';
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

/// macOS renders this app with `titleBarStyle: hidden` (see main.dart's
/// `_configureDesktopWindow`), so the native traffic-light buttons float
/// over the top-left of the window with no OS-reserved space for them.
/// AppShell clears them for its own sidebar/content layout by inserting a
/// top titlebar strip (`_kMacTitlebarInset` in app_shell.dart), but this
/// scaffold backs the top-level VOD/Series/AIOStreams detail routes (see
/// go_router_config.dart's top-level `GoRoute`s), which render *outside*
/// AppShell's subtree entirely and never got that treatment - so the
/// leading back button sat directly under the traffic lights. Shifting it
/// right by the traffic-light cluster's width clears them without
/// disturbing the rest of the AppBar's vertical layout.
bool get _isMacDesktopWindow => !kIsWeb && Platform.isMacOS;
const double _kMacTrafficLightInset = 72;

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
    final macInset =
        _isMacDesktopWindow && !DesktopFullscreenScope.isFullscreenOf(context)
        ? _kMacTrafficLightInset
        : 0.0;
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
          title: _GlassTitle(title: title, scale: scale),
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
          leadingWidth: (56 * scale) + macInset,
          leading: Padding(
            padding: EdgeInsets.fromLTRB(
              8 * scale + macInset,
              8 * scale,
              8 * scale,
              8 * scale,
            ),
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

/// The AppBar title, wrapped in a permanent frosted-glass pill so it stays
/// legible over whatever hero art/content is behind it instead of floating
/// as bare text. Kept as a plain, static decoration (no scroll listener, no
/// `setState`, no animation) deliberately - an earlier version faded the
/// pill in only after scrolling, which meant a per-frame rebuild tied to
/// scroll position; on slower TV hardware that's one more thing competing
/// with the page's own transition animation for frame budget, for a look
/// that's barely different from "always on".
class _GlassTitle extends StatelessWidget {
  const _GlassTitle({required this.title, required this.scale});

  final String title;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 14 * scale,
            vertical: 6 * scale,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF09090b).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: theme.appBarTheme.titleTextStyle,
          ),
        ),
      ),
    );
  }
}
