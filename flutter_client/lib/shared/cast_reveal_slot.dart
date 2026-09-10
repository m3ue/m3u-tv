import 'dart:async';

import 'package:flutter/material.dart';

/// Holds a zero-height slot until the async-loaded [castRow] arrives *and*
/// the page's push transition has settled, then eases it into place:
/// [AnimatedSize] reflows the surrounding column height while the row itself
/// fades and slides up. Without the hold the cast row pops in and shoves the
/// (bottom-aligned) poster + meta block upward, often mid route-transition,
/// which reads as a stutter.
///
/// Shared by the VOD and AIOStreams movie detail screens so both reveal the
/// cast row the same way.
class CastRevealSlot extends StatefulWidget {
  const CastRevealSlot({super.key, required this.castRow, this.topPadding = 0});

  final Widget? castRow;
  final double topPadding;

  /// Buffer after the route transition completes before the row eases in, so
  /// it never competes with the tail of the page animation.
  static const settleDelay = Duration(milliseconds: 260);

  @override
  State<CastRevealSlot> createState() => _CastRevealSlotState();
}

class _CastRevealSlotState extends State<CastRevealSlot> {
  bool _revealed = false;
  Timer? _timer;
  Animation<double>? _routeAnimation;
  bool _waitingOnRoute = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScheduleReveal();
  }

  @override
  void didUpdateWidget(CastRevealSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScheduleReveal();
  }

  void _maybeScheduleReveal() {
    if (_revealed || _timer != null || _waitingOnRoute) return;
    if (widget.castRow == null) return;

    final animation = ModalRoute.of(context)?.animation;
    final settling =
        animation != null &&
        animation.status != AnimationStatus.completed &&
        animation.status != AnimationStatus.dismissed;
    if (settling) {
      _routeAnimation = animation;
      _waitingOnRoute = true;
      animation.addStatusListener(_onRouteStatus);
      return;
    }
    _startTimer();
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    _waitingOnRoute = false;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer(CastRevealSlot.settleDelay, () {
      if (mounted) setState(() => _revealed = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showRow = _revealed && widget.castRow != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: !showRow
            ? const SizedBox(
                key: ValueKey('cast-empty'),
                width: double.infinity,
              )
            : Padding(
                key: const ValueKey('cast-row'),
                padding: EdgeInsets.only(top: widget.topPadding),
                child: widget.castRow,
              ),
      ),
    );
  }
}
