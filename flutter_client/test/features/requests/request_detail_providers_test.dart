import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/requests/request_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

final AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

ContentRequestSearchResult _movie({
  bool hdAvailable = false,
  bool uhdAvailable = false,
}) => ContentRequestSearchResult(
  type: 'movie',
  externalId: '603',
  integrationId: hdAvailable ? 2 : 1,
  integrationName: hdAvailable ? 'Radarr UHD' : 'Radarr HD',
  title: 'The Matrix',
  alreadyAvailable: hdAvailable && uhdAvailable,
  providers: [
    ContentRequestProvider(
      integrationId: 1,
      integrationName: 'Radarr HD',
      alreadyAvailable: hdAvailable,
    ),
    ContentRequestProvider(
      integrationId: 2,
      integrationName: 'Radarr UHD',
      alreadyAvailable: uhdAvailable,
    ),
  ],
);

MediaRequestSummary _pending(int integrationId) => MediaRequestSummary(
  id: integrationId * 10,
  type: 'movie',
  title: 'The Matrix',
  status: MediaRequestStatus.pendingApproval,
  externalId: '603',
  integrationId: integrationId,
);

Future<List<int>> _pump(
  WidgetTester tester,
  ContentRequestSearchResult result, {
  List<MediaRequestSummary> requests = const <MediaRequestSummary>[],
}) async {
  final submitted = <int>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mediaRequestsProvider.overrideWith((_) => requests)],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RequestDetailScreen(
          result: result,
          onSubmit:
              ({
                required type,
                required integrationId,
                required externalId,
                seasons,
              }) async {
                submitted.add(integrationId);
                return _pending(integrationId);
              },
        ),
      ),
    ),
  );
  await tester.pump();
  return submitted;
}

void main() {
  testWidgets('a single integration shows no picker, as before', (
    tester,
  ) async {
    await _pump(
      tester,
      const ContentRequestSearchResult(
        type: 'movie',
        externalId: '603',
        integrationId: 1,
        integrationName: 'Radarr',
        title: 'The Matrix',
      ),
    );

    expect(find.text(_l.requestsProviderHeading), findsNothing);
    expect(find.text(_l.requestsRequestButton), findsOneWidget);
  });

  testWidgets(
    'an integration that has the title does not hide one that can take it',
    (tester) async {
      final submitted = await _pump(tester, _movie(hdAvailable: true));

      expect(find.text(_l.requestsProviderHeading), findsOneWidget);
      expect(find.text('Radarr HD'), findsOneWidget);
      expect(find.text('Radarr UHD'), findsOneWidget);
      // Starts on UHD, the one that doesn't have it.
      expect(find.text(_l.requestsRequestButton), findsOneWidget);

      await tester.tap(find.text(_l.requestsRequestButton));
      await tester.pump();
      expect(submitted, [2]);

      await tester.tap(find.text('Radarr HD'));
      await tester.pump();
      expect(find.text(_l.requestsAlreadyAvailable), findsOneWidget);
    },
  );

  testWidgets('a request on one integration leaves the other requestable', (
    tester,
  ) async {
    await _pump(tester, _movie(), requests: [_pending(2)]);

    // Starts on HD: UHD already has this guest's request.
    expect(find.text(_l.requestsRequestButton), findsOneWidget);

    await tester.tap(find.text('Radarr UHD'));
    await tester.pump();
    expect(find.text(_l.requestsStatusPendingApproval), findsOneWidget);
    expect(find.text(_l.requestsRequestButton), findsNothing);
  });
}
