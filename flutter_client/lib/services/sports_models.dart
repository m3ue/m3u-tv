/// Value types for the Sports screen: competitions, teams and fixtures as
/// M3U Editor serves them (it reads ESPN's scoreboards on the app's behalf).
/// Plain data with no Flutter or I/O dependency so the matcher and its tests
/// can use them freely.
library;

/// What the editor advertises when Sports is enabled (`m3u_editor.sports` in
/// the auth response): the competitions it can list and how to ask for
/// their games.
class SportsCapability {
  const SportsCapability({
    required this.leagues,
    this.fixturesAction = 'get_sports_fixtures',
    this.teamsAction,
    this.followsAction,
    this.toggleFollowAction,
    this.syncFollowsAction,
    this.maxRangeDays = 14,
  });

  factory SportsCapability.fromJson(Map<String, dynamic> json) {
    final actions = json['actions'];
    final rawLeagues = json['leagues'];
    final rawSportNames = json['sport_names'];
    final sportNames = <String, String>{
      if (rawSportNames is Map)
        for (final MapEntry(:key, :value) in rawSportNames.entries)
          if (key is String && value is String && value.isNotEmpty) key: value,
    };
    final maxRangeDays = json['max_range_days'];
    String? action(String name) {
      final value = actions is Map ? actions[name] : null;
      return value is String && value.isNotEmpty ? value : null;
    }

    return SportsCapability(
      leagues: [
        if (rawLeagues is List)
          for (final league in rawLeagues)
            if (league is Map) ?SportsLeague.fromJson(league, sportNames),
      ],
      fixturesAction: action('fixtures') ?? 'get_sports_fixtures',
      teamsAction: action('teams'),
      followsAction: action('follows'),
      toggleFollowAction: action('toggle_follow'),
      syncFollowsAction: action('sync_follows'),
      maxRangeDays: maxRangeDays is int && maxRangeDays > 0 ? maxRangeDays : 14,
    );
  }

  /// In the editor's display order.
  final List<SportsLeague> leagues;
  final String fixturesAction;

  /// Null on editors predating the team browser or follow sync.
  final String? teamsAction;
  final String? followsAction;
  final String? toggleFollowAction;
  final String? syncFollowsAction;

  /// Whether every team of a league can be listed (the team browser).
  bool get listsTeams => teamsAction != null;

  /// Whether follows sync per viewer through the editor.
  bool get syncsFollows =>
      followsAction != null &&
      toggleFollowAction != null &&
      syncFollowsAction != null;

  /// The longest span one fixtures request may cover.
  final int maxRangeDays;

  SportsLeague? leagueById(String id) {
    for (final league in leagues) {
      if (league.id == id) return league;
    }
    return null;
  }
}

/// A competition the Sports screen can list ("hockey/nhl").
class SportsLeague {
  const SportsLeague({
    required this.id,
    required this.name,
    required this.abbreviation,
    this.soccerStyle = false,
    this.isDefault = false,
    this.sportDisplayName,
  });

  /// [sportNames] maps the sport that starts an id to its display name.
  static SportsLeague? fromJson(
    Map<dynamic, dynamic> json, [
    Map<String, String> sportNames = const {},
  ]) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final abbreviation = json['abbreviation'];
    return SportsLeague(
      id: id,
      name: name,
      abbreviation: abbreviation is String ? abbreviation : name,
      soccerStyle: json['soccer_style'] == true,
      isDefault: json['default'] == true,
      sportDisplayName: sportNames[id.split('/').first],
    );
  }

  final String id;
  final String name;
  final String abbreviation;

  /// The sport the league belongs to, the start of its id ("hockey").
  String get sport => id.split('/').first;

  /// The sport's display name from the editor ("Rugby League").
  final String? sportDisplayName;

  /// [sportDisplayName], else the sport's id.
  String get sportName => sportDisplayName ?? sport;

  /// Football (soccer) lists the home side first ("Arsenal v Chelsea");
  /// North American leagues list the away side first ("Jets at Bills").
  final bool soccerStyle;

  /// Listed until the viewer picks their own competitions.
  final bool isDefault;
}

