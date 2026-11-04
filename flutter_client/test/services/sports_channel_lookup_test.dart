import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/sports_channel_lookup.dart';
import 'package:m3u_tv/services/sports_models.dart';

void main() {
  const first = Channel(id: 1, name: 'One', streamUrl: 'http://x/1');
  const second = Channel(id: 2, name: 'Two', streamUrl: 'http://x/2');

  test("keeps the editor's order and drops channels not on this device", () {
    final matches = sportsChannelMatchesFrom(
      const {
        'hockey/nhl:401': [
          SportsChannelRef(streamId: 2, programTitle: 'NHL Hockey'),
          SportsChannelRef(streamId: 99),
          SportsChannelRef(streamId: 1),
        ],
        'hockey/nhl:402': [SportsChannelRef(streamId: 99)],
      },
      const {1: first, 2: second},
    );

    expect(matches['hockey/nhl:401']!.map((match) => match.channel.id), [2, 1]);
    expect(matches['hockey/nhl:401']!.first.programTitle, 'NHL Hockey');
    expect(matches['hockey/nhl:401']!.last.programTitle, isNull);
    expect(matches['hockey/nhl:402'], isEmpty);
  });
}
