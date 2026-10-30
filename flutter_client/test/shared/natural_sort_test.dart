import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/natural_sort.dart';

import '../fixtures/generated_channel_names.dart';

void main() {
  test('encode orders exactly as compareTo over generated names', () {
    final names = generateNames(3000);
    final keys = [for (final name in names) NaturalSortKey.of(name)];
    final encoded = [for (final key in keys) key.encode()];
    final random = Random(7);
    for (var n = 0; n < 50000; n++) {
      final a = random.nextInt(names.length);
      final b = random.nextInt(names.length);
      expect(
        encoded[a].compareTo(encoded[b]).sign,
        keys[a].compareTo(keys[b]).sign,
        reason: '"${names[a]}" vs "${names[b]}"',
      );
    }
  });

  test('encode handles the edge cases compareTo defines', () {
    int encodedSign(String a, String b) => NaturalSortKey.of(
      a,
    ).encode().compareTo(NaturalSortKey.of(b).encode()).sign;

    expect(encodedSign('', '&TV'), -1);
    expect(encodedSign('&TV', '00s'), -1);
    expect(encodedSign('00s', 'Zebra'), -1);
    expect(encodedSign('Channel 2', 'Channel 10'), -1);
    expect(encodedSign('ESPN', 'ESPN 2'), -1);
    expect(encodedSign('ESPN 2', 'ESPN 2 HD'), -1);
    expect(encodedSign('abc', 'ABC'), 0);
    expect(encodedSign('007', '7'), 0);
    expect(
      encodedSign('A 99999999999999999999', 'A 100000000000000000000'),
      -1,
    );
  });
}
