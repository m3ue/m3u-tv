import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';

/// How long a day's channels are reused. Score refreshes come far more often,
/// and a game's channels rarely change.
const Duration kSportsChannelsMaxAge = Duration(minutes: 10);

/// A channel showing a game, resolved to this device's catalog.
class SportsChannelMatch {
  const SportsChannelMatch({required this.channel, this.programTitle});

  final Channel channel;

  /// The guide listing that named the game; null when the channel's own title
  /// did (an event channel).
  final String? programTitle;
}

/// The editor's channels for each game of [leagues] starting in [from, to], by
/// [SportsFixture.key].
Future<Map<String, List<SportsChannelMatch>>> loadSportsChannelMatches({
  required SportsService service,
  required CatalogRepository repository,
  required SportsCapability capability,
  required List<SportsLeague> leagues,
  required DateTime from,
  required DateTime to,
}) async {
  final refs = await service.channels(
    capability: capability,
    leagues: leagues,
    from: from,
    to: to,
  );
  final channels = await repository.activeItemsByIds<Channel>(
    kind: kCatalogKindLive,
    ids: {
      for (final gameRefs in refs.values)
        for (final ref in gameRefs) ref.streamId,
    },
  );
  return sportsChannelMatchesFrom(refs, {
    for (final channel in channels) channel.id: channel,
  });
}

/// Pairs [refs] with [channels], keeping the editor's order. A channel not in
/// this device's catalog yet is left out.
Map<String, List<SportsChannelMatch>> sportsChannelMatchesFrom(
  Map<String, List<SportsChannelRef>> refs,
  Map<int, Channel> channels,
) {
  return {
    for (final MapEntry(:key, :value) in refs.entries)
      key: [
        for (final ref in value)
          if (channels[ref.streamId] case final channel?)
            SportsChannelMatch(
              channel: channel,
              programTitle: ref.programTitle,
            ),
      ],
  };
}
