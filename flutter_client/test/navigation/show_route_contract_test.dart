import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'show-details route builder uses l10n.showNotFound and wires onRecordSeries/onDeleteSeriesRule',
    () {
      const path = 'lib/navigation/go_router_config.dart';
      final source = File(path).readAsStringSync();

      expect(
        source,
        contains('AppLocalizations.of(context).showNotFound('),
        reason:
            'show-details route must localize the not-found text via l10n.showNotFound',
      );
      expect(
        source.contains(r'"Show "$normalizedTitle" not found"'),
        isFalse,
        reason:
            r'show-details route must not regress to the raw "Show $title not found" literal (B4 bug)',
      );
      expect(
        source,
        contains('onRecordSeries: actions.onRecordSeries'),
        reason:
            'ShowDetailScreen must receive a non-null onRecordSeries from ContentActions',
      );
      expect(
        source,
        contains('onDeleteSeriesRule: actions.onDeleteSeriesRule'),
        reason:
            'ShowDetailScreen must receive a non-null onDeleteSeriesRule from ContentActions',
      );
    },
  );
}
