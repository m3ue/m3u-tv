import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';
import 'package:material_ui/material_ui.dart';

/// "Utah Mammoth at Toronto Maple Leafs" / "Arsenal vs Chelsea", in the
/// league's own order; the provider's event name for anything else.
String sportsFixtureTitle(AppLocalizations l10n, SportsFixture fixture) {
  final home = fixture.home?.team.displayName;
  final away = fixture.away?.team.displayName;
  if (home == null || away == null) return fixture.name ?? '';
  return fixture.league.soccerStyle
      ? l10n.sportsFixtureVs(home, away)
      : l10n.sportsFixtureAt(away, home);
}

/// A team crest, or a neutral shield when there is none.
class SportsTeamLogo extends StatelessWidget {
  const SportsTeamLogo({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.shield_outlined,
      size: size * 0.8,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final url = this.url;
    return SizedBox(
      width: size,
      height: size,
      child: url == null
          ? fallback
          : CachedMediaThumbnail(
              url: url,
              fallback: fallback,
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
    );
  }
}

/// One game in the Sports list: kickoff or live status, both teams with
/// their crests and scores, and how many channels carry it, over a wash of
/// the two teams' colours.
class SportsFixtureCard extends StatelessWidget {
  const SportsFixtureCard({
    super.key,
    required this.fixture,
    required this.channelCount,
    required this.isResolving,
    required this.showLeague,
    required this.inMultiview,
    required this.onTap,
    required this.onLongTap,
  });

  final SportsFixture fixture;

  /// Channels found for the game; null when it can't be watched (finished
  /// or postponed).
  final int? channelCount;
  final bool isResolving;

  /// Names the league under the time, for lists not already grouped by it.
  final bool showLeague;
  final bool inMultiview;
  final VoidCallback onTap;
  final VoidCallback onLongTap;

  static const double _radius = 12;

  /// The channel chips' slot: fixed, so their width doesn't move the rest.
  static const double _channelSlotWidth = 168;

  /// Below this card width, status and channels move above the teams.
  static const double _compactBelowWidth = 560;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final sides = fixture.displayOrder;
    final colors = [
      for (final side in sides) _washColor(side.team, theme.colorScheme),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * scale),
      child: DpadInkWell(
        onTap: onTap,
        onLongTap: onLongTap,
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(_radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius),
            gradient: colors.length == 2
                ? LinearGradient(colors: colors)
                : null,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 20 * scale,
            vertical: 12 * scale,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final status = _StatusColumn(
                fixture: fixture,
                showLeague: showLeague,
              );
              final teams = _Matchup(fixture: fixture, sides: sides);
              final channels = _ChannelIndicator(
                count: channelCount,
                isResolving: isResolving,
                inMultiview: inMultiview,
              );
              final chevron = Icon(
                Icons.chevron_right,
                size: 20 * scale,
                color: theme.colorScheme.onSurfaceVariant,
              );
              if (constraints.maxWidth < _compactBelowWidth * scale) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: status),
                        channels,
                        SizedBox(width: 4 * scale),
                        chevron,
                      ],
                    ),
                    SizedBox(height: 10 * scale),
                    teams,
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 104 * scale, child: status),
                  SizedBox(width: 16 * scale),
                  Expanded(child: teams),
                  SizedBox(width: 16 * scale),
                  SizedBox(
                    width: _channelSlotWidth * scale,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: channels,
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  chevron,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// The team's colour, dimmed into the card. Black and white (common
  /// "no colour" answers) fall back to the alternate, else to no tint.
  static Color _washColor(SportsTeam team, ColorScheme scheme) {
    for (final hex in [team.colorHex, team.alternateColorHex]) {
      final color = _parseHex(hex);
      if (color == null) continue;
      final luminance = color.computeLuminance();
      if (luminance < 0.02 || luminance > 0.85) continue;
      return color.withValues(alpha: 0.32);
    }
    return Colors.transparent;
  }

  static Color? _parseHex(String? hex) {
    if (hex == null) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({required this.fixture, required this.showLeague});

  final SportsFixture fixture;
  final bool showLeague;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final strong = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final headline = switch (fixture.state) {
      SportsFixtureState.live => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 6 * scale,
            vertical: 2 * scale,
          ),
          child: Text(
            l10n.sportsLiveBadge,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onError,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
      SportsFixtureState.finished => Text(l10n.sportsFinal, style: strong),
      SportsFixtureState.postponed => Text(
        l10n.sportsPostponed,
        style: strong,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      SportsFixtureState.scheduled => Text(
        DateFormat.jm(
          Localizations.localeOf(context).toLanguageTag(),
        ).format(fixture.start.toLocal()),
        style: strong,
      ),
    };
    final detail = fixture.state == SportsFixtureState.live
        ? fixture.statusDetail
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        headline,
        if (detail != null && detail.isNotEmpty) ...[
          SizedBox(height: 4 * scale),
          Text(
            detail,
            style: muted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (showLeague) ...[
          SizedBox(height: 4 * scale),
          Text(fixture.league.abbreviation, style: muted),
        ],
      ],
    );
  }
}

/// Both teams, one per row: crest, name, and the score in a fixed-width
/// column, so scores line up with each other and with other cards.
class _Matchup extends StatelessWidget {
  const _Matchup({required this.fixture, required this.sides});

  final SportsFixture fixture;
  final List<SportsCompetitor> sides;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final scored =
        fixture.state == SportsFixtureState.live ||
        fixture.state == SportsFixtureState.finished;
    final scores = [
      if (scored)
        for (final side in sides) num.tryParse(side.score ?? ''),
    ];
    final leader = switch (scores) {
      [final num a, final num b] when a != b => a > b ? 0 : 1,
      _ => null,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < sides.length; i++) ...[
          if (i > 0) SizedBox(height: 10 * scale),
          _TeamRow(
            fixture: fixture,
            competitor: sides[i],
            showScore: scored,
            // Finished games mark ESPN's winner; live ones the side ahead
            leads: fixture.state == SportsFixtureState.finished
                ? sides[i].winner
                : leader == i,
            trails: fixture.state == SportsFixtureState.finished
                ? !sides[i].winner
                : leader != null && leader != i,
          ),
        ],
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.fixture,
    required this.competitor,
    required this.showScore,
    required this.leads,
    required this.trails,
  });

  final SportsFixture fixture;
  final SportsCompetitor competitor;
  final bool showScore;
  final bool leads;
  final bool trails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);
    final color = trails ? theme.colorScheme.onSurfaceVariant : null;
    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: leads ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );
    final score = showScore ? competitor.score : null;
    final name = Text(
      competitor.team.displayName,
      style: nameStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      children: [
        SportsTeamLogo(url: competitor.team.logoUrl, size: 36 * scale),
        SizedBox(width: 14 * scale),
        if (score == null)
          Expanded(child: name)
        else
          // A hairline from the name to its score, so the eye follows the
          // row across the gap. The name takes its own width (a flexible
          // name's unused share wouldn't pass to the line, and the score
          // would drift), short of room for some line.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gap = 12 * scale;
                return Row(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(
                          0,
                          constraints.maxWidth - 2 * gap - 16 * scale,
                        ),
                      ),
                      child: name,
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.22,
                        ),
                      ),
                    ),
                    SizedBox(width: gap),
                  ],
                );
              },
            ),
          ),
        SizedBox(
          width: 36 * scale,
          child: score == null
              ? null
              : Text(
                  score,
                  textAlign: TextAlign.end,
                  style: nameStyle?.copyWith(
                    fontWeight: leads ? FontWeight.w800 : FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ChannelIndicator extends StatelessWidget {
  const _ChannelIndicator({
    required this.count,
    required this.isResolving,
    required this.inMultiview,
  });

  final int? count;
  final bool isResolving;
  final bool inMultiview;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    if (count == null || (count == 0 && isResolving)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    if (count == 0) {
      return MetadataChip(icon: Icons.tv_off, label: l10n.sportsNoChannel);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (inMultiview) ...[
          MetadataChip(icon: Icons.grid_view, label: l10n.multiviewTitle),
          SizedBox(height: 6 * scale),
        ],
        MetadataChip(
          icon: Icons.live_tv,
          label: l10n.sportsChannelCount(count),
        ),
      ],
    );
  }
}
