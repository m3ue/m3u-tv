// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/sports_models.dart';

/// Sports preferences: which competitions are listed (per device) and which
/// teams "My Teams" follows.
///
/// Follows sync per viewer through M3U Editor when it offers that (see
/// `AppStateController._syncSportsFollows`): the list held here is then the
/// active viewer's, replaced from the server on every viewer sync, and each
/// local change is pushed through [onFollowChanged]. Without sync it is
/// simply this device's own list.
class SportsSettings extends ChangeNotifier {
  SportsSettings({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_sports';

  final PersistentJsonStore? _store;

  /// The viewer's chosen competition ids; null until they choose, which
  /// lists the editor's defaults.
  Set<String>? _leagueIds;
  List<FollowedSportsTeam> _followedTeams = const [];

  /// Viewers whose follows have been reconciled with the server at least
  /// once, so this device's own list is only merged in the first time.
  Set<String> _syncedViewers = const {};

  /// Called after a local follow or unfollow, to push it to the server.
  void Function(FollowedSportsTeam team, {required bool followed})?
  onFollowChanged;

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

  Future<void>? _loading;

  /// Loads the stored preferences once; later calls wait on that load.
  /// Anything that replaces stored state (a follows sync) must wait for it,
  /// or the load would land afterwards and restore the stale list.
  Future<void> ensureLoaded() => _loading ??= load();

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
    final synced = raw['synced_viewers'];
    if (synced is List) {
      _syncedViewers = {
        for (final ulid in synced)
          if (ulid is String) ulid,
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
    final followed = FollowedSportsTeam.fromTeam(team);
    _followedTeams = following
        ? [..._followedTeams.where((t) => t.key != team.key)]
        : [..._followedTeams, followed];
    notifyListeners();
    await _persist();
    onFollowChanged?.call(followed, followed: !following);
    return !following;
  }

  /// Whether [viewerUlid]'s follows were ever reconciled with the server.
  bool hasSynced(String viewerUlid) => _syncedViewers.contains(viewerUlid);

  /// Whether any viewer's were, i.e. this device's own list has already
  /// been merged into an account once.
  bool get hasSyncedAnyViewer => _syncedViewers.isNotEmpty;

  /// Takes the server's list for [viewerUlid] as the followed teams.
  Future<void> replaceFollows(
    List<FollowedSportsTeam> follows, {
    required String viewerUlid,
  }) async {
    _followedTeams = List.unmodifiable(follows);
    _syncedViewers = {..._syncedViewers, viewerUlid};
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{
      if (_leagueIds case final ids?) 'leagues': ids.toList(),
      'teams': [for (final team in _followedTeams) team.toJson()],
      'synced_viewers': _syncedViewers.toList(),
    });
  }
}
