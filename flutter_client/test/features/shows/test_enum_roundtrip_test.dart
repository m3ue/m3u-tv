// B8: Enum round-trip — verifies the wire-value contract for DvrSeriesMode
// and DvrMatchMode from domain_models.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('DvrSeriesMode wire contract', () {
    test('all round-trips correctly', () {
      expect(dvrSeriesModeFromWire('all'), DvrSeriesMode.all);
      expect(DvrSeriesMode.all.wireValue, 'all');
    });

    test('new_flag round-trips correctly', () {
      expect(dvrSeriesModeFromWire('new_flag'), DvrSeriesMode.newFlag);
      expect(DvrSeriesMode.newFlag.wireValue, 'new_flag');
    });

    test('unique_se round-trips correctly', () {
      expect(dvrSeriesModeFromWire('unique_se'), DvrSeriesMode.uniqueSe);
      expect(DvrSeriesMode.uniqueSe.wireValue, 'unique_se');
    });

    test('null falls back to uniqueSe (server column default)', () {
      expect(dvrSeriesModeFromWire(null), DvrSeriesMode.uniqueSe);
    });

    test('legacy new_only maps to newFlag', () {
      expect(dvrSeriesModeFromWire('new_only'), DvrSeriesMode.newFlag);
    });

    test('legacy new maps to newFlag', () {
      expect(dvrSeriesModeFromWire('new'), DvrSeriesMode.newFlag);
    });

    test('unknown wire value falls back to uniqueSe', () {
      expect(dvrSeriesModeFromWire('random_garbage'), DvrSeriesMode.uniqueSe);
    });

    test('DvrSeriesMode has no regex variant (exhaustiveness check)', () {
      // The enum only has three values. If .regex were added later, this switch
      // would be a compile error until updated — proving the contract.
      for (final mode in DvrSeriesMode.values) {
        switch (mode) {
          case DvrSeriesMode.all:
          case DvrSeriesMode.newFlag:
          case DvrSeriesMode.uniqueSe:
            break;
        }
      }
    });
  });

  group('DvrMatchMode wire contract', () {
    test('contains round-trips correctly', () {
      expect(dvrMatchModeFromWire('contains'), DvrMatchMode.contains);
      expect(DvrMatchMode.contains.wireValue, 'contains');
    });

    test('exact round-trips correctly', () {
      expect(dvrMatchModeFromWire('exact'), DvrMatchMode.exact);
      expect(DvrMatchMode.exact.wireValue, 'exact');
    });

    test('starts_with round-trips correctly', () {
      expect(dvrMatchModeFromWire('starts_with'), DvrMatchMode.startsWith);
      expect(DvrMatchMode.startsWith.wireValue, 'starts_with');
    });

    test('tmdb round-trips correctly', () {
      expect(dvrMatchModeFromWire('tmdb'), DvrMatchMode.tmdb);
      expect(DvrMatchMode.tmdb.wireValue, 'tmdb');
    });

    test('null falls back to contains (documented default)', () {
      expect(dvrMatchModeFromWire(null), DvrMatchMode.contains);
    });

    test('unknown wire value falls back to contains', () {
      expect(dvrMatchModeFromWire('random_garbage'), DvrMatchMode.contains);
    });

    test('DvrMatchMode covers all documented wire values (exhaustiveness)', () {
      for (final mode in DvrMatchMode.values) {
        switch (mode) {
          case DvrMatchMode.contains:
          case DvrMatchMode.exact:
          case DvrMatchMode.startsWith:
          case DvrMatchMode.tmdb:
            break;
        }
      }
    });
  });
}
