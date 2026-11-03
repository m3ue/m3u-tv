// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/sports_models.dart';

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

/// Per-device Sports preferences: which competitions are listed and which
/// teams "My Teams" follows. Device-level rather than per playlist, since
/// neither depends on the provider.
class SportsSettings extends ChangeNotifier {
  SportsSettings({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_sports';

  final PersistentJsonStore? _store;

  /// The viewer's chosen competition ids; null until they choose, which
  /// lists the editor's defaults.
  Set<String>? _leagueIds;
  List<FollowedSportsTeam> _followedTeams = const [];

  /// The competitions of [available] (the editor's, in its order) to list.
  List<SportsLeague> enabledLeagues(List<SportsLeague> available) => [
    for (final league in available)
      if (isLeagueEnabled(league)) league,
  ];

  bool isLeagueEnabled(SportsLeague league) =>
      _leagueIds?.contains(league.id) ?? league.isDefault;

  List<FollowedSportsTeam> get followedTeams => _followedTeams;

  Set<String> get followedTeamKeys => {
    for (final team in _followedTeams) team.key,
  };

  bool isFollowing(String teamKey) =>
      _followedTeams.any((team) => team.key == teamKey);

  Future<void> load() async {
    final raw = await _store?.read(_storeKey);
    if (raw is! Map) return;
    final leagues = raw['leagues'];
    if (leagues is List) {
      _leagueIds = {
        for (final id in leagues)
          if (id is String) id,
      };
    }
    final teams = raw['teams'];
    if (teams is List) {
      _followedTeams = [
        for (final team in teams.map(FollowedSportsTeam.fromJson)) ?team,
      ];
    }
    notifyListeners();
  }

  /// Lists [league] or stops listing it. The first choice starts from the
  /// defaults among [available], so turning one league off keeps the rest.
  Future<void> setLeagueEnabled(
    SportsLeague league, {
    required bool enabled,
    required List<SportsLeague> available,
  }) async {
    if (enabled == isLeagueEnabled(league)) return;
    final ids =
        _leagueIds ??
        {
          for (final candidate in available)
            if (candidate.isDefault) candidate.id,
        };
    _leagueIds = enabled
        ? {...ids, league.id}
        : {...ids.where((id) => id != league.id)};
    notifyListeners();
    await _persist();
  }

  /// Follows [team], or stops following it. Returns whether it is now
  /// followed.
  Future<bool> toggleFollow(SportsTeam team) async {
    final following = isFollowing(team.key);
    _followedTeams = following
        ? [..._followedTeams.where((t) => t.key != team.key)]
        : [..._followedTeams, FollowedSportsTeam.fromTeam(team)];
    notifyListeners();
    await _persist();
    return !following;
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{
      if (_leagueIds case final ids?) 'leagues': ids.toList(),
      'teams': [for (final team in _followedTeams) team.toJson()],
    });
  }
}
