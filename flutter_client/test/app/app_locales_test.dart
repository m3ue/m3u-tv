import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/app/app_locales.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

void main() {
  const simplifiedChinese = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hans',
    countryCode: 'CN',
  );

  test('a bare zh names its script and region; other locales pass through', () {
    expect(qualifiedAppLocale(const Locale('zh')), simplifiedChinese);
    expect(qualifiedAppLocale(const Locale('de')), const Locale('de'));
    const traditional = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    expect(qualifiedAppLocale(traditional), traditional);
    expect(appSupportedLocales, contains(simplifiedChinese));
    expect(appSupportedLocales, isNot(contains(const Locale('zh'))));
  });

  for (final requested in [const Locale('zh'), const Locale('zh', 'CN')]) {
    testWidgets(
      '$requested resolves to zh_Hans_CN with Chinese strings and dates',
      (tester) async {
        late Locale resolved;
        late String title;
        late String time;
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: appSupportedLocales,
            locale: qualifiedAppLocale(requested),
            home: Builder(
              builder: (context) {
                resolved = Localizations.localeOf(context);
                title = AppLocalizations.of(context).navLiveTv;
                time = DateFormat.jm(
                  resolved.toLanguageTag(),
                ).format(DateTime(2026, 10, 21, 15, 30));
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(resolved, simplifiedChinese);
        expect(title, '直播电视');
        expect(
          time,
          DateFormat.jm('zh').format(DateTime(2026, 10, 21, 15, 30)),
        );
      },
    );
  }
}
