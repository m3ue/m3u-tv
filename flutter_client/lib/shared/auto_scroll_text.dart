import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Description text in the height its parent leaves it (capped at
/// [maxLines] when set). Shows whole lines only, fading out the last one when
/// there is more. Once it has been on screen for a moment it slowly scrolls
/// through the rest, pauses at the end, returns to the top and starts over
/// (the way Kodi shows plot text), unless the platform asks for reduced
/// motion. Give it a fresh key per item so each one starts back at the top.
/// Used by the EPG guide preview and the Home spotlight.
class AutoScrollText extends StatefulWidget {
  const AutoScrollText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  static const _restDelay = Duration(seconds: 3);
  static const _endPause = Duration(seconds: 3);
  static const _returnDuration = Duration(milliseconds: 700);
  static const _millisecondsPerLine = 2500;

  final _controller = ScrollController();
  // Whether the text is scrolled to its top / end. The edge fades only
  // change at those two points, so the mask rebuilds there instead of on
  // every frame of the scroll.
  final _edges = ValueNotifier<({bool atTop, bool atEnd})>((
    atTop: true,
    atEnd: false,
  ));
  Timer? _timer;
  bool _running = false;
  double _lineHeight = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateEdges);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _edges.dispose();
    super.dispose();
  }

  void _updateEdges() {
    final position = _controller.position;
    _edges.value = (
      atTop: position.pixels <= 0.5,
      atEnd:
          position.hasContentDimensions &&
          position.pixels >= position.maxScrollExtent - 0.5,
    );
  }

  /// Starts the scroll loop the first time the text is found to overflow.
  void _startLoop() {
    if (_running || MediaQuery.disableAnimationsOf(context)) return;
    _running = true;
    _timer = Timer(_restDelay, _scrollDown);
  }

  Future<void> _scrollDown() async {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final distance = position.maxScrollExtent - position.pixels;
    if (distance <= 0) {
      // A relayout gave the text room after all; build restarts the loop
      // if it overflows again.
      _running = false;
      return;
    }
    await _controller.animateTo(
      position.maxScrollExtent,
      duration: Duration(
        milliseconds: (distance / _lineHeight * _millisecondsPerLine).round(),
      ),
      curve: Curves.linear,
    );
    if (!mounted) return;
    _timer = Timer(_endPause, _scrollUp);
  }

  Future<void> _scrollUp() async {
    if (!mounted || !_controller.hasClients) return;
    await _controller.animateTo(
      0,
      duration: _returnDuration,
      curve: Curves.easeInOut,
    );
    if (!mounted) return;
    _timer = Timer(_restDelay, _scrollDown);
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(widget.text, style: widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final textHeight = painter.height;
        final lineHeight = painter.preferredLineHeight;
        final lineCount = painter.computeLineMetrics().length;
        painter.dispose();
        _lineHeight = lineHeight;

        final maxLines = widget.maxLines;
        // Fit check first: with no height bound and no maxLines there is
        // nothing to scroll within, so the text simply shows in full.
        // heightFactor 1 hugs the text in a loose box (the spotlight's
        // Column); a tight box (the guide preview) still fills its slot.
        if ((!constraints.maxHeight.isFinite ||
                textHeight <= constraints.maxHeight) &&
            (maxLines == null || lineCount <= maxLines)) {
          return Align(
            alignment: Alignment.topLeft,
            heightFactor: 1,
            child: text,
          );
        }
        final fitLines = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / lineHeight).floor()
            : maxLines!;
        final lines = maxLines == null
            ? fitLines
            : math.min(fitLines, maxLines);
        if (lines < 1) return const SizedBox.shrink();
        _startLoop();

        final viewportHeight = lines * lineHeight;
        final fade = math.min(0.5, lineHeight * 0.9 / viewportHeight);
        return Align(
          alignment: Alignment.topLeft,
          heightFactor: 1,
          child: SizedBox(
            height: viewportHeight,
            // Its own layer: the scroll repaints only the text, not whatever
            // sits behind it (the Home hero's backdrop, the guide preview).
            child: RepaintBoundary(
              child: ValueListenableBuilder(
                valueListenable: _edges,
                builder: (context, edges, child) {
                  final (:atTop, :atEnd) = edges;
                  return ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        if (atTop) Colors.white else Colors.transparent,
                        Colors.white,
                        Colors.white,
                        if (atEnd) Colors.white else Colors.transparent,
                      ],
                      stops: [0, fade, 1 - fade, 1],
                    ).createShader(bounds),
                    child: child,
                  );
                },
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false, overscroll: false),
                  child: SingleChildScrollView(
                    controller: _controller,
                    physics: const NeverScrollableScrollPhysics(),
                    child: text,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
