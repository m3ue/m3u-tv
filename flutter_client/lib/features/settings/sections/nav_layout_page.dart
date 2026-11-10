import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/app/navigation_sidebar.dart';
import 'package:m3u_tv/features/settings/settings_ui.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// Settings > Appearance page for ordering the main destinations and choosing
/// where each one shows. One order drives both the nav and the Home rows.
///
/// Touch and mouse drag a row by its handle. A remote can't drag, so OK picks a
/// row up, Up/Down move it and OK drops it (the same idea as Multiview's tile
/// reorder mode); the order is only saved on drop.
///
/// An M3U TV Home screen from the server adds its rows under their section,
/// each with its own Home switch, and locks the whole page when enforced.
class NavLayoutPage extends ConsumerStatefulWidget {
  const NavLayoutPage({
    super.key,
    required this.service,
    required this.usesRemote,
  });

  final ViewSettingsService service;

  /// Whether to explain the remote's pick-up flow instead of dragging.
  final bool usesRemote;

  @override
  ConsumerState<NavLayoutPage> createState() => _NavLayoutPageState();
}

class _NavLayoutPageState extends ConsumerState<NavLayoutPage> {
  static const double _switchColumnWidth = 72;

  /// Keeps each row's focus borders inside the group's rounded clip. Taken out
  /// of the row's own padding, so the row stays the same size.
  static const double _rowInset = 4;

  late NavLayout _layout = widget.service.navLayoutSync;
  List<String> _available = const [];

  String? _grabbedRoute;
  NavLayout? _layoutBeforeGrab;

  /// Makes Back cancel the grab rather than leave the page. A local history
  /// entry is what every Back path already honors: `GoRouter.pop` and
  /// `Navigator.pop`, which ignore `PopScope`, both remove the entry instead
  /// of popping the route.
  LocalHistoryEntry? _grabEntry;

  final Map<String, FocusNode> _rowNodes = {};

  bool get _locked => widget.service.isNavLayoutEnforced;

  @override
  void initState() {
    super.initState();
    widget.service.addListener(_onServiceChanged);
  }

  /// The server's layout can arrive or change while the page is open.
  void _onServiceChanged() {
    if (!mounted || _grabbedRoute != null) return;
    setState(() => _layout = widget.service.navLayoutSync);
  }

  FocusNode _nodeFor(String route) => _rowNodes.putIfAbsent(
    route,
    () => FocusNode(debugLabel: 'nav-layout-$route'),
  );

