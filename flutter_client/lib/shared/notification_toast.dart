import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

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
    this.swipeToDismiss = false,
  });

  final Widget child;
  final void Function(TvNotificationItem item)? onNotificationTap;

  /// Enables swipe-down-to-dismiss on the toast cards. Only meaningful
  /// on touch (phone/tablet) form factors - TV/desktop stay D-pad/mouse
  /// driven and skip the drag recognizer entirely.
  final bool swipeToDismiss;

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

  /// Upserts a toast by [TvNotificationItem.id]: updates it in place (without
  /// resetting its entrance animation or focus) if already showing, otherwise
  /// enqueues it. For a [TvNotificationItem.sticky] item, repeated calls with
  /// the same id are how a caller drives a live-updating toast (e.g. sweep
  /// progress) without it re-animating in on every tick.
  void updateItem(TvNotificationItem item) {
    setState(() {
      final index = _queue.indexWhere((entry) => entry.item.id == item.id);
      if (index == -1) {
        _queue.add(_ToastEntry(item: item, key: UniqueKey()));
      } else {
        _queue[index] = _queue[index].copyWith(item: item);
      }
    });
  }

  /// Removes a toast by id immediately, if one with that id is showing. For a
  /// sticky progress toast, this is the caller's signal that the underlying
  /// work finished.
  void dismissById(String id) {
    setState(() => _queue.removeWhere((entry) => entry.item.id == id));
  }

  void _dismiss(_ToastEntry entry) {
    setState(() => _queue.remove(entry));
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.of(context).padding;
    final scale = FontSizeScope.scaleOf(context);
    // Snackbars use the same bottom slot, so the stack steps up above one
    // while it is showing.
    final snackBarLift = SnackBarTrackingMessenger.isShowingOf(context)
        ? 56 * scale
        : 0.0;
    return Stack(
      children: [
        widget.child,
        // Bottom-centre stack, newest at the bottom, in the same spot and
        // width as the app's floating snackbars.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          bottom: safePadding.bottom + 16 + snackBarLift,
          left: safePadding.left + 16,
          right: safePadding.right + 16,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        swipeToDismiss: widget.swipeToDismiss,
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// App-wide [ScaffoldMessenger] (installed in `MaterialApp.builder`) that
/// tracks whether a snackbar is showing or queued, so
/// [NotificationToastOverlay] can keep its bottom stack clear of it. Behaves
/// exactly like the default messenger otherwise.
class SnackBarTrackingMessenger extends ScaffoldMessenger {
  const SnackBarTrackingMessenger({super.key, required super.child});

  /// Whether a snackbar is on screen or queued. Rebuilds [context] when that
  /// changes; false when no tracking messenger is installed.
  static bool isShowingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_SnackBarShowingScope>()
          ?.showing ??
      false;

  @override
  ScaffoldMessengerState createState() => _SnackBarTrackingMessengerState();
}

class _SnackBarTrackingMessengerState extends ScaffoldMessengerState {
  int _open = 0;

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final controller = super.showSnackBar(
      snackBar,
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
    setState(() => _open++);
    unawaited(
      controller.closed.whenComplete(() {
        if (mounted) setState(() => _open--);
      }),
    );
    return controller;
  }

  @override
  Widget build(BuildContext context) =>
      _SnackBarShowingScope(showing: _open > 0, child: super.build(context));
}

class _SnackBarShowingScope extends InheritedWidget {
  const _SnackBarShowingScope({required this.showing, required super.child});

  final bool showing;

  @override
  bool updateShouldNotify(_SnackBarShowingScope oldWidget) =>
      showing != oldWidget.showing;
}

class _ToastEntry {
  _ToastEntry({required this.item, required this.key});

  final TvNotificationItem item;
  final Key key;

  _ToastEntry copyWith({required TvNotificationItem item}) =>
      _ToastEntry(item: item, key: key);
}

class _NotificationToast extends StatefulWidget {
  const _NotificationToast({
    super.key,
    required this.item,
    required this.onDismiss,
    this.onTap,
    this.swipeToDismiss = false,
  });

  final TvNotificationItem item;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;
  final bool swipeToDismiss;

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
    _slide =
        Tween<Offset>(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
        );

    _enterController.forward();

    if (!widget.item.sticky) {
      _progressController.addStatusListener(_onProgressStatus);
      _progressController.forward();
    }

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

  /// Only sticky toasts that report real progress draw a bar; the
  /// auto-dismiss countdown still runs (and pauses on focus/hover) unseen.
  Widget _buildProgressBar(Color textColor) {
    return LinearProgressIndicator(
      value: widget.item.progressValue,
      minHeight: 2,
      borderRadius: BorderRadius.circular(1),
      backgroundColor: textColor.withValues(alpha: 0.12),
      valueColor: AlwaysStoppedAnimation<Color>(
        textColor.withValues(alpha: 0.7),
      ),
    );
  }

  void _pause() {
    if (_paused || widget.item.sticky) return;
    _paused = true;
    _progressController.stop();
  }

  void _resume() {
    if (!_paused || widget.item.sticky) return;
    _paused = false;
    _progressController.forward();
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

  void _onDragUpdate(DismissUpdateDetails details) {
    if (details.progress > 0) {
      _pause();
    } else {
      _resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = FontSizeScope.scaleOf(context);
    final radius = BorderRadius.circular(12 * scale);
    // Neutral card like the rest of the app; only errors take a colour.
    final isDanger = widget.item.status == 'danger';
    final background = isDanger ? _dangerBackground : scheme.surfaceContainer;
    const textColor = Color(0xFFEDEDED);
    final hasBody = widget.item.body != null && widget.item.body!.isNotEmpty;

    Widget card = Focus(
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
            fit: StackFit.passthrough,
            children: [
              Material(
                color: background,
                elevation: 6,
                shadowColor: Colors.black,
                borderRadius: radius,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16 * scale,
                    vertical: 14 * scale,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.title,
                        style: const TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (hasBody) ...[
                        SizedBox(height: 2 * scale),
                        Text(
                          widget.item.body!,
                          style: TextStyle(
                            color: textColor.withValues(
                              alpha: isDanger ? 0.85 : 0.6,
                            ),
                            fontSize: 14,
                            height: 1.4,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                      if (widget.item.sticky) ...[
                        SizedBox(height: 10 * scale),
                        _buildProgressBar(textColor),
                      ],
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
                        borderRadius: radius,
                        width: 2,
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: [scheme.primary, scheme.secondary],
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
    );

    if (widget.swipeToDismiss) {
      card = Dismissible(
        key: ValueKey(widget.item.id),
        // Swipe down, like the floating snackbars that share this slot
        direction: DismissDirection.down,
        onUpdate: _onDragUpdate,
        onDismissed: (_) => widget.onDismiss(),
        child: card,
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: 8 * scale),
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _slide, child: card),
      ),
    );
  }

  static const _dangerBackground = Color(0xFFC62828);
}
