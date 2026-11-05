import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Games for the Sports screen, from M3U Editor's Sports integration.
///
/// The editor reads its sports providers, caches them for every client, finds
/// the channels showing each game, and proxies the team crests, so the app
/// never contacts a provider itself. Only available while the editor advertises the `sports` feature (see
/// [XtreamAuthResponse.hasSports]).
class SportsService {
  SportsService(this._xtream);

  final XtreamService _xtream;

  /// Every fixture of [leagues] starting in [from, to), soonest first.
  /// Throws when the editor can't be reached or refuses the request.
  Future<List<SportsFixture>> fixtures({
    required SportsCapability capability,
    required List<SportsLeague> leagues,
    required DateTime from,
    required DateTime to,
  }) async {
    if (leagues.isEmpty) return const [];
    final cappedTo = to.difference(from).inDays > capability.maxRangeDays
        ? from.add(Duration(days: capability.maxRangeDays))
        : to;
    final json = await _xtream.getSportsFixtures(
      capability,
      leagueIds: leagues.map((league) => league.id),
      from: from,
      to: cappedTo,
    );
    return parseFixtures(json, capability)
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The channels showing each game of [leagues] starting in [from, to], by
  /// [SportsFixture.key], strongest match first. The editor matches these on
  /// request against the guide, so ask for one day, after showing its games.
  /// Throws when the editor can't be reached or refuses the request.
  Future<Map<String, List<SportsChannelRef>>> channels({
    required SportsCapability capability,
    required List<SportsLeague> leagues,
    required DateTime from,
    required DateTime to,
  }) async {
    if (leagues.isEmpty) return const {};
    return parseChannels(
      await _xtream.getSportsChannels(
        capability,
        leagueIds: leagues.map((league) => league.id),
        from: from,
        to: to,
      ),
    );
  }

  /// One game's details as they stand now; null when the editor's provider
  /// has none. Throws when the editor can't be reached or refuses the request.
  Future<SportsFixtureDetails?> details({
    required SportsCapability capability,
    required SportsFixture fixture,
  }) async {
    return parseDetails(
      await _xtream.getSportsFixtureDetails(
        capability,
        leagueId: fixture.league.id,
        fixtureId: fixture.id,
      ),
      capability,
    );
  }

  /// Maps the editor's `get_sports_fixture_details` response. Exposed for
  /// tests.
  static SportsFixtureDetails? parseDetails(
    Object? json,
    SportsCapability capability,
  ) {
    final raw = json is Map ? json['details'] : null;
    if (raw is! Map) return null;
    final fixture = raw['fixture'];
    final info = raw['info'];
    return SportsFixtureDetails(
      fixture: fixture is Map ? _parseFixture(fixture, capability) : null,
      lineScore: _parseLineScore(raw['line_score']),
      events: [
        if (raw['events'] case final List<dynamic> events)
          for (final event in events) ?_parseEvent(event),
      ],
      stats: [
        if (raw['stats'] case final List<dynamic> stats)
          for (final stat in stats) ?_parseStat(stat),
      ],
      leaders: [
        if (raw['leaders'] case final List<dynamic> leaders)
          for (final category in leaders) ?_parseLeaders(category),
      ],
      venue: info is Map ? _string(info['venue']) : null,
      location: info is Map ? _string(info['location']) : null,
      attendance: info is Map && info['attendance'] is int
          ? info['attendance'] as int
          : null,
      officials: [
        if (info is Map && info['officials'] is List)
          for (final official in info['officials'] as List) ?_string(official),
      ],
      series: info is Map ? _string(info['series']) : null,
      homeRecord: info is Map ? _string(info['home_record']) : null,
      awayRecord: info is Map ? _string(info['away_record']) : null,
    );
  }

  static SportsLineScore? _parseLineScore(Object? json) {
    if (json is! Map) return null;
    List<String> column(String key) => [
      if (json[key] case final List<dynamic> values)
        for (final value in values) _string(value) ?? '-',
    ];
    final periods = column('periods');
    final home = column('home');
    final away = column('away');
    if (periods.isEmpty ||
        home.length != periods.length ||
        away.length != periods.length) {
      return null;
    }
    return SportsLineScore(periods: periods, home: home, away: away);
  }

  static SportsFixtureEvent? _parseEvent(Object? json) {
    if (json is! Map) return null;
    final text = _string(json['text']);
    if (text == null) return null;
    return SportsFixtureEvent(
      kind: switch (json['kind']) {
        'yellow_card' => SportsEventKind.yellowCard,
        'red_card' => SportsEventKind.redCard,
        'substitution' => SportsEventKind.substitution,
        'penalty' => SportsEventKind.penalty,
        _ => SportsEventKind.score,
      },
      text: text,
      time: _string(json['time']),
      side: switch (json['side']) {
        'home' => SportsSide.home,
        'away' => SportsSide.away,
        _ => null,
      },
      homeScore: _string(json['home_score']),
      awayScore: _string(json['away_score']),
    );
  }

  static SportsTeamStat? _parseStat(Object? json) {
    if (json is! Map) return null;
    final label = _string(json['label']);
    final home = _string(json['home']);
    final away = _string(json['away']);
    if (label == null || home == null || away == null) return null;
    return SportsTeamStat(label: label, home: home, away: away);
  }

  static SportsLeaderCategory? _parseLeaders(Object? json) {
    if (json is! Map) return null;
    final label = _string(json['label']);
    if (label == null) return null;
    SportsLeader? leader(Object? raw) {
      if (raw is! Map) return null;
      final name = _string(raw['name']);
      if (name == null) return null;
      return SportsLeader(
        name: name,
        value: _string(raw['value']),
        photoUrl: _string(raw['photo']),
      );
    }

    return SportsLeaderCategory(
      label: label,
      home: leader(json['home']),
      away: leader(json['away']),
    );
  }

  /// Maps the editor's `get_sports_channels` response, dropping entries
  /// without a usable stream id. Exposed for tests.
  static Map<String, List<SportsChannelRef>> parseChannels(Object? json) {
    final raw = json is Map ? json['channels'] : null;
    if (raw is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && value is List)
          key: [
            for (final channel in value)
              if (channel is Map && channel['stream_id'] is int)
                SportsChannelRef(
                  streamId: channel['stream_id'] as int,
                  programTitle: _string(channel['program_title']),
                ),
          ],
    };
  }

