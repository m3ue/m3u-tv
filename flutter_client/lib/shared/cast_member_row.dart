import 'dart:async';
import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/list_picker_sheet.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Cast row used on the VOD movie detail and Series detail screens to
/// display the rich cast emitted by m3u-editor's `cast_list` payload.
/// Returns [SizedBox.shrink] when [members] is null or empty so callers
/// can drop it inline without a null check.
///
/// **Wide layout** (`compact = false`, the default): a horizontal scroll
/// row of 144×~140 cards. Each card is a 72×72 circular avatar with
/// name (bold, 1 line) and character (muted, 1 line) in a billing-block
/// layout - 144px fits ~21 characters so names like "Christoph Waltz"
/// and "Jesse Pinkman" don't truncate. When more members exist than
/// cards fit the available width (and [onShowAll] is set), the last
/// visible slot becomes a "+N / show all" tile that fires [onShowAll]
/// - callers wire it to the same picker modal the season picker uses.
/// Without [onShowAll] the row falls back to a plain horizontal scroll
/// capped at [_maxMembers] (15). D-pad traversal is native: left/right
/// moves focus between cards; the row stops at its edges so focus
/// doesn't escape into the surrounding column. Focused cards get the
/// canonical project-wide [GradientBorderEffect] glow. Member cards fire
/// [onTapMember] when set, opening that actor's filmography; otherwise
/// cast stays informational on wide layouts.
///
/// **Compact mode** (`compact = true`, phone breakpoint): a pill-shaped
/// picker button mirroring the season picker's chrome - the localized
/// "Cast" label, a down-chevron, and a count badge showing how many cast
/// members are in [members]. Tapping the button fires [onShowAll],
/// which callers wire to the same bottom-drawer picker used by the
/// season picker. The picker button is hidden when [onShowAll] is null,
/// allowing narrow callers (e.g. a search results card) to opt out of
/// the cast UI entirely.
class CastMemberRow extends StatelessWidget {
  const CastMemberRow({
    super.key,
    required this.members,
    this.semanticLabel,
    this.compact = false,
    this.onShowAll,
    this.allCastSemanticLabel,
    this.onTapMember,
  });

  final List<CastMember>? members;

  /// Accessibility label for the row in wide layout, and the visible
  /// button label in compact layout. Localized at the call site (the
  /// VOD/Series detail screens pass `AppLocalizations.of(context)
  /// .vodCast` / `.seriesCast`). The row itself stays
  /// locale-agnostic.
  final String? semanticLabel;

  /// Phone-breakpoint layout. Renders a single picker button instead of
  /// the wide horizontal scroll row. See class doc.
  final bool compact;

  /// Tap handler for the compact picker chip and the wide layout's
  /// "+N / show all" overflow tile. Typically opens the full cast in
  /// the same modal shape the season picker uses (bottom sheet on the
  /// narrow breakpoint, centered dialog on the wide one). When null,
  /// the compact widget renders nothing and the wide row falls back to
  /// a plain scroll without an overflow tile.
  final VoidCallback? onShowAll;

  /// Accessibility / visible label for the sheet when the picker is
  /// tapped (e.g. "Show all cast"). Localized at the call site.
  final String? allCastSemanticLabel;

  /// Opens a cast member's filmography screen. Null leaves cast
  /// non-interactive (wide-layout cards render without a tap affordance,
  /// and rows in the "show all" sheet stay non-tappable).
  final ValueChanged<CastMember>? onTapMember;

  static const double _cardWidth = 144;
  static const double _avatarSize = 72;
  static const double _cardHeight = 144;
  static const double _cardGap = 12;
  static const int _maxMembers = 15;

  /// Padding between a card's focus border and its content, so the
  /// [GradientBorderEffect] glow never hugs the avatar or a long name.
  static const EdgeInsets _cardInset = EdgeInsets.symmetric(
    vertical: 4,
    horizontal: 3,
  );

