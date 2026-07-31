import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

void main() {
  test('saved Direct M3U refresh error is generated for every locale', () {
    const translations = <String, String>{
      'en': 'Unable to refresh the saved Direct M3U source.',
      'de':
          'Die gespeicherte Direct-M3U-Quelle konnte nicht aktualisiert werden.',
      'es': 'No se pudo actualizar la fuente Direct M3U guardada.',
      'fr': "Impossible d'actualiser la source Direct M3U enregistrée.",
      'zh': '无法刷新已保存的 Direct M3U 来源。',
    };

    for (final MapEntry(key: locale, value: expected) in translations.entries) {
      final arb =
          jsonDecode(
                File('lib/l10n/app_$locale.arb').readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(
        arb['settingsSavedM3uRefreshFailed'],
        expected,
        reason: 'app_$locale.arb must define the localized recovery error',
      );

      final generated = lookupAppLocalizations(Locale(locale));
      expect(
        generated.settingsSavedM3uRefreshFailed,
        expected,
        reason: 'the generated $locale getter must match its ARB',
      );
    }
  });
}
