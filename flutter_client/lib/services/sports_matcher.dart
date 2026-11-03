import 'package:m3u_tv/services/sports_models.dart';

/// Pure text matching between a fixture's teams and guide/channel text.
///
/// A team is "named" by a text when one of its phrases (full name, short
/// name, nickname, or a known alias) appears in it as whole words, after
/// both are lowercased, accent-folded and stripped to letters and digits.
/// A single place name ("Toronto", "New York") is deliberately not a
/// phrase: one city fields teams in several leagues.
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

  /// Whether [normalizedText] (from [normalize]) names any of [phrases].
  static bool mentions(String normalizedText, Set<String> phrases) {
    for (final phrase in phrases) {
      if (normalizedText.contains(' $phrase ')) return true;
    }
    return false;
  }

  /// The normalized phrases that name [team].
  static Set<String> phrasesFor(SportsTeam team) => {
    for (final name in _namesFor(team)) ?_phrase(name),
  };

  /// Lowercase substrings for a SQL `LIKE` prefilter: any text that names
  /// the team contains at least one of them.
  ///
  /// One word per phrase (its longest), shortest phrases first, and none
  /// for a phrase already holding a chosen word: "Maple Leafs" gives
  /// `maple`, which "Toronto Maple Leafs" contains too, so `toronto` (and
  /// every Raptors listing it would pull in) is never searched. Accented
  /// words are searched as written and folded, since `LIKE` folds neither.
  static Set<String> needlesFor(SportsTeam team) {
    final names = [
      for (final name in _namesFor(team))
        if (_phrase(name) != null) name,
    ]..sort((a, b) => a.length.compareTo(b.length));
    final chosen = <String>{};
    final needles = <String>{};
    for (final name in names) {
      final folded = normalize(name).trim().split(' ');
      if (folded.any(chosen.contains)) continue;
      final raw = name
          .toLowerCase()
          .split(_nonWord)
          .where((word) => word.isNotEmpty)
          .toList();
      var longest = 0;
      for (var i = 1; i < folded.length; i++) {
        if (folded[i].length > folded[longest].length) longest = i;
      }
      chosen.add(folded[longest]);
      needles.add(folded[longest]);
      // Same split both ways unless the name has letters `normalize` drops.
      if (raw.length == folded.length) needles.add(raw[longest]);
    }
    return needles;
  }

  static final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  /// A college is named by its school (`location`: ESPN abbreviates its
  /// short name to "S Illinois"), never by its nickname alone, since
  /// hundreds of schools share "Wolves" or "Cougars". A pro nickname is
  /// distinctive in its league, so pros keep it.
  static Iterable<String> _namesFor(SportsTeam team) sync* {
    yield team.displayName;
    yield team.shortName;
    if (team.leagueId.contains('college') || team.leagueId.contains('.ncaa.')) {
      final location = team.location;
      if (location != null) yield location;
    } else {
      yield team.nickname;
    }
    final trimmed = _clubAffix.firstMatch(team.displayName);
    if (trimmed != null) yield trimmed.group(1)!;
    yield* _aliases[normalize(team.displayName).trim()] ?? const <String>[];
  }

  /// "Seattle Sounders FC" -> "Seattle Sounders", "AFC Bournemouth" ->
  /// "Bournemouth".
  static final RegExp _clubAffix = RegExp(
    r'^(?:(?:AFC|FC|CF|SC|CD|AC|SV|VfB|VfL|TSG|RCD|SSC|AS)\s+)?(.+?)(?:\s+(?:FC|CF|SC|AFC))?$',
  );

  static String? _phrase(String name) {
    final phrase = normalize(name).trim();
    if (phrase.length < 3 || _tooGeneric.contains(phrase)) return null;
    return phrase;
  }

  /// Phrases that can't stand for one team on their own.
  static const Set<String> _tooGeneric = {
    'united',
    'city',
    'club',
    'real',
    'sporting',
    'athletic',
    'athletics',
    'state',
    'college',
    'university',
    'los angeles',
    'new york',
    'new england',
    'san francisco',
    'chicago',
    'toronto',
    'washington',
  };

  /// Common short forms guides use that the provider's names don't cover,
  /// keyed by the provider's normalized full name.
  static const Map<String, List<String>> _aliases = {
    'manchester united': ['Man Utd', 'Man United'],
    'manchester city': ['Man City'],
    'tottenham hotspur': ['Tottenham', 'Spurs'],
    'wolverhampton wanderers': ['Wolves', 'Wolverhampton'],
    'brighton hove albion': ['Brighton'],
    'newcastle united': ['Newcastle'],
    'west ham united': ['West Ham'],
    'nottingham forest': ["Nott'm Forest", 'Forest'],
    'leeds united': ['Leeds'],
    'paris saint germain': ['PSG', 'Paris SG', 'Paris'],
    'bayern munich': ['Bayern', 'Bayern Munchen', 'FC Bayern'],
    'borussia dortmund': ['Dortmund', 'BVB'],
    'borussia monchengladbach': ['Gladbach', 'Monchengladbach'],
    'bayer leverkusen': ['Leverkusen'],
    'internazionale': ['Inter', 'Inter Milan'],
    'ac milan': ['Milan'],
    'juventus': ['Juve'],
    'atletico madrid': ['Atletico', 'Atleti'],
    'barcelona': ['Barca', 'FC Barcelona'],
    'athletic club': ['Athletic Bilbao', 'Bilbao'],
    'inter miami cf': ['Inter Miami'],
    'la galaxy': ['Galaxy'],
    'new york red bulls': ['Red Bulls', 'NY Red Bulls'],
    'new york city fc': ['NYCFC', 'NYC FC'],
    'los angeles fc': ['LAFC'],
    'los angeles lakers': ['LA Lakers'],
    'los angeles clippers': ['LA Clippers'],
    'la clippers': ['Los Angeles Clippers'],
    'los angeles kings': ['LA Kings'],
    'los angeles rams': ['LA Rams'],
    'los angeles chargers': ['LA Chargers'],
    'los angeles dodgers': ['LA Dodgers'],
    'los angeles angels': ['LA Angels'],
    'new york rangers': ['NY Rangers'],
    'new york islanders': ['NY Islanders'],
    'new york knicks': ['NY Knicks'],
    'new york giants': ['NY Giants'],
    'new york jets': ['NY Jets'],
    'new york yankees': ['NY Yankees'],
    'new york mets': ['NY Mets'],
  };

  // Accented Latin letters guides commonly carry, folded to ASCII.
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
