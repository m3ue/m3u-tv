/// Text folding for searching team names: lowercased, accents removed.
class SportsMatcher {
  const SportsMatcher._();

  /// Lowercases, folds accents, turns every run of anything but letters and
  /// digits into one space, and pads both ends with a space so a phrase can
  /// be found as `' $phrase '`.
  static String normalize(String text) {
    final buffer = StringBuffer(' ');
    var pendingSpace = false;
    for (final rune in text.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      final folded = _fold[char] ?? char;
      final isWord =
          (rune >= 0x30 && rune <= 0x39) ||
          (rune >= 0x61 && rune <= 0x7a) ||
          _fold.containsKey(char);
      if (isWord) {
        if (pendingSpace && buffer.length > 1) buffer.write(' ');
        pendingSpace = false;
        buffer.write(folded);
      } else {
        pendingSpace = true;
      }
    }
    buffer.write(' ');
    return buffer.toString();
  }

  static const Map<String, String> _fold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
    'ă': 'a', 'ą': 'a', 'æ': 'ae', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e', //
    'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ı': 'i', 'ł': 'l',
    'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', //
    'ö': 'o', 'ø': 'o', 'ő': 'o', 'œ': 'oe', 'ř': 'r', 'ś': 's', 'š': 's',
    'ş': 's', 'ș': 's', 'ß': 'ss', 'ť': 't', 'ţ': 't', 'ț': 't', 'ù': 'u', //
    'ú': 'u', 'û': 'u', 'ü': 'u', 'ű': 'u', 'ů': 'u', 'ý': 'y', 'ÿ': 'y',
    'ž': 'z', 'ź': 'z', 'ż': 'z',
  };
}
