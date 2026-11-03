import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_matcher.dart';
import 'package:m3u_tv/services/sports_models.dart';

/// How a channel was tied to a fixture, strongest first.
enum SportsMatchKind {
  /// A guide programme names both teams in its title, or both in its
  /// subtitle: the fixture line itself ("Utah Mammoth at Toronto Maple
  /// Leafs").
  guideHeadline,

  /// The channel's own name names both teams: a provider's per-event
  /// channel ("NHL 05: Mammoth @ Maple Leafs 7PM").
  channelName,

  /// A guide programme names one team in its title and the other in its
  /// subtitle.
  guideSplit,

  /// Both teams appear only in a programme's description, e.g. a
  /// whip-around show listing the games it carries.
  guideDescription,
}

/// A channel that can carry a fixture.
class SportsChannelMatch {
  const SportsChannelMatch({
    required this.channel,
    required this.kind,
    this.program,
  });

  final Channel channel;
  final SportsMatchKind kind;

  /// The guide programme the match came from; null for a channel-name match.
  final EpgProgram? program;
}

/// Finds the channels in the active playlist that carry each fixture, from
/// the locally stored guide and the channel names.
///
/// Everything is narrowed in SQLite first: guide rows and channel names are
/// prefiltered by the teams' [SportsMatcher.needlesFor] substrings, so only
/// a handful of rows reach the whole-phrase checks here, however large the
/// playlist. The guide is only as far ahead as the app has fetched it (the
/// background sweep keeps the next several programmes per channel), so a
/// game days away usually resolves by channel name only, if at all.
class SportsChannelResolver {
  SportsChannelResolver(this._repo);

  final CatalogRepository _repo;

  /// A programme carries the game when it is on air between shortly after
  /// kickoff (so the pre-game show that ends at kickoff doesn't count) and
  /// the first stretch of play.
  static const Duration _windowStartOffset = Duration(minutes: 10);
  static const Duration _windowEndOffset = Duration(minutes: 45);

  /// Matches per fixture are capped: past this many, the list is noise.
  static const int _maxPerFixture = 30;

  /// Matches for each of [fixtures] that can still be watched, keyed by
  /// fixture id, strongest first. Finished, postponed and team-less
  /// fixtures are skipped.
  Future<Map<String, List<SportsChannelMatch>>> resolve(
    List<SportsFixture> fixtures,
  ) async {
    final targets = [
      for (final fixture in fixtures)
        if (fixture.hasTeams &&
            (fixture.state == SportsFixtureState.scheduled ||
                fixture.state == SportsFixtureState.live))
          _Target(fixture),
    ];
    if (targets.isEmpty) return const {};

    final needles = <String>{for (final target in targets) ...target.needles};
    final namedChannels = await _repo.liveChannelsNamedLike(needles);

    // Per fixture: guide id -> its strongest programme. One guide query per
    // run of overlapping kickoff windows, with only that run's teams, so a
    // week of fixtures never scans the week's replays and talk shows.
    final guideHits = <String, Map<String, (SportsMatchKind, EpgProgram)>>{};
    for (final group in _windowGroups(targets)) {
      final programs = await _repo.programmesMentioning(
        endAfter: group.first.fixture.start.add(_windowStartOffset),
        startBefore: group.last.fixture.start.add(_windowEndOffset),
        needles: {for (final target in group) ...target.needles},
      );
      if (programs.isEmpty) continue;
      final normalized = [
        for (final program in programs) _NormalizedProgram(program),
      ];
      for (final target in group) {
        _collectGuideHits(target, normalized, guideHits);
      }
    }

    final guideIds = <String>{
      for (final hits in guideHits.values) ...hits.keys,
    };
    final guideChannels = await _repo.liveChannelsForGuideIds(guideIds);
    final normalizedNames = {
      for (final channel in namedChannels)
        channel.id: SportsMatcher.normalize(channel.name),
    };

    final result = <String, List<SportsChannelMatch>>{};
    for (final target in targets) {
      final byChannel = <int, SportsChannelMatch>{};
      void offer(SportsChannelMatch match) {
        final existing = byChannel[match.channel.id];
        if (existing == null || match.kind.index < existing.kind.index) {
          byChannel[match.channel.id] = match;
        }
      }

      final hits = guideHits[target.fixture.id];
      if (hits != null) {
        for (final channel in guideChannels) {
          for (final id in _guideIdsOf(channel)) {
            final hit = hits[id];
            if (hit == null) continue;
            offer(
              SportsChannelMatch(
                channel: channel,
                kind: hit.$1,
                program: hit.$2,
              ),
            );
            break;
          }
        }
      }
      for (final channel in namedChannels) {
        if (target.namesBoth(normalizedNames[channel.id]!)) {
          offer(
            SportsChannelMatch(
              channel: channel,
              kind: SportsMatchKind.channelName,
            ),
          );
        }
      }
      if (byChannel.isEmpty) continue;
      final matches = byChannel.values.toList()
        ..sort((a, b) {
          final byKind = a.kind.index.compareTo(b.kind.index);
          if (byKind != 0) return byKind;
          return _matchGap(a, target.fixture).compareTo(
            _matchGap(b, target.fixture),
          );
        });
      result[target.fixture.id] = matches.length > _maxPerFixture
          ? matches.sublist(0, _maxPerFixture)
          : matches;
    }
    return result;
  }

