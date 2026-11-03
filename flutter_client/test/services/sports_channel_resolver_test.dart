import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_store.dart';
import 'package:m3u_tv/services/sports_channel_resolver.dart';
import 'package:m3u_tv/services/sports_matcher.dart';
import 'package:m3u_tv/services/sports_models.dart';

const SportsLeague _nhl = SportsLeague(
  id: 'hockey/nhl',
  name: 'NHL',
  abbreviation: 'NHL',
);
final DateTime _kickoff = DateTime.utc(2026, 11, 4);

SportsTeam _team(String id, String name, String nickname) => SportsTeam(
  leagueId: _nhl.id,
  id: id,
  displayName: name,
  shortName: nickname,
  nickname: nickname,
  abbreviation: id.toUpperCase(),
);

final SportsTeam _leafs = _team('tor', 'Toronto Maple Leafs', 'Maple Leafs');
final SportsTeam _mammoth = _team('uta', 'Utah Mammoth', 'Mammoth');
final SportsTeam _rangers = _team('nyr', 'New York Rangers', 'Rangers');
final SportsTeam _blues = _team('stl', 'St. Louis Blues', 'Blues');

SportsFixture _fixture(
  String id,
  SportsTeam home,
  SportsTeam away, {
  DateTime? start,
  SportsFixtureState state = SportsFixtureState.scheduled,
}) => SportsFixture(
  id: id,
  league: _nhl,
  start: start ?? _kickoff,
  state: state,
  statusDetail: '',
  home: SportsCompetitor(team: home),
  away: SportsCompetitor(team: away),
);

Channel _channel(int id, String name, {String? epgId, String? tvgName}) =>
    Channel(
      id: id,
      name: name,
      streamUrl: 'http://host/live/$id.ts',
      epgChannelId: epgId,
      tvgName: tvgName,
    );

EpgProgram _program(
  String channelId,
  String title, {
  String? subtitle,
  String description = '',
  Duration startOffset = Duration.zero,
  Duration length = const Duration(hours: 3),
}) => EpgProgram(
  channelId: channelId,
  title: title,
  subtitle: subtitle,
  description: description,
  start: _kickoff.add(startOffset),
  end: _kickoff.add(startOffset + length),
);