  @override
  Widget build(BuildContext context) {
    final visible = members;
    if (visible == null || visible.isEmpty) {
      return const SizedBox.shrink();
    }

    if (compact) {
      // Compact callers without a sheet set onShowAll=null → render
      // nothing. Avoids a tap target that would no-op.
      if (onShowAll == null) return const SizedBox.shrink();
      return _CastPickerButton(
        label: semanticLabel ?? 'Cast',
        badgeCount: visible.length,
        onTap: onShowAll!,
      );
    }

    return Semantics(
      label: semanticLabel,
      container: true,
      child: DpadRegion(
        memoryKey: 'cast-member-row',
        horizontalEdge: DpadEdgeBehavior.stop,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capped = visible.length > _maxMembers
                ? visible.sublist(0, _maxMembers)
                : visible;
            // Card slots that fit the available width without scrolling
            // (n × 144 + (n−1) × 12 ≤ maxWidth). Unbounded width (e.g.
            // an ancestor horizontal scroller) fits everything.
            final maxWidth = constraints.maxWidth;
            final fit = maxWidth.isFinite
                ? math.max(
                    1,
                    (maxWidth + _cardGap) ~/ (_cardWidth + _cardGap),
                  )
                : capped.length;
            // With onShowAll wired, members beyond what fits collapse
            // into a trailing "+N / show all" tile instead of scrolling
            // off-screen. Without it, keep the plain capped scroll row.
            final overflows = onShowAll != null && visible.length > fit;
            final shown = overflows
                ? capped.sublist(0, math.min(fit - 1, capped.length))
                : capped;
            final hiddenCount = visible.length - shown.length;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              child: Row(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(width: _cardGap),
                    SizedBox(
                      width: _cardWidth,
                      height: _cardHeight,
                      child: _CastMemberCard(
                        member: shown[i],
                        onTap: onTapMember == null
                            ? null
                            : () => onTapMember!(shown[i]),
                      ),
                    ),
                  ],
                  if (overflows) ...[
                    if (shown.isNotEmpty) const SizedBox(width: _cardGap),
                    SizedBox(
                      width: _cardWidth,
                      height: _cardHeight,
                      child: _ShowAllCastCard(
                        hiddenCount: hiddenCount,
                        label:
                            allCastSemanticLabel ??
                            AppLocalizations.of(context).castShowAll,
                        onTap: onShowAll!,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pill-shaped picker button matching the season picker's chrome:
/// `label` text, a count badge, a down-chevron, focused via
/// [GradientBorderEffect]. Tap fires [onTap]. Renders nothing different
/// when [badgeCount] is 0 or 1 - the season picker shows the badge for
/// any positive count.
class _CastPickerButton extends StatelessWidget {
  const _CastPickerButton({
    required this.label,
    required this.badgeCount,
    required this.onTap,
  });

  final String label;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppButton(
      label: label,
      icon: Icons.arrow_drop_down,
      badgeCount: badgeCount > 0 ? badgeCount : null,
      // Muted, not the default error red - this is a count, not an
      // unwatched / new alert (matches how the season picker styles its
      // episode-count badge).
      badgeColor: scheme.surfaceContainerHighest,
      badgeTextColor: scheme.onSurfaceVariant,
      onPressed: onTap,
    );
  }
}

/// Trailing wide-layout tile shown when more members exist than fit
/// the row: a "+N" circle where the avatar sits and the localized
/// "Show all" label in the name slot. Tap opens the full cast in the
/// caller's picker modal.
class _ShowAllCastCard extends StatelessWidget {
  const _ShowAllCastCard({
    required this.hiddenCount,
    required this.label,
    required this.onTap,
  });

  final int hiddenCount;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: label,
      button: true,
      child: DpadInkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        effects: const [
          GradientBorderEffect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ],
        // Inset the content so the focus border has breathing room on every
        // side, not just the text baseline.
        child: Padding(
          padding: CastMemberRow._cardInset,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: CastMemberRow._avatarSize,
                height: CastMemberRow._avatarSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: Text(
                      '+$hiddenCount',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CastMemberCard extends StatelessWidget {
  const _CastMemberCard({required this.member, this.onTap});

  final CastMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = member.name;
    final character = member.character;

    return Semantics(
      label: character != null && character.isNotEmpty
          ? '$name as $character'
          : name,
      child: DpadInkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        effects: const [
          GradientBorderEffect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ],
        // Inset the content so the focus border has breathing room on every
        // side, not just the text baseline.
        child: Padding(
          padding: CastMemberRow._cardInset,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Circular headshot. No decorative ring or fade - a gradient
              // ring and a bottom-to-top surface fade were both tried here
              // and left visible dark artifacts on avatars in dark theme.
              // Focus is the card-level [GradientBorderEffect] only.
              SizedBox(
                width: CastMemberRow._avatarSize,
                height: CastMemberRow._avatarSize,
                child: ClipOval(
                  child: ResilientMediaImage(
                    imageUrl: member.photo,
                    fallbackIcon: Icons.person,
                    backgroundColor: scheme.surface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              if (character != null && character.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  character,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the "Show all cast" picker listing every [cast] member (avatar +
/// name + character). A drag-handle bottom sheet on the narrow
/// breakpoint, a centered dialog when [asDialog] is true - the same modal
/// split the season picker uses so D-pad / dismiss behavior matches.
/// Shared by the VOD and Series detail screens.
void showAllCast(
  BuildContext context,
  List<CastMember> cast, {
  bool asDialog = false,
  ValueChanged<CastMember>? onTapMember,
}) {
  final l = AppLocalizations.of(context);
  unawaited(
    ListPickerSheet.show(
      context,
      title: l.castShowAll,
      cancelLabel: l.cancel,
      asDialog: asDialog,
      children: [
        for (final member in cast)
          CastSheetRow(member: member, onTapMember: onTapMember),
      ],
    ),
  );
}

/// Single row inside the "Show all cast" picker: a 48px circular avatar,
/// a bold name and a muted character line, both ellipsized to one line.
/// Tappable (via [DpadInkWell], matching the season picker's `_seasonTile`
/// pattern) only when [onTapMember] is set - it pops the sheet after firing
/// the callback, the same way `_seasonTile` pops with its selection.
class CastSheetRow extends StatelessWidget {
  const CastSheetRow({super.key, required this.member, this.onTapMember});

  final CastMember member;
  final ValueChanged<CastMember>? onTapMember;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final character = member.character;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: ClipOval(
              child: ResilientMediaImage(
                imageUrl: member.photo,
                fallbackIcon: Icons.person,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  member.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (character != null && character.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    character,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTapMember == null) return content;

    return DpadInkWell(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      onTap: () {
        onTapMember!(member);
        Navigator.of(context).pop();
      },
      child: content,
    );
  }
}
