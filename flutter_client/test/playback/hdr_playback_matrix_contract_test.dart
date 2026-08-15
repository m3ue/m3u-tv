import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HDR playback matrix records the phase-one delivery contract', () {
    final document = File('../docs/migration/hdr-playback-matrix.md');

    expect(document.existsSync(), isTrue);
    final text = document.readAsStringSync();

    for (final target in <String>[
      'Android phone/tablet',
      'Android TV',
      'iOS',
      'iPadOS',
      'tvOS',
      'macOS',
      'Linux',
      'Windows',
    ]) {
      expect(text, contains('## $target'));
      expect(
        text,
        contains('$target real-device/real-runtime: unverified/blocker'),
      );
    }

    for (final format in <String>['HDR10', 'HDR10+', 'HLG', 'Dolby Vision']) {
      expect(text, contains(format));
    }
    for (final state in <String>[
      'source HDR detected',
      'HDR output active',
      'HDR tone-mapped to SDR',
      'HDR unsupported/unavailable',
    ]) {
      expect(text, contains(state));
    }

    expect(text, contains('PR #209 is pending Draft'));
    expect(text, contains('Issue #167 is In review'));
    expect(
      text,
      contains(
        'Server transcode is unverified and not HDR-capable until complete generated output and delivery path prove metadata preservation and renderer behavior.',
      ),
    );
    expect(
      text,
      contains(
        'Native events and diagnostics may contain only normalized non-sensitive transfer characteristics, color primaries, color space, and bit depth.',
      ),
    );
    expect(
      text,
      contains(
        'They must not contain stream URLs, headers, credentials, tokens, or raw native payloads.',
      ),
    );
    expect(text, contains('| Target | Backend and native path |'));
    expect(text, contains('| HDR10 | HDR10+ | HLG | Dolby Vision |'));
  });
}