  /// Maps the editor's `get_sports_fixtures` response, dropping fixtures of
  /// leagues [capability] doesn't list or without a usable id and start.
  /// Exposed for tests.
  static List<SportsFixture> parseFixtures(
    Object? json,
    SportsCapability capability,
  ) {
    final rawFixtures = json is Map ? json['fixtures'] : null;
    if (rawFixtures is! List) return [];
    return [
      for (final raw in rawFixtures)
        if (raw is Map) ?_parseFixture(raw, capability),
    ];
  }

  static SportsFixture? _parseFixture(
    Map<dynamic, dynamic> json,
    SportsCapability capability,
  ) {
    final id = _string(json['id']);
    final league = capability.leagueById(_string(json['league_id']) ?? '');
    final start = DateTime.tryParse(_string(json['start']) ?? '')?.toUtc();
    if (id == null || league == null || start == null) return null;
    final broadcasts = json['broadcasts'];
    return SportsFixture(
      id: id,
      league: league,
      start: start,
      state: switch (json['state']) {
        'live' => SportsFixtureState.live,
        'finished' => SportsFixtureState.finished,
        'postponed' => SportsFixtureState.postponed,
        _ => SportsFixtureState.scheduled,
      },
      statusDetail: _string(json['status_detail']) ?? '',
      home: _parseCompetitor(json['home'], league.id),
      away: _parseCompetitor(json['away'], league.id),
      name: _string(json['name']),
      leagueLogoUrl: _string(json['league_logo']),
      broadcasts: [
        if (broadcasts is List)
          for (final broadcast in broadcasts) ?_string(broadcast),
      ],
    );
  }

  static SportsCompetitor? _parseCompetitor(Object? json, String leagueId) {
    if (json is! Map) return null;
    final team = _parseTeam(json['team'], leagueId);
    if (team == null) return null;
    return SportsCompetitor(
      team: team,
      score: _string(json['score']),
      winner: json['winner'] == true,
    );
  }

  static SportsTeam? _parseTeam(Object? team, String leagueId) {
    if (team is! Map) return null;
    final id = _string(team['id']);
    if (id == null) return null;
    final displayName = _string(team['display_name']) ?? id;
    return SportsTeam(
      leagueId: leagueId,
      id: id,
      displayName: displayName,
      shortName: _string(team['short_name']) ?? displayName,
      nickname: _string(team['nickname']) ?? displayName,
      abbreviation: _string(team['abbreviation']) ?? '',
      logoUrl: _string(team['logo']),
      colorHex: _string(team['color']),
      alternateColorHex: _string(team['alternate_color']),
      location: _string(team['location']),
    );
  }

  /// Every team of [league], alphabetically (the editor's order). Empty when
  /// the editor predates the team browser.
  Future<List<SportsTeam>> teams(
    SportsCapability capability,
    SportsLeague league,
  ) async {
    if (!capability.listsTeams) return const [];
    return parseTeams(
      await _xtream.getSportsTeams(capability, league.id),
      league.id,
    );
  }

  /// Maps the editor's `get_sports_teams` response. Exposed for tests.
  static List<SportsTeam> parseTeams(Object? json, String leagueId) {
    final rawTeams = json is Map ? json['teams'] : null;
    if (rawTeams is! List) return const [];
    return [for (final raw in rawTeams) ?_parseTeam(raw, leagueId)];
  }

  static String? _string(Object? raw) {
    if (raw == null) return null;
    final text = '$raw'.trim();
    return text.isEmpty ? null : text;
  }
}
