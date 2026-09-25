import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/clear_cache_dialog.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/cache_service.dart';

/// Pumps a host with a button that opens the dialog and records its result.
/// The returned getter reports whether the dialog closed and what it chose.
Future<(bool, CacheClearScope?) Function()> _host(WidgetTester tester) async {
  var closed = false;
  CacheClearScope? captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await showClearCacheDialog(context);
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => (closed, captured);
}

void main() {
  testWidgets('the default button clears everything', (tester) async {
    final result = await _host(tester);

    expect(find.text('Clear Cache & Refresh?'), findsOneWidget);
    await tester.tap(find.text('Clear & Refresh'));
    await tester.pumpAndSettle();

    expect(result(), (true, CacheClearScope.all));
  });

  for (final (label, scope) in [
    ('Everything', CacheClearScope.all),
    ('Content only', CacheClearScope.content),
    ('Guide (EPG) only', CacheClearScope.epg),
    ('Images only', CacheClearScope.images),
  ]) {
    testWidgets('"$label" resolves with ${scope.name}', (tester) async {
      final result = await _host(tester);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(result(), (true, scope));
    });
  }

  testWidgets('Cancel resolves with null', (tester) async {
    final result = await _host(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result(), (true, null));
  });
}
