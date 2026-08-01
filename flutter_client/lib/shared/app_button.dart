import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';

/// Stadium-radius focus border shared by every pill/circular button in the
/// app. A large radius makes the dpad focus border match the pill shape
/// regardless of widget height.
const kStadiumFocusEffects = [
  GradientBorderEffect(borderRadius: BorderRadius.all(Radius.circular(50))),
];

/// `materialTapTargetSize: MaterialTapTargetSize.shrinkWrap` (set app-wide in
/// `main.dart` for TV layouts) removes Material 3's default 48dp minimum tap
/// target, so a bare `FilledButton` renders far smaller than intended. These
/// are the single place that size is restored — retune here to change every
/// button in the app at once.
const _kMinSize = Size(64, 48);
const _kPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

enum AppButtonVariant { primary, tonal, destructive }

const _kBlack = Color(0xFF09090b);

/// Paints the `primary` variant's black-to-dark-gray gradient in place of a
/// flat fill, via the `backgroundBuilder` hook `ButtonStyle` gained for
/// exactly this (see the Flutter buttons migration guide) — the button's own
/// `backgroundColor` is left transparent so this shows through, while the
/// ink/ripple and disabled dimming above it are unaffected. Also raises
/// [ButtonStyle.elevation] since `primary` renders as an [ElevatedButton] —
/// the drop shadow gives it more visual weight than the flat `tonal`/
/// `destructive` variants.
ButtonStyle _primaryGradientStyle(ButtonStyle base) {
  return base.copyWith(
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    // Focus/hover is already shown via the gradient DpadFocusable border —
    // Material's own hover/press state layer on top of the background just
    // fights with it (background looks like it's flickering between
    // transparency levels as hover/focus/press states change).
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(6),
    shadowColor: const WidgetStatePropertyAll(Colors.black87),
    backgroundBuilder: (context, states, child) {
      final dimmed = states.contains(WidgetState.disabled);
      return DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _kBlack,
              if (dimmed) _kBlack.withValues(alpha: 0.5) else _kBlack,
            ],
          ),
        ),
        child: child,
      );
    },
  );
}

/// The "ghost button" look — a barely-there fill with a subtle outline,
/// instead of Material 3's default solid container fill (which renders as
/// flat gray/red against this app's dark theme). [tint] lets `destructive`
/// reuse the same look while still reading as red. Still a
/// [FilledButton]/[IconButton], just restyled — not an [OutlinedButton].
ButtonStyle _ghostStyle(ButtonStyle base, {Color tint = Colors.white}) {
  return base.copyWith(
    backgroundColor: WidgetStatePropertyAll(tint.withValues(alpha: 0.08)),
    foregroundColor: WidgetStatePropertyAll(tint),
    // See the matching comment in _primaryGradientStyle — the gradient
    // DpadFocusable border is the one focus/hover indicator; a background
    // state layer on top of it just reads as flicker.
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    side: WidgetStatePropertyAll(
      BorderSide(color: tint.withValues(alpha: 0.4)),
    ),
  );
}

/// Wraps [DpadFocusable] so hovering with a mouse also moves real D-pad
/// focus, not just the button's own highlight — otherwise a mouse hovering
/// a sibling button never lit up its gradient border, and an autofocused
/// button kept its border until the next arrow-key press.
class _HoverFocusable extends StatefulWidget {
  const _HoverFocusable({
    required this.child,
    required this.onSelect,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onSelect;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_HoverFocusable> createState() => _HoverFocusableState();
}

class _HoverFocusableState extends State<_HoverFocusable> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void dispose() {
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _focusNode.requestFocus(),
      child: DpadFocusable(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onSelect: widget.onSelect,
        effects: kStadiumFocusEffects,
        child: widget.child,
      ),
    );
  }
}

