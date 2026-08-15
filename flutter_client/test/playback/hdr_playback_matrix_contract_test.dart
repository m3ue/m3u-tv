import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _targets = <String>[
  'Android phone/tablet',
  'Android TV',
  'iOS',
  'iPadOS',
  'tvOS',
  'macOS',
  'Linux',
  'Windows',
];

const _formats = <String>['HDR10', 'HDR10+', 'HLG', 'Dolby Vision'];

const _decisions = <String>{
  'source HDR detected',
  'HDR output active',
  'HDR tone-mapped to SDR',
  'HDR unsupported/unavailable',
};

void _validateDocument(String text) {
  for (final section in <String>[
    'Threat Model',
    'Acceptance Criteria',
    'Detection',
    'Presentation',
    'Fallback',
    'User Communication',
  ]) {
    if (!RegExp(
      '^## ${RegExp.escape(section)}\$',
      multiLine: true,
    ).hasMatch(text)) {
      throw StateError('The $section section is missing.');
    }
  }

  final lines = text.split('\n');
  final headerIndex = lines.indexWhere(
    (line) =>
        _tableCells(line).isNotEmpty && _tableCells(line).first == 'Target',
  );
  if (headerIndex == -1 || headerIndex + 1 >= lines.length) {
    throw StateError('The decision table header is missing.');
  }

  final header = _tableCells(lines[headerIndex]);
  final separator = _tableCells(lines[headerIndex + 1]);
  if (header.length < 2 || separator.length != header.length) {
    throw StateError('The decision table is malformed.');
  }
  if (separator.any((cell) => !RegExp(r'^:?-{3,}:?$').hasMatch(cell))) {
    throw StateError('The decision table separator is malformed.');
  }

  final formatIndexes = <String, int>{};
  for (final format in _formats) {
    final indexes = <int>[
      for (var index = 0; index < header.length; index++)
        if (header[index] == format) index,
    ];
    if (indexes.length != 1) {
      throw StateError('The $format column is missing or duplicated.');
    }
    formatIndexes[format] = indexes.single;
  }

  final rowsByTarget = <String, List<String>>{};
  for (
    var index = headerIndex + 2;
    index < lines.length && lines[index].trimLeft().startsWith('|');
    index++
  ) {
    final row = _tableCells(lines[index]);
    if (row.length != header.length) {
      throw StateError('The decision table row is malformed.');
    }
    final target = row.first;
    if (!_targets.contains(target)) {
      throw StateError('The decision table has an unexpected target row.');
    }
    if (rowsByTarget.containsKey(target)) {
      throw StateError('The $target row is duplicated.');
    }
    rowsByTarget[target] = row;
  }

  if (rowsByTarget.length != _targets.length) {
    throw StateError('The decision table has missing target rows.');
  }
  for (final target in _targets) {
    final row = rowsByTarget[target];
    if (row == null) {
      throw StateError('The $target row is missing.');
    }
    for (final format in _formats) {
      final decision = row[formatIndexes[format]!];
      if (decision.isEmpty || !_decisions.contains(decision)) {
        throw StateError('The $target $format decision is invalid.');
      }
    }
  }

  for (final target in _targets) {
    if (!text.contains('## $target') ||
        !text.contains(
          '$target real-device/real-runtime: unverified/blocker',
        ) ||
        !text.contains('## $target\n\n') &&
            !text.contains('## $target\r\n\r\n')) {
      throw StateError('The $target real-device gate is missing.');
    }
  }

  for (final requiredText in <String>[
    'PR #209 is pending Draft',
    'Issue #167 is In review',
    'Server transcode is unverified and not HDR-capable until complete generated output and delivery path prove metadata preservation and renderer behavior.',
    'Native events and diagnostics may contain only normalized non-sensitive transfer characteristics, color primaries, color space, and bit depth.',
    'They must not contain stream URLs, headers, credentials, tokens, or raw native payloads.',
    'Child-delivery plan:',
    'https://developer.android.com/media/media3/exoplayer/supported-formats',
    'https://developer.apple.com/documentation/avfoundation/media_playback_and_selection',
    'https://mpv.io/manual/master/#options-hdr',
  ]) {
    if (!text.contains(requiredText)) {
      throw StateError('Required evidence is missing: $requiredText');
    }
  }
  if (text.contains('\u2013') || text.contains('\u2014')) {
    throw StateError('The document contains a prohibited dash character.');
  }
}

List<String> _tableCells(String line) {
  final trimmed = line.trim();
  if (!trimmed.startsWith('|') || !trimmed.endsWith('|')) {
    return const <String>[];
  }
  return trimmed
      .substring(1, trimmed.length - 1)
      .split('|')
      .map((cell) => cell.trim())
      .toList();
}

void main() {
  test('HDR playback matrix records the phase-one delivery contract', () {
    final document = File('../docs/migration/hdr-playback-matrix.md');

    expect(document.existsSync(), isTrue);
    final text = document.readAsStringSync();

    _validateDocument(text);
  });

  test('HDR playback matrix rejects a blank Android phone/tablet HDR10 cell', () {
    final text = File(
      '../docs/migration/hdr-playback-matrix.md',
    ).readAsStringSync();
    _validateDocument(text);

    final mutated = text.replaceFirst(
      '| Android phone/tablet | Media3 ExoPlayer to Flutter texture | HDR unsupported/unavailable |',
      '| Android phone/tablet | Media3 ExoPlayer to Flutter texture |  |',
    );

    expect(mutated, isNot(equals(text)));
    expect(() => _validateDocument(mutated), throwsStateError);
  });
}
