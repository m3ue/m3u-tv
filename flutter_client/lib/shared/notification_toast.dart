import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// In-app overlay toast for push notifications. Works on all platforms
/// including Android TV and tvOS, where OS-level notification APIs are
/// unavailable.
///
/// Hold a [GlobalKey<NotificationToastOverlayState>] and call
/// [NotificationToastOverlayState.enqueue] to show a toast.
///
/// Pass [onNotificationTap] to handle taps — the callback receives the full
/// [TvNotificationItem] so future payload fields (deep links, episode IDs,
/// thumbnails) can drive navigation.
class NotificationToastOverlay extends StatefulWidget {
  const NotificationToastOverlay({
    super.key,
    required this.child,
    this.onNotificationTap,
  });

  final Widget child;
  final void Function(TvNotificationItem item)? onNotificationTap;

  @override
  State<NotificationToastOverlay> createState() =>
      NotificationToastOverlayState();
}

class NotificationToastOverlayState extends State<NotificationToastOverlay> {
  final List<_ToastEntry> _queue = [];

  void enqueue(TvNotificationItem item) {
    setState(() {
      _queue.add(_ToastEntry(item: item, key: UniqueKey()));
    });
  }

  void _dismiss(_ToastEntry entry) {
    setState(() => _queue.remove(entry));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 24,
          right: 24,
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: _queue
                .map(
                  (entry) => _NotificationToast(
                    key: entry.key,
                    item: entry.item,
                    onDismiss: () => _dismiss(entry),
                    onTap: widget.onNotificationTap != null
                        ? () => widget.onNotificationTap!(entry.item)
                        : null,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _ToastEntry {
  _ToastEntry({required this.item, required this.key});

  final TvNotificationItem item;
  final Key key;
}

class _NotificationToast extends StatefulWidget {
  const _NotificationToast({
    super.key,
    required this.item,
    required this.onDismiss,
    this.onTap,
  });

  final TvNotificationItem item;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  State<_NotificationToast> createState() => _NotificationToastState();
}

class _NotificationToastState extends State<_NotificationToast>
    with TickerProviderStateMixin {
  late final AnimationController _enterController;
  late final AnimationController _progressController;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  final FocusNode _focusNode = FocusNode();
  bool _focused = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();

    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    _opacity = CurvedAnimation(parent: _enterController, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.4, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterController, curve: Curves.easeOut));

    unawaited(_enterController.forward());

    _progressController.addStatusListener(_onProgressStatus);
    unawaited(_progressController.forward());

    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _progressController.removeStatusListener(_onProgressStatus);
    _enterController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  void _onProgressStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_paused && mounted) {
      unawaited(_dismissAnimated());
    }
  }

  void _onFocusChange() {
    final hasFocus = _focusNode.hasFocus;
    setState(() => _focused = hasFocus);
    if (hasFocus) {
      _pause();
    } else {
      _resume();
    }
  }

  void _pause() {
    if (_paused) return;
    _paused = true;
    _progressController.stop();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    unawaited(_progressController.forward());
  }

  Future<void> _dismissAnimated() async {
    if (!mounted) return;
    _progressController.stop();
    await _enterController.reverse();
    widget.onDismiss();
  }

  void _handleTap() {
    widget.onTap?.call();
    unawaited(_dismissAnimated());
  }

  @override
  Widget build(BuildContext context) {
    final (accentColor, icon) = _statusAccent(widget.item.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _slide,
          child: Focus(
            focusNode: _focusNode,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.select ||
                      event.logicalKey == LogicalKeyboardKey.enter)) {
                _handleTap();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: MouseRegion(
              onEnter: (_) => _pause(),
              onExit: (_) => _resume(),
              child: GestureDetector(
                onTap: _handleTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xEE1C1C1E),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x60000000),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(width: 4, color: accentColor),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  14,
                                  14,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          icon,
                                          color: accentColor,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.item.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.3,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                              if (widget.item.body != null &&
                                                  widget
                                                      .item
                                                      .body!
                                                      .isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  widget.item.body!,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.7),
                                                    fontSize: 15,
                                                    height: 1.4,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedBuilder(
                                      animation: _progressController,
                                      builder: (_, _) =>
                                          LinearProgressIndicator(
                                            value:
                                                1.0 - _progressController.value,
                                            minHeight: 3,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                            backgroundColor: Colors.white
                                                .withValues(alpha: 0.1),
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  accentColor.withValues(
                                                    alpha: 0.75,
                                                  ),
                                                ),
                                          ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // D-pad focus ring
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _focused ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: CustomPaint(
                            painter: GradientBorderPainter(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(14),
                              ),
                              width: 2,
                              gradient: LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: [
                                  accentColor,
                                  accentColor.withValues(alpha: 0.4),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static (Color, IconData) _statusAccent(String status) => switch (status) {
    'success' => (
      const Color(0xFF4CAF50),
      Icons.check_circle_outline,
    ),
    'warning' => (
      const Color(0xFFFFA726),
      Icons.warning_amber_outlined,
    ),
    'danger' => (const Color(0xFFF44336), Icons.error_outline),
    _ => (const Color(0xFF42A5F5), Icons.info_outline),
  };
}
