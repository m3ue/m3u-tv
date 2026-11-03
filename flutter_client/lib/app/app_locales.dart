import 'package:flutter/widgets.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;

/// [AppLocalizations.localizationsDelegates] with `material_ui`'s Material and
/// Cupertino delegates in place of `flutter_localizations`' (which gen-l10n
/// still emits). `material_ui` widgets look up their own
/// `MaterialLocalizations` type, and its `MaterialApp` only bundles the
/// English default, so without these any non-English locale finds no
/// localizations at all.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

/// [AppLocalizations.supportedLocales] as handed to Flutter's `Localizations`,
/// each passed through [qualifiedAppLocale].
final List<Locale> appSupportedLocales = List.unmodifiable(
  AppLocalizations.supportedLocales.map(qualifiedAppLocale),
);

/// The locale every `Text` inherits as its paragraph locale, which also picks
/// the Han glyph forms platform font fallback uses. Chinese names its script
/// and region: Windows DirectWrite treats a bare `zh` like an unknown language
/// and falls back to a Japanese font, drawing the UI and any Chinese channel
/// or programme names in Japanese glyph forms (Plezy 846eef4a4). The app ships
/// Simplified Chinese only, so a bare `zh` is Simplified.
Locale qualifiedAppLocale(Locale locale) =>
    locale.languageCode == 'zh' && locale.scriptCode == null
    ? const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hans',
        countryCode: 'CN',
      )
    : locale;
