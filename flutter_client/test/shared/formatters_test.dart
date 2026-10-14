import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/formatters.dart';

void main() {
  group('nullIfBlank', () {
    test('trims, and treats blank as absent', () {
      expect(nullIfBlank('  Action '), 'Action');
      expect(nullIfBlank('   '), isNull);
      expect(nullIfBlank(''), isNull);
      expect(nullIfBlank(null), isNull);
    });
  });

  group('formatRuntime', () {
    test('renders hours and minutes, dropping empty parts', () {
      expect(formatRuntime(const Duration(minutes: 135)), '2h 15m');
      expect(formatRuntime(const Duration(hours: 2)), '2h');
      expect(formatRuntime(const Duration(minutes: 45, seconds: 59)), '45m');
      expect(formatRuntime(Duration.zero), '0m');
    });
  });

  group('parseRuntimeText', () {
    test('reads the runtime formats the payloads carry', () {
      expect(
        parseRuntimeText('01:40:09'),
        const Duration(hours: 1, minutes: 40, seconds: 9),
      );
      expect(parseRuntimeText('1:45'), const Duration(hours: 1, minutes: 45));
      expect(parseRuntimeText('2h 50m'), const Duration(hours: 2, minutes: 50));
      expect(parseRuntimeText('2h'), const Duration(hours: 2));
      expect(parseRuntimeText('50m'), const Duration(minutes: 50));
      expect(parseRuntimeText('95 min'), const Duration(minutes: 95));
      expect(parseRuntimeText('120'), const Duration(minutes: 120));
      expect(parseRuntimeText('45:00'), const Duration(minutes: 45));
      expect(
        parseRuntimeText('12:30'),
        const Duration(minutes: 12, seconds: 30),
      );
      expect(parseRuntimeText('2700'), const Duration(minutes: 45));
      expect(parseRuntimeText('300'), const Duration(hours: 5));
    });

    test('returns null for empty or unreadable text', () {
      expect(parseRuntimeText(null), isNull);
      expect(parseRuntimeText(''), isNull);
      expect(parseRuntimeText('0'), isNull);
      expect(parseRuntimeText('00:00:00'), isNull);
      expect(parseRuntimeText('unknown'), isNull);
    });
  });

  group('formatRuntimeText', () {
    test('normalises parseable runtimes', () {
      expect(formatRuntimeText('01:40:00'), '1h 40m');
      expect(formatRuntimeText('136 min'), '2h 16m');
      expect(formatRuntimeText('2h 50m'), '2h 50m');
    });

    test('keeps unparseable text and drops blank text', () {
      expect(formatRuntimeText(' Feature length '), 'Feature length');
      expect(formatRuntimeText('  '), isNull);
      expect(formatRuntimeText(null), isNull);
    });
  });

  group('formatBytes', () {
    test('uses GB from 1 GiB and whole MB below it', () {
      expect(formatBytes(1610612736), '1.5 GB');
      expect(formatBytes(1073741824), '1.0 GB');
      expect(formatBytes(358612992), '342 MB');
    });
  });

  group('formatRating', () {
    test('always shows one decimal place', () {
      expect(formatRating(7.5), '★ 7.5');
      expect(formatRating(8), '★ 8.0');
      expect(formatRating(7.25), '★ 7.3');
    });

    test('appends an upper-cased source', () {
      expect(formatRating(7.5, source: 'tmdb'), '★ 7.5 TMDB');
      expect(formatRating(7.5, source: ' '), '★ 7.5');
    });

    test('parses text ratings, passing non-numeric text through', () {
      expect(formatRatingText('7.5'), '★ 7.5');
      expect(formatRatingText(' 8 '), '★ 8.0');
      expect(formatRatingText('PG'), '★ PG');
      expect(formatRatingText(''), isNull);
      expect(formatRatingText(null), isNull);
    });
  });
}