/// The one button look used everywhere: primary/tonal/destructive text (with
/// an optional leading icon), wrapped in [DpadFocusable] with a stadium
/// focus ring. `primary` renders as an [ElevatedButton] for extra visual
/// weight; `tonal`/`destructive` render as [FilledButton]/[FilledButton.tonal].
/// Material buttons wrap in plain [DpadFocusable] (not [DpadInkWell]) since
/// they already provide their own ink/ripple.
///
/// Change the styling here — sizing, shape, colors — and it's reflected
/// everywhere a button is used, the same way [DpadInkWell] centralizes the
/// tappable-card look.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.tonal,
    this.autofocus = false,
    this.focusNode,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Shows a spinner in place of the label/icon and disables the button —
  /// for in-flight async actions (e.g. connecting, creating).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = FilledButton.styleFrom(
      minimumSize: _kMinSize,
      padding: _kPadding,
    );
    final style = switch (variant) {
      AppButtonVariant.destructive => _ghostStyle(
        baseStyle,
        tint: colorScheme.error,
      ),
      AppButtonVariant.primary => _primaryGradientStyle(baseStyle),
      AppButtonVariant.tonal => _ghostStyle(baseStyle),
    };

    final effectiveOnPressed = loading ? null : onPressed;

    Widget button;
    if (loading) {
      final child = SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: variant == AppButtonVariant.destructive
              ? colorScheme.error
              : null,
        ),
      );
      button = variant == AppButtonVariant.primary
          ? ElevatedButton(style: style, onPressed: null, child: child)
          : FilledButton.tonal(style: style, onPressed: null, child: child);
    } else if (icon == null) {
      button = variant == AppButtonVariant.primary
          ? ElevatedButton(
              style: style,
              onPressed: effectiveOnPressed,
              child: Text(label),
            )
          : FilledButton.tonal(
              style: style,
              onPressed: effectiveOnPressed,
              child: Text(label),
            );
    } else {
      button = variant == AppButtonVariant.primary
          ? ElevatedButton.icon(
              style: style,
              onPressed: effectiveOnPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : FilledButton.tonalIcon(
              style: style,
              onPressed: effectiveOnPressed,
              icon: Icon(icon),
              label: Text(label),
            );
    }

    return _HoverFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: effectiveOnPressed,
      child: button,
    );
  }
}

/// Icon-only counterpart to [AppButton] — same stadium focus ring and
/// minimum footprint, for compact controls like player transport buttons
/// and destructive icon actions.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.variant = AppButtonVariant.tonal,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final AppButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseStyle = IconButton.styleFrom(minimumSize: _kMinSize);
    final style = switch (variant) {
      AppButtonVariant.destructive => _ghostStyle(
        baseStyle,
        tint: colorScheme.error,
      ),
      AppButtonVariant.primary => _primaryGradientStyle(baseStyle),
      AppButtonVariant.tonal => _ghostStyle(baseStyle),
    };

    Widget rawButton;
    if (variant == AppButtonVariant.primary) {
      // No IconButton variant renders elevated — use a plain ElevatedButton
      // with an icon child instead, matching AppButton's primary treatment.
      final elevatedButton = ElevatedButton(
        style: style,
        onPressed: onPressed,
        child: Icon(icon),
      );
      final tooltipMessage = tooltip;
      rawButton = tooltipMessage == null
          ? elevatedButton
          : Tooltip(message: tooltipMessage, child: elevatedButton);
    } else {
      rawButton = IconButton.filledTonal(
        tooltip: tooltip,
        style: style,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    // IconButton's own `tooltip` only surfaces via a Tooltip, whose semantics
    // node isn't reliably queryable in widget tests without enabling the
    // full semantics tree — wrap explicitly so `find.bySemanticsLabel` works
    // the same as it did for the hand-rolled buttons this replaces.
    final button = tooltip == null
        ? rawButton
        : Semantics(label: tooltip, button: true, child: rawButton);

    return _HoverFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onSelect: onPressed,
      child: button,
    );
  }
}
