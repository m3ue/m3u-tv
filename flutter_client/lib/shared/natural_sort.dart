/// Alphanumeric ("natural") string comparator: symbol-led names first, then
/// digit-led names, then letter-led names, and within each group, numeric
/// runs compare by value rather than lexically (`"2 Fast"` before
/// `"10 Things"`, not after). Matches the ordering scheme requested in
/// https://github.com/m3ue/m3u-tv/issues/285 for the Live TV channel list
/// ("special character first ... then by number ... then channels named
/// A-Z").
///
/// Tokenizes both strings on every call; to sort a large list, build one
/// [NaturalSortKey] per element up front instead (see [sortByNatural]).
int compareNatural(String a, String b) =>
    NaturalSortKey.of(a).compareTo(NaturalSortKey.of(b));

/// Sorts [items] in place by [nameOf] in [compareNatural] order (reversed
/// when [descending]), tokenizing each name once rather than once per
/// comparison. [tieBreak], when given, orders items ahead of the name
/// comparison (it decides first; names only break its ties).
void sortByNatural<T>(
  List<T> items,
  String Function(T item) nameOf, {
  bool descending = false,
  int Function(T a, T b)? tieBreak,
}) {
  if (items.length < 2) return;
  final decorated =
      [
        for (final item in items)
          (item: item, key: NaturalSortKey.of(nameOf(item))),
      ]..sort((a, b) {
        final first = tieBreak?.call(a.item, b.item) ?? 0;
        if (first != 0) return first;
        final cmp = a.key.compareTo(b.key);
        return descending ? -cmp : cmp;
      });
  for (var i = 0; i < decorated.length; i++) {
    items[i] = decorated[i].item;
  }
}

/// A string pre-split into the chunks [compareNatural] compares, so a sort
/// pays the tokenizing cost once per element instead of once per comparison.
class NaturalSortKey implements Comparable<NaturalSortKey> {
  NaturalSortKey._(this._group, this._chunks);

  factory NaturalSortKey.of(String s) =>
      NaturalSortKey._(_leadGroup(s), _tokenize(s));

  final int _group;
  final List<_Chunk> _chunks;

  @override
  int compareTo(NaturalSortKey other) {
    final groupCompare = _group.compareTo(other._group);
    if (groupCompare != 0) return groupCompare;
    final a = _chunks;
    final b = other._chunks;
    final length = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final aChunk = a[i];
      final bChunk = b[i];
      final aDigits = aChunk.digits;
      final bDigits = bChunk.digits;
      final chunkCompare = aDigits != null && bDigits != null
          ? _compareDigits(aDigits, bDigits)
          : aChunk.lower.compareTo(bChunk.lower);
      if (chunkCompare != 0) return chunkCompare;
    }
    return a.length.compareTo(b.length);
  }

  /// This key as a string whose plain binary order (SQLite's default `BINARY`
  /// collation, which compares UTF-8 bytes) matches [compareTo], so a
  /// promoted column can carry the natural sort into an `ORDER BY`.
  ///
  /// Layout: the lead group as one digit, then each chunk in turn. A digit
  /// run is its length (as one character) followed by its digits, so a
  /// longer number sorts later without padding. A text run is its lowercased
  /// text followed by U+0001, which sorts below every other character so a
  /// shorter run comes first, as in [compareTo]. Same-group keys always hold
  /// the same chunk kind at each position, so a digit chunk is only ever
  /// compared with another digit chunk.
  ///
  /// Two approximations, both outside what channel names realistically hold:
  /// U+0000 and U+0001 in a name encode as U+0002, and UTF-8 orders
  /// characters above U+FFFF (most emoji) after U+E000-U+FFFF, where Dart's
  /// UTF-16 comparison puts them before.
  String encode() {
    final out = StringBuffer()..writeCharCode(_zero + _group);
    for (final chunk in _chunks) {
      final digits = chunk.digits;
      if (digits != null) {
        out
          ..writeCharCode(_zero + digits.length)
          ..write(digits);
        continue;
      }
      final text = chunk.lower;
      if (text.codeUnits.any((unit) => unit < _textEnd + 1)) {
        for (final unit in text.codeUnits) {
          out.writeCharCode(unit < _textEnd + 1 ? _textEnd + 1 : unit);
        }
      } else {
        out.write(text);
      }
      out.writeCharCode(_textEnd);
    }
    return out.toString();
  }
}

/// Orders digit runs (leading zeros already stripped) by numeric value, at
/// any length.
int _compareDigits(String a, String b) {
  final lengthCompare = a.length.compareTo(b.length);
  return lengthCompare != 0 ? lengthCompare : a.compareTo(b);
}

/// [NaturalSortKey.encode]'s end-of-text-run marker.
const _textEnd = 0x01;

/// `digits` is set for a digit run (leading zeros stripped, `"0"` for all
/// zeros); `lower` is the run's text, lowercased.
typedef _Chunk = ({String? digits, String lower});

const _zero = 0x30;
const _nine = 0x39;

bool _isDigit(int code) => code >= _zero && code <= _nine;

/// 0 = leads with a non-alphanumeric character (or is empty), 1 = leads with
/// a digit, 2 = leads with a letter.
int _leadGroup(String s) {
  if (s.isEmpty) return 0;
  final code = s.codeUnitAt(0);
  const upperA = 0x41;
  const upperZ = 0x5a;
  const lowerA = 0x61;
  const lowerZ = 0x7a;
  if (_isDigit(code)) return 1;
  if ((code >= upperA && code <= upperZ) ||
      (code >= lowerA && code <= lowerZ)) {
    return 2;
  }
  return 0;
}

/// Splits [s] into alternating runs of ASCII digits and non-digits (the
/// `\d+|\D+` chunking).
List<_Chunk> _tokenize(String s) {
  final chunks = <_Chunk>[];
  var start = 0;
  while (start < s.length) {
    final digits = _isDigit(s.codeUnitAt(start));
    var end = start + 1;
    while (end < s.length && _isDigit(s.codeUnitAt(end)) == digits) {
      end++;
    }
    final text = s.substring(start, end);
    chunks.add((
      digits: digits ? _stripLeadingZeros(text) : null,
      lower: digits ? text : text.toLowerCase(),
    ));
    start = end;
  }
  return chunks;
}

String _stripLeadingZeros(String digits) {
  var start = 0;
  while (start < digits.length - 1 && digits.codeUnitAt(start) == _zero) {
    start++;
  }
  return start == 0 ? digits : digits.substring(start);
}
