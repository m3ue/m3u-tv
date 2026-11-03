import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_manage_dialog.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

Channel _channel(int id) => Channel(
  id: id,
  name: 'Channel $id',
  streamUrl: 'http://example.com/$id.m3u8',
);

Future<void> _pumpDialog(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showMultiviewManageDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists queued channels and removes one via its icon button', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(multiviewControllerProvider)
      ..toggle(_channel(1))
      ..toggle(_channel(2));

    await _pumpDialog(tester, container);

    expect(find.text('Channel 1'), findsOneWidget);
    expect(find.text('Channel 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Channel 1'));
    await tester.pumpAndSettle();

    expect(find.text('Channel 1'), findsNothing);
    expect(find.text('Channel 2'), findsOneWidget);
    expect(controller.channels.map((c) => c.id), [2]);
  });

  testWidgets('Clear All empties the queue and closes the dialog', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(multiviewControllerProvider)
      ..toggle(_channel(1))
      ..toggle(_channel(2));

    await _pumpDialog(tester, container);

    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();

    expect(controller.channels, isEmpty);
    expect(find.text('Manage Multiview'), findsNothing);
  });

  testWidgets('removing the last channel closes the dialog', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(multiviewControllerProvider)
      ..toggle(_channel(1));

    await _pumpDialog(tester, container);

    await tester.tap(find.byTooltip('Remove Channel 1'));
    await tester.pumpAndSettle();

    expect(controller.channels, isEmpty);
    expect(find.text('Manage Multiview'), findsNothing);
  });
}