void main() {
  group('SportsMatcher', () {
    test('normalize folds case, accents and punctuation', () {
      expect(
        SportsMatcher.normalize('Atlético-Madrid: LIVE!'),
        ' atletico madrid live ',
      );
      expect(SportsMatcher.normalize('St. Louis'), ' st louis ');
    });

    test('phrases name the team, never just its city', () {
      final phrases = SportsMatcher.phrasesFor(_rangers);
      expect(
        phrases,
        containsAll(['new york rangers', 'rangers', 'ny rangers']),
      );
      expect(phrases, isNot(contains('new york')));
      expect(
        SportsMatcher.mentions(' new york knicks at boston ', phrases),
        isFalse,
      );
      expect(
        SportsMatcher.mentions(' nhl hockey rangers at blues ', phrases),
        isTrue,
      );
    });

    test('a college is named by its school, never its nickname alone', () {
      const team = SportsTeam(
        leagueId: 'basketball/mens-college-basketball',
        id: '79',
        displayName: 'Southern Illinois Salukis',
        shortName: 'S Illinois',
        nickname: 'Salukis',
        abbreviation: 'SIU',
        location: 'Southern Illinois',
      );
      final phrases = SportsMatcher.phrasesFor(team);
      expect(phrases, contains('southern illinois'));
      expect(phrases, isNot(contains('salukis')));

      const cougars = SportsTeam(
        leagueId: 'basketball/mens-college-basketball',
        id: '2',
        displayName: 'Charleston Cougars',
        shortName: 'Charleston',
        nickname: 'Cougars',
        abbreviation: 'COFC',
        location: 'Charleston',
      );
      expect(
        SportsMatcher.mentions(
          SportsMatcher.normalize('Burlington Cougars vs Georgetown'),
          SportsMatcher.phrasesFor(cougars),
        ),
        isFalse,
      );
    });

    test('needles skip words a shorter phrase already covers', () {
      // "toronto" would also pull in every Raptors and Blue Jays listing.
      expect(SportsMatcher.needlesFor(_leafs), {'maple'});
      expect(SportsMatcher.needlesFor(_rangers), {'rangers'});
    });

    test('needles cover accented and folded spellings', () {
      const team = SportsTeam(
        leagueId: 'soccer/esp.1',
        id: '1',
        displayName: 'Atlético Madrid',
        shortName: 'Atlético',
        nickname: 'Atlético Madrid',
        abbreviation: 'ATM',
      );
      expect(
        SportsMatcher.needlesFor(team),
        containsAll(['atlético', 'atletico']),
      );
    });
  });

  group('SportsChannelResolver', () {
    late CatalogDatabase db;
    late CatalogRepository repo;
    late SportsChannelResolver resolver;

    setUp(() {
      db = CatalogDatabase.memory();
      repo = CatalogRepository(db);
      resolver = SportsChannelResolver(repo);
    });

    tearDown(() => db.close());

    Future<void> seed(
      List<Channel> channels,
      Map<String, List<EpgProgram>> guide,
    ) async {
      await repo.replaceItems(
        sourceKey: repo.shownSource,
        kind: kCatalogKindLive,
        items: channels,
      );
      await repo.applyEpgOps([EpgReplaceChannels(guide)]);
    }

    test('finds guide and event-channel matches, strongest first', () async {
      await seed(
        [
          _channel(1, 'Sportsnet Ontario', epgId: 'sn.on'),
          _channel(2, 'NHL 05: Mammoth @ Maple Leafs 7PM'),
          _channel(3, 'TSN 4', epgId: 'tsn4'),
          _channel(4, 'Sportsnet Ontario HD', epgId: 'sn.on'),
          _channel(5, 'Unrelated', epgId: 'other'),
        ],
        {
          'sn.on': [
            // The pre-game show ends at kickoff: not the game.
            _program(
              'sn.on',
              'Maple Leafs Pre-Game vs Mammoth',
              startOffset: const Duration(hours: -1),
              length: const Duration(hours: 1),
            ),
            _program('sn.on', 'NHL Hockey', subtitle: 'Mammoth at Maple Leafs'),
          ],
          'tsn4': [
            _program('tsn4', 'NHL Hockey: Maple Leafs', subtitle: 'vs Mammoth'),
          ],
          'other': [_program('other', 'Maple Leafs Classics')],
        },
      );

      final result = await resolver.resolve([
        _fixture('g1', _leafs, _mammoth),
      ]);
      final matches = result['g1']!;
      expect(matches.map((m) => (m.channel.id, m.kind)), [
        (1, SportsMatchKind.guideHeadline),
        (4, SportsMatchKind.guideHeadline),
        (2, SportsMatchKind.channelName),
        (3, SportsMatchKind.guideSplit),
      ]);
      expect(matches.first.program?.subtitle, 'Mammoth at Maple Leafs');
    });

    test('a guide keyed by tvg-name still finds its channel', () async {
      await seed(
        [_channel(1, 'Hockey Night', tvgName: 'hockey.night')],
        {
          'hockey.night': [
            _program('hockey.night', 'Rangers at Blues'),
          ],
        },
      );
      final result = await resolver.resolve([
        _fixture('g1', _blues, _rangers),
      ]);
      expect(result['g1']!.single.channel.id, 1);
    });

    test('ignores other games, finished games and far-off airings', () async {
      await seed(
        [
          _channel(1, 'Network', epgId: 'net'),
        ],
        {
          'net': [
            // Same teams, but a replay airing hours before kickoff.
            _program(
              'net',
              'Mammoth at Maple Leafs (Replay)',
              startOffset: const Duration(hours: -6),
            ),
            // The live slot carries a different game.
            _program('net', 'Rangers at Blues'),
          ],
        },
      );
      final result = await resolver.resolve([
        _fixture('leafs', _leafs, _mammoth),
        _fixture(
          'done',
          _blues,
          _rangers,
          state: SportsFixtureState.finished,
        ),
      ]);
      expect(result, isEmpty);
    });

    test('resolves fixtures days apart in separate guide windows', () async {
      final later = _kickoff.add(const Duration(days: 2));
      await seed(
        [_channel(1, 'Network', epgId: 'net')],
        {
          'net': [
            _program('net', 'Mammoth at Maple Leafs'),
            _program(
              'net',
              'Rangers at Blues',
              startOffset: const Duration(days: 2),
            ),
          ],
        },
      );
      final result = await resolver.resolve([
        _fixture('first', _leafs, _mammoth),
        _fixture('second', _blues, _rangers, start: later),
      ]);
      expect(result.keys, unorderedEquals(['first', 'second']));
    });
  });
}
