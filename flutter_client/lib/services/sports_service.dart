import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Games for the Sports screen, from M3U Editor's Sports integration.
///
/// The editor reads ESPN's scoreboards, caches them for every client, and
/// proxies the team crests, so the app never contacts ESPN itself. Only
/// available while the editor advertises the `sports` feature (see
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
