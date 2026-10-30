import 'dart:math';

/// Channel-name-shaped strings: mixed case, digit runs (some zero-padded or
/// long), separators, symbols and a few non-ASCII letters.
List<String> generateNames(int count, {int seed = 285}) {
  final random = Random(seed);
  const pieces = [
    'ESPN',
    'espn',
    'BBC',
    'Sky',
    'sky',
    'News',
    'HD',
    'FHD',
    'UK',
    'US',
    'Café',
    'Ñ',
    'Ü',
    'ø',
    '|',
    '&',
    '#',
    '+',
    '.',
    '-',
    ' ',
    ' ',
    ':',
    '(',
    ')',
    '[',
    'é',
    'Z',
    'a',
    'b',
    'TV',
  ];
  String digits() {
    final length = 1 + random.nextInt(random.nextInt(10) == 0 ? 22 : 4);
    return List.generate(length, (_) => random.nextInt(10)).join();
  }

  return List.generate(count, (_) {
    final parts = random.nextInt(5);
    final buffer = StringBuffer();
    for (var i = 0; i < parts; i++) {
      buffer.write(
        random.nextInt(3) == 0
            ? digits()
            : pieces[random.nextInt(pieces.length)],
      );
    }
    return buffer.toString();
  });
}