  /// [targets] sorted by kickoff and split wherever one kickoff's window
  /// ends before the next one's starts.
  static List<List<_Target>> _windowGroups(List<_Target> targets) {
    final sorted = [...targets]
      ..sort((a, b) => a.fixture.start.compareTo(b.fixture.start));
    final groups = <List<_Target>>[];
    for (final target in sorted) {
      final group = groups.isEmpty ? null : groups.last;
      final windowEnd = group?.last.fixture.start.add(_windowEndOffset);
      if (group != null &&
          !target.fixture.start.add(_windowStartOffset).isAfter(windowEnd!)) {
        group.add(target);
      } else {
        groups.add([target]);
      }
    }
    return groups;
  }

  static void _collectGuideHits(
    _Target target,
    List<_NormalizedProgram> programs,
    Map<String, Map<String, (SportsMatchKind, EpgProgram)>> guideHits,
  ) {
    final windowStart = target.fixture.start.add(_windowStartOffset);
    final windowEnd = target.fixture.start.add(_windowEndOffset);
    for (final program in programs) {
      final p = program.program;
      if (!p.end.isAfter(windowStart) || !p.start.isBefore(windowEnd)) {
        continue;
      }
      final kind = target.programKind(program);
      if (kind == null) continue;
      final hits = guideHits.putIfAbsent(target.fixture.id, () => {});
      final existing = hits[p.channelId];
      if (existing == null ||
          kind.index < existing.$1.index ||
          (kind == existing.$1 &&
              _gap(p, target.fixture) < _gap(existing.$2, target.fixture))) {
        hits[p.channelId] = (kind, p);
      }
    }
  }

  /// The identifiers a channel's guide may be stored under, in
  /// `EpgService.lookupForChannel`'s order.
  static Iterable<String> _guideIdsOf(Channel channel) sync* {
    for (final id in [channel.epgChannelId, channel.tvgName, channel.name]) {
      if (id != null && id.isNotEmpty) yield id;
    }
  }

  static Duration _gap(EpgProgram program, SportsFixture fixture) =>
      program.start.difference(fixture.start).abs();

  static Duration _matchGap(SportsChannelMatch match, SportsFixture fixture) {
    final program = match.program;
    return program == null ? Duration.zero : _gap(program, fixture);
  }
}

class _Target {
  _Target(this.fixture)
    : home = SportsMatcher.phrasesFor(fixture.home!.team),
      away = SportsMatcher.phrasesFor(fixture.away!.team),
      needles = {
        ...SportsMatcher.needlesFor(fixture.home!.team),
        ...SportsMatcher.needlesFor(fixture.away!.team),
      };

  final SportsFixture fixture;
  final Set<String> home;
  final Set<String> away;
  final Set<String> needles;

  bool namesBoth(String normalized) =>
      home.isNotEmpty &&
      away.isNotEmpty &&
      SportsMatcher.mentions(normalized, home) &&
      SportsMatcher.mentions(normalized, away);

  SportsMatchKind? programKind(_NormalizedProgram program) {
    if (home.isEmpty || away.isEmpty) return null;
    final homeInTitle = SportsMatcher.mentions(program.title, home);
    final awayInTitle = SportsMatcher.mentions(program.title, away);
    final homeInSubtitle = SportsMatcher.mentions(program.subtitle, home);
    final awayInSubtitle = SportsMatcher.mentions(program.subtitle, away);
    if ((homeInTitle && awayInTitle) || (homeInSubtitle && awayInSubtitle)) {
      return SportsMatchKind.guideHeadline;
    }
    final homeInHeadline = homeInTitle || homeInSubtitle;
    final awayInHeadline = awayInTitle || awayInSubtitle;
    if (homeInHeadline && awayInHeadline) return SportsMatchKind.guideSplit;
    if ((homeInHeadline || SportsMatcher.mentions(program.description, home)) &&
        (awayInHeadline || SportsMatcher.mentions(program.description, away))) {
      return SportsMatchKind.guideDescription;
    }
    return null;
  }
}

/// A programme's searchable fields, normalized once for every fixture.
class _NormalizedProgram {
  _NormalizedProgram(this.program)
    : title = SportsMatcher.normalize(program.title),
      subtitle = SportsMatcher.normalize(program.subtitle ?? ''),
      description = SportsMatcher.normalize(
        program.description.length > _descriptionScanLength
            ? program.description.substring(0, _descriptionScanLength)
            : program.description,
      );

  static const int _descriptionScanLength = 400;

  final EpgProgram program;
  final String title;
  final String subtitle;
  final String description;
}