/// One side of a fixture, or a followed team.
class SportsTeam {
  const SportsTeam({
    required this.leagueId,
    required this.id,
    required this.displayName,
    required this.shortName,
    required this.nickname,
    required this.abbreviation,
    this.logoUrl,
    this.colorHex,
    this.alternateColorHex,
    this.location,
  });

  final String leagueId;
  final String id;

  /// "Toronto Maple Leafs"
  final String displayName;

  /// "Maple Leafs" for pro teams, the school for college ("Alabama").
  final String shortName;

  /// The team name without its place: "Maple Leafs", "Crimson Tide".
  final String nickname;
  final String abbreviation;
  final String? logoUrl;

  /// Bare hex without `#` ("003e7e"), as the provider sends it.
  final String? colorHex;
  final String? alternateColorHex;

  /// The team's place; for a college, its school ("Southern Illinois").
  final String? location;

  /// Stable across fixtures and leagues: what follows are keyed by.
  String get key => '$leagueId:$id';
}

enum SportsFixtureState { scheduled, live, finished, postponed }

class SportsCompetitor {
  const SportsCompetitor({required this.team, this.score, this.winner = false});

  final SportsTeam team;

  /// The provider's score text; null before the game starts.
  final String? score;
  final bool winner;
}

class SportsFixture {
  const SportsFixture({
    required this.id,
    required this.league,
    required this.start,
    required this.state,
    required this.statusDetail,
    this.home,
    this.away,
    this.name,
    this.broadcasts = const [],
    this.leagueLogoUrl,
  });

  final String id;
  final SportsLeague league;

  /// The league's logo (through the editor's logo proxy), made for dark
  /// backgrounds where ESPN has one.
  final String? leagueLogoUrl;

  /// Kickoff, UTC.
  final DateTime start;
  final SportsFixtureState state;

  /// The provider's short status line: "2nd - 12:34", "Final/OT",
  /// "Top 5th". Shown verbatim while live or finished.
  final String statusDetail;
  final SportsCompetitor? home;
  final SportsCompetitor? away;

  /// "Utah Mammoth at Toronto Maple Leafs"
  final String? name;

  /// Broadcaster names the provider lists ("ESPN+", "TNT").
  final List<String> broadcasts;

  bool get hasTeams => home != null && away != null;

  /// The two sides in display order (see [SportsLeague.soccerStyle]).
  List<SportsCompetitor> get displayOrder {
    final home = this.home;
    final away = this.away;
    if (home == null || away == null) {
      return [?home, ?away];
    }
    return league.soccerStyle ? [home, away] : [away, home];
  }

  bool involves(Set<String> teamKeys) =>
      teamKeys.contains(home?.team.key) || teamKeys.contains(away?.team.key);
}

/// A followed team as "My Teams" lists it, kept with enough to render the
/// row without a fetch.
class FollowedSportsTeam {
  const FollowedSportsTeam({
    required this.key,
    required this.name,
    this.logoUrl,
  });

  factory FollowedSportsTeam.fromTeam(SportsTeam team) => FollowedSportsTeam(
    key: team.key,
    name: team.displayName,
    logoUrl: team.logoUrl,
  );

  final String key;
  final String name;
  final String? logoUrl;

  Map<String, Object?> toJson() => {
    'key': key,
    'name': name,
    if (logoUrl != null) 'logo': logoUrl,
  };

  /// A follow as M3U Editor's `get_sports_follows` returns it.
  static FollowedSportsTeam? fromServer(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['team_key'];
    final name = raw['name'];
    if (key is! String || key.isEmpty || name is! String) return null;
    final logo = raw['logo'];
    return FollowedSportsTeam(
      key: key,
      name: name,
      logoUrl: logo is String && logo.isNotEmpty ? logo : null,
    );
  }

  static FollowedSportsTeam? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final name = raw['name'];
    if (key is! String || name is! String) return null;
    final logo = raw['logo'];
    return FollowedSportsTeam(
      key: key,
      name: name,
      logoUrl: logo is String ? logo : null,
    );
  }
}
