import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:material_ui/material_ui.dart';

/// Where AppShell draws its player while it floats. AppShell is one page in
/// the root Navigator, and the VOD/Series detail pages are pushed above it,
/// so a floating player drawn by AppShell itself ends up beneath them.
/// [FloatingPlayerHost] sits above the whole Navigator instead.
///
/// AppShell hands over a builder rather than a widget: the host builds it in
/// the same frame AppShell stops building it, so the player (under a
/// GlobalKey) moves between the two without being remounted, which would
/// restart its stream.
class FloatingPlayerSlot extends ChangeNotifier {
  WidgetBuilder? _builder;
  int _hosts = 0;
  bool _disposed = false;

  /// Whether a [FloatingPlayerHost] is mounted to draw the player. Without
  /// one, AppShell keeps drawing it itself.
  bool get hasHost => _hosts > 0;

  WidgetBuilder? get builder => _builder;

  /// Has the host draw [builder], or nothing for null.
  void place(WidgetBuilder? builder) {
    if (builder == null && _builder == null) return;
    _builder = builder;
    notifyListeners();
  }

  /// Has the host rebuild what it draws, for changes AppShell made without
  /// moving the player.
  void refresh() {
    if (_builder != null) notifyListeners();
  }

  /// Drops the builder while the tree is locked (AppShell's dispose), where
  /// the host can't be marked for rebuild until the next frame.
  void clearDeferred() {
    if (_builder == null) return;
    _builder = null;
    // The whole app may be going (the slot's provider disposes it too).
    scheduleMicrotask(() {
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Wraps the app's Navigator (see `MaterialApp.router`'s builder in
/// main.dart) with a layer for the floating player above it.
class FloatingPlayerHost extends ConsumerStatefulWidget {
  const FloatingPlayerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<FloatingPlayerHost> createState() => _FloatingPlayerHostState();
}

class _FloatingPlayerHostState extends ConsumerState<FloatingPlayerHost> {
  late final FloatingPlayerSlot _slot = ref.read(floatingPlayerSlotProvider);

  @override
  void initState() {
    super.initState();
    _slot._hosts++;
  }

  @override
  void dispose() {
    _slot._hosts--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Its own Overlay: the player's tooltips need one, and the
        // Navigator's is beneath this layer.
        Overlay.wrap(
          child: ListenableBuilder(
            listenable: _slot,
            builder: (context, _) =>
                _slot.builder?.call(context) ?? const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}
