import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_catalog_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Serves scripted catalog pages keyed by `skip`, recording each request.
class _FakeAioApi extends AIOStreamsApiService {
  _FakeAioApi(this.pages)
    : super(
        xtreamService: XtreamService(
          transport: (_) async => throw StateError('no network in tests'),
        ),
      );

  final Map<int, List<AIOStreamsItem>> pages;
  final List<int> requestedSkips = [];

  @override
  Future<List<AIOStreamsItem>> getCatalog(
    int integrationId,
    String type,
    String catalogId, {
    int skip = 0,
    String? search,
    String? genre,
  }) async {
    requestedSkips.add(skip);
    return pages[skip] ?? const [];
  }
}

List<AIOStreamsItem> _items(int from, int to) => [
  for (var n = from; n <= to; n++)
    AIOStreamsItem(id: 'tt$n', type: 'movie', name: 'Movie $n'),
];

const _catalog = AIOStreamsCatalog(id: 'top', type: 'movie', name: 'Top');

Widget _harness(_FakeAioApi api) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: AIOStreamsCatalogScreen(
    integrationId: 1,
    catalog: _catalog,
    apiService: api,
    onItemSelect: (_) {},
  ),
);

/// Scrolling to the bottom of the grid loads the next page, as it would
/// for a user D-padding or scrolling down.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -10000));
  await tester.pumpAndSettle();
}

void main() {
  // First pages are 20 items so the autofocused first card sits outside the
  // prefetch window and paging waits for Load more.
  testWidgets('pages by the item offset the addon returned', (tester) async {
    final api = _FakeAioApi({0: _items(1, 20), 20: _items(21, 25)});
    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(api.requestedSkips, [0]);
    await _scrollToEnd(tester);

    expect(api.requestedSkips, [0, 20]);
    expect(find.byType(MediaPreviewCard, skipOffstage: false), findsWidgets);
  });

  testWidgets('a page shorter than 20 does not end paging', (tester) async {
    // Addon page sizes vary; only an empty page (or one adding nothing new)
    // proves the catalog is exhausted.
    final api = _FakeAioApi({0: _items(1, 20), 20: _items(21, 25)});
    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();
    await _scrollToEnd(tester);

    // The 5-item page didn't end paging: reaching the end again asks for
    // the page after it.
    await _scrollToEnd(tester);
    expect(api.requestedSkips, [0, 20, 25]);
  });

  testWidgets('stops once a page adds nothing new', (tester) async {
    // An addon that ignores skip keeps returning its first page.
    final api = _FakeAioApi({0: _items(1, 20), 20: _items(1, 20)});
    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    await _scrollToEnd(tester);

    expect(find.text('Load more'), findsNothing);
    expect(api.requestedSkips, [0, 20]);
  });

  testWidgets('focusing a card near the end prefetches the next page', (
    tester,
  ) async {
    // With four cards the autofocused first card is already inside the
    // prefetch window.
    final api = _FakeAioApi({0: _items(1, 4), 4: _items(5, 6)});
    await tester.pumpWidget(_harness(api));
    await tester.pumpAndSettle();

    expect(api.requestedSkips, [0, 4]);
    expect(find.byType(MediaPreviewCard), findsNWidgets(6));
  });
}
