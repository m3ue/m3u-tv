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
      final aNum = aChunk.number;
      final bNum = bChunk.number;
      final chunkCompare = aNum != null && bNum != null
          ? aNum.compareTo(bNum)
          : aChunk.lower.compareTo(bChunk.lower);
      if (chunkCompare != 0) return chunkCompare;
    }
    return a.length.compareTo(b.length);
  }
}

typedef _Chunk = ({int? number, String lower});

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
/// `\d+|\D+` chunking). A digit run too long for an int compares as text,
/// as `int.tryParse` returning null did.
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
      number: digits ? int.tryParse(text) : null,
      lower: digits ? text : text.toLowerCase(),
    ));
    start = end;
  }
  return chunks;
}