  @override
  void dispose() {
    widget.service.removeListener(_onServiceChanged);
    _grabbedRoute = null;
    for (final node in _rowNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _save(NavLayout layout) {
    setState(() => _layout = layout);
    unawaited(widget.service.setNavLayout(layout));
  }

  void _grab(String route) {
    final entry = LocalHistoryEntry(onRemove: _cancelGrab);
    ModalRoute.of(context)?.addLocalHistoryEntry(entry);
    setState(() {
      _grabEntry = entry;
      _grabbedRoute = route;
      _layoutBeforeGrab = _layout;
    });
  }

  void _drop() {
    final before = _layoutBeforeGrab;
    _grabbedRoute = null;
    _grabEntry?.remove();
    _grabEntry = null;
    if (before == _layout) {
      setState(() {});
    } else {
      _save(_layout);
    }
  }

  void _cancelGrab() {
    final route = _grabbedRoute;
    final before = _layoutBeforeGrab;
    if (route == null || before == null || !mounted) return;
    setState(() {
      _grabbedRoute = null;
      _grabEntry = null;
      _layout = before;
    });
    _keepRowFocused(route);
  }

  bool _onDirection(String route, TraversalDirection direction) {
    if (_grabbedRoute != route) return false;
    final delta = switch (direction) {
      TraversalDirection.up => -1,
      TraversalDirection.down => 1,
      _ => 0,
    };
    if (delta != 0) {
      setState(() => _layout = _layout.moved(route, delta, _available));
      _keepRowFocused(route);
    }
    return true;
  }

  /// The list rebuilds a moved row in its new slot, which can drop focus.
  void _keepRowFocused(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _nodeFor(route)..requestFocus();
      final rowContext = node.context;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  void _onDragReorder(List<String> rows, int oldIndex, int newIndex) {
    if (_locked) return;
    _save(_layout.moved(rows[oldIndex], newIndex - oldIndex, _available));
  }

  Future<void> _confirmReset(AppLocalizations l) async {
    final confirmed = await showSettingsConfirmDialog(
      context,
      title: l.settingsNavLayoutReset,
      message: l.settingsNavLayoutResetMessage,
      confirmLabel: l.settingsNavLayoutResetConfirm,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    // Back to the server's layout when there is one, else the app's.
    await widget.service.resetNavLayout();
    if (mounted) setState(() => _layout = widget.service.navLayoutSync);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    _available = ref.watch(availableMainRoutesProvider);
    final rows = _layout.order
        .where(_available.contains)
        .toList(growable: false);
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final columnStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final locked = _locked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (locked)
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: 18 * scale,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                child: Text(l.settingsManagedByServer, style: hintStyle),
              ),
            ],
          )
        else
          Text(
            widget.usesRemote
                ? l.settingsNavLayoutHintRemote
                : l.settingsNavLayoutHintTouch,
            style: hintStyle,
          ),
        SizedBox(height: 4 * scale),
        Text(l.settingsNavLayoutPinned, style: hintStyle),
        SizedBox(height: 16 * scale),
        Padding(
          padding: EdgeInsets.only(right: _rowInset * scale),
          child: Row(
            children: [
              const Spacer(),
              for (final label in [l.settingsNavLayoutColumnNav, l.navHome])
                SizedBox(
                  width: _switchColumnWidth * scale,
                  child: Text(
                    label,
                    style: columnStyle,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 8 * scale),
        Flexible(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kSettingsGroupRadius),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: rows.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _onDragReorder(rows, oldIndex, newIndex),
              itemBuilder: (context, index) =>
                  _buildRow(context, rows[index], index),
            ),
          ),
        ),
        if (!locked) ...[
          SizedBox(height: 16 * scale),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: l.settingsNavLayoutReset,
              onPressed: () => unawaited(_confirmReset(l)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(BuildContext context, String route, int index) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final isGrabbed = route == _grabbedRoute;
    final locked = _locked;
    final serverRows = widget.service.customHomeRowsFor(route);
    final hiddenRows = locked
        ? const <String>{}
        : widget.service.hiddenHomeRowIds;
    final handle = Icon(
      isGrabbed ? Icons.swap_vert : Icons.drag_handle,
      size: 24 * scale,
      color: isGrabbed
          ? theme.colorScheme.primary
          : theme.colorScheme.onSurfaceVariant,
    );
    return Material(
      key: ValueKey(route),
      color: isGrabbed
          ? Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.16),
              theme.colorScheme.surfaceContainerHigh,
            )
          : theme.colorScheme.surfaceContainerHigh,
      shape: Border(
        bottom: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(_rowInset * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Stretches the switch cells to the row's height, so their focus
            // borders match the row's at any font scale.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DpadFocusable(
                      focusNode: _nodeFor(route),
                      autofocus: index == 0,
                      // Keys only: a tap would pick the row up with no way to move it.
                      tapToSelect: false,
                      onSelect: () {
                        if (locked) return;
                        isGrabbed ? _drop() : _grab(route);
                      },
                      onDirection: (direction) =>
                          _onDirection(route, direction),
                      effects: [
                        GradientBorderEffect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                          width: isGrabbed ? 4 : 2.5,
                        ),
                      ],
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8 * scale,
                          vertical: 10 * scale,
                        ),
                        child: Row(
                          children: [
                            if (locked)
                              Icon(
                                Icons.lock_outline,
                                size: 24 * scale,
                                color: theme.colorScheme.onSurfaceVariant,
                              )
                            else
                              ReorderableDragStartListener(
                                index: index,
                                child: handle,
                              ),
                            SizedBox(width: 12 * scale),
                            Icon(
                              navigationRouteIcon(route),
                              size: 22 * scale,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            SizedBox(width: 12 * scale),
                            Expanded(
                              child: Text(
                                navigationRouteLabel(context, route),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _switchCell(
                    scale,
                    value: _layout.showsInNav(route),
                    onChanged: locked
                        ? null
                        : (shown) =>
                              _save(_layout.withNav(route, shown: shown)),
                  ),
                  _switchCell(
                    scale,
                    value: _layout.showsHomeRow(route),
                    onChanged: locked
                        ? null
                        : (shown) =>
                              _save(_layout.withHomeRow(route, shown: shown)),
                  ),
                ],
              ),
            ),
            for (final row in serverRows)
              _serverRowLine(
                context,
                scale,
                row.title ?? '',
                shown: !hiddenRows.contains(row.id),
                onChanged: locked
                    ? null
                    : (shown) => unawaited(
                        widget.service.setHomeRowShown(row.id, shown: shown),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// A row the server added to a section: only its Home switch, under the
  /// section it moves with.
  Widget _serverRowLine(
    BuildContext context,
    double scale,
    String title, {
    required bool shown,
    required ValueChanged<bool>? onChanged,
  }) {
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                (8 + 24 + 12 + 22 + 12) * scale,
                8 * scale,
                8 * scale,
                8 * scale,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          SizedBox(width: _switchColumnWidth * scale),
          _switchCell(scale, value: shown, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _switchCell(
    double scale, {
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    if (onChanged == null) {
      return SizedBox(
        width: _switchColumnWidth * scale,
        child: Center(
          child: AppSwitch(value: value, onChanged: null),
        ),
      );
    }
    return DpadInkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _switchColumnWidth * scale,
        child: Center(
          child: AppSwitch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
