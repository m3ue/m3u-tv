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

  group('compareNatural', () {
    test('sorts symbols before digits before letters', () {
      final names = ['Zebra', '&TV', '00s Replay']..sort(compareNatural);
      expect(names, ['&TV', '00s Replay', 'Zebra']);
    });

    test('compares numeric runs by value, not lexically', () {
      final names = ['Channel 10', 'Channel 2']..sort(compareNatural);
      expect(names, ['Channel 2', 'Channel 10']);
    });

    test('is case-insensitive', () {
      final names = ['bbc', 'ABC']..sort(compareNatural);
      expect(names, ['ABC', 'bbc']);
    });

    test('compares a digit run too long for an int by value', () {
      final names = [
        'A 99999999999999999999 x',
        'A 100000000000000000000 x',
        'A 1 x',
      ]..sort(compareNatural);
      expect(names, [
        'A 1 x',
        'A 99999999999999999999 x',
        'A 100000000000000000000 x',
      ]);
    });

    test('a shorter prefix sorts first', () {
      final names = ['ESPN 2 HD', 'ESPN 2', 'ESPN']..sort(compareNatural);
      expect(names, ['ESPN', 'ESPN 2', 'ESPN 2 HD']);
    });
  });

  group('sortByNatural', () {
    test('matches compareNatural for every pair', () {
      final names = [
        'Channel 10',
        'channel 2',
        '&TV',
        '00s Replay',
        '007 Classics',
        'Zebra',
        'zebra 1',
        'ABC',
        '',
        'News 24/7',
        'News 24',
      ];
      final expected = [...names]..sort(compareNatural);
      final sorted = [...names];
      sortByNatural(sorted, (name) => name);
      expect(sorted, expected);
      sortByNatural(sorted, (name) => name, descending: true);
      expect(sorted, expected.reversed.toList());
    });
  });
}
