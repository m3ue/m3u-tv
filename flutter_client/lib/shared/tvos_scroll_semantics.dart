import 'dart:ui' show SemanticsAction, SemanticsActionEventCallback;

import 'package:flutter/material.dart';

/// tvOS only: keeps UIKit's focus engine from scrolling Flutter scrollables.
///
/// The iOS/tvOS engine mirrors every scrollable whose semantics node has
/// `hasImplicitScrolling` as a native `UIScrollView` registered with the
/// UIFocusSystem (`FlutterScrollableSemanticsObject`). On tvOS that focus
/// engine is always running, so when the Siri Remote moves the native mirror
/// it sends `SemanticsAction.scrollToOffset` back to Flutter - often
/// synchronously from inside `FlutterView.updateSemantics`, where the
/// resulting `jumpTo` throws `!owner!._debugDoingSemantics`, and in every
/// build mode it yanks the row back to a stale offset mid D-pad scroll (the
/// "moves a bit then stops" strip, a row scrolling while focus is in another
/// one).
///
/// Implicit scrolling only exists so the platform can scroll for the user;
/// on TV the D-pad owns every scroll, so it is turned off app-wide here and
/// the engine never creates the native mirrors. VoiceOver's own scroll
/// gestures use the separate scrollUp/Down/Left/Right actions and still work.
class TvosScrollBehavior extends MaterialScrollBehavior {
  const TvosScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      _NoImplicitScrollPhysics(parent: super.getScrollPhysics(context));
}

class _NoImplicitScrollPhysics extends ScrollPhysics {
  const _NoImplicitScrollPhysics({super.parent});

  @override
  _NoImplicitScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _NoImplicitScrollPhysics(parent: buildParent(ancestor));

  @override
  bool get allowImplicitScrolling => false;
}

/// tvOS backstop for [TvosScrollBehavior]: a scrollable that passes its own
/// `physics` replaces the behaviour's outermost physics and keeps implicit
/// scrolling (and its native mirror), so drop any `scrollToOffset` that still
/// arrives instead of letting it move a D-pad-driven scroll view.
SemanticsActionEventCallback ignoreNativeScrollToOffset(
  SemanticsActionEventCallback? handler,
) {
  return (event) {
    if (event.type == SemanticsAction.scrollToOffset) return;
    handler?.call(event);
  };
}
