import 'dart:async';

import 'package:dpad/dpad.dart' show DpadFocusState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/hover_scroll_arrows.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

const double _kCardWidth = 150;
const double _kAvatarSize = 72;
const double _kAvatarGap = 8;
// Name + role text below the avatar (each maxLines: 1). This grows with the
// user's font-size setting (global TextScaler in main.dart) while the
// avatar above it does not, so only this budget is scaled - see CastStripState.build.
const double _kCardTextHeight = 72;
const double _kCardGap = 12;

/// A "locked focus" horizontal cast row for TV / desktop detail screens.
///
/// The whole strip is ONE plain [Focus] stop whose `onKeyEvent` handles every
/// arrow key itself and always consumes it - so nothing ever reaches a
/// directional traversal policy (the pattern Plezy uses, and the only one that
/// behaved on tvOS). Left/right move an internal index and scroll this row's
/// own controller; up/down are handed to [onNavigateUp] / [onNavigateDown]
/// (each always consumed, so focus never escapes the row). Cast is
/// informational - there is no per-card tap action.
///
/// Shared by the Series and VOD/movie detail screens. The compact (phone)
/// affordance stays the `CastMemberRow` picker chip + bottom sheet; this is the
/// wide layout only.
class CastStrip extends StatefulWidget {
  const CastStrip({
    super.key,
    required this.members,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onReveal,
    this.autofocus = false,
    this.maxMembers = 20,
    this.debugLabel = 'castStrip',
  });

  final List<CastMember> members;

  /// Up pressed while the row holds focus. Always consumed regardless.
  final VoidCallback? onNavigateUp;

  /// Down pressed while the row holds focus. Always consumed regardless.
  final VoidCallback? onNavigateDown;

  /// Called with this strip's [BuildContext] whenever it gains focus, so a
  /// host scroll region can bring it into view. Null when the row is always
  /// on-screen (e.g. pinned below the fold on VOD wide).
  final void Function(BuildContext context)? onReveal;

  final bool autofocus;
  final int maxMembers;
  final String debugLabel;

  @override
  State<CastStrip> createState() => CastStripState();
}

class CastStripState extends State<CastStrip> {
  final ScrollController _controller = ScrollController();
  late final FocusNode _focusNode = FocusNode(debugLabel: widget.debugLabel);
  int _focusedIndex = 0;
  bool _hasFocus = false;

  List<CastMember> get _members => widget.members.length > widget.maxMembers
      ? widget.members.sublist(0, widget.maxMembers)
      : widget.members;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(CastStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusedIndex >= _members.length) {
      _focusedIndex = _members.isEmpty ? 0 : _members.length - 1;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = _focusNode.hasFocus);
    if (_focusNode.hasFocus) {
      _centerFocused(animate: false);
      widget.onReveal?.call(context);
    }
  }

  /// Take focus, park the cursor, and ask the host to reveal the row. Public so
  /// a sibling row / screen can hop focus here.
  void focusRow() {
    _focusNode.requestFocus();
    _centerFocused(animate: false);
    widget.onReveal?.call(context);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (isDown) _moveFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (isDown) _moveFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (widget.onNavigateUp == null) return KeyEventResult.ignored;
      if (isDown) widget.onNavigateUp!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (widget.onNavigateDown == null) return KeyEventResult.ignored;
      if (isDown) widget.onNavigateDown!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  double get _itemExtent => _kCardWidth + _kCardGap;

  /// KNOWN ISSUE (shared with the episode strip - see `_centerFocused` in
  /// series_details_screen.dart): aggressive fast left/right key-repeat can
  /// still trip the `!_debugDoingSemantics` assertion storm when this
  /// `animateTo` settles during a semantics flush. Debug-only, self-recovers,
  /// but not yet bullet-proof - needs more device testing. A
  /// FrameSafeScrollController that deferred these jumps fixed the asserts but
  /// broke normal recenter, so it was reverted. In practice this row is far
  /// harder to race than the episode strip (fewer, wider cards), so it is left
  /// as-is pending a shared fix for both rows.
  void _centerFocused({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      final target =
          (_focusedIndex * _itemExtent +
                  _kCardWidth / 2 -
                  position.viewportDimension / 2)
              .clamp(0.0, position.maxScrollExtent);
      if ((target - position.pixels).abs() < 1) return;
      if (animate) {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          ),
        );
      } else {
        position.jumpTo(target);
      }
    });
  }

  void _moveFocus(int delta) {
    final target = (_focusedIndex + delta).clamp(0, _members.length - 1);
    if (target == _focusedIndex) return;
    setState(() => _focusedIndex = target);
    _centerFocused();
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    // No Scrollbar wrapper: under fast key-repeat its interplay with the
    // ListView's own ignore-pointer toggling throws a semantics assertion
    // storm on TV.
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      descendantsAreFocusable: false,
      onKeyEvent: _handleKeyEvent,
      child: SizedBox(
        height:
            _kAvatarSize +
            _kAvatarGap +
            _kCardTextHeight * FontSizeScope.scaleOf(context),
        // Desktop mouse users get hover arrows here (the scrollbar is hidden);
        // TV / phone pass straight through.
        child: HoverScrollArrows(
          controller: _controller,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: _itemExtent,
            itemCount: members.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: _kCardGap),
              child: _CastStripCard(
                member: members[index],
                focused: _hasFocus && index == _focusedIndex,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CastStripCard extends StatelessWidget {
  const _CastStripCard({required this.member, required this.focused});

  final CastMember member;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final character = member.character?.trim();
    final body = Padding(
      // Keep the focus border off the avatar / a long name.
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipOval(
            child: SizedBox(
              width: _kAvatarSize,
              height: _kAvatarSize,
              child: ResilientMediaImage(
                imageUrl: member.photo,
                fallbackIcon: Icons.person,
                width: _kAvatarSize,
                height: _kAvatarSize,
                borderRadius: 0,
              ),
            ),
          ),
          const SizedBox(height: _kAvatarGap),
          Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (character != null && character.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              character,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    return SizedBox(
      width: _kCardWidth,
      child: GradientBorderEffect(
        borderRadius: BorderRadius.circular(8),
      ).build(context, DpadFocusState(focused: focused, pressed: false), body),
    );
  }
}
