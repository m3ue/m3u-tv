import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/catalog_window.dart';
import 'package:m3u_tv/shared/catalog_window_grid.dart';

/// In-memory source with a controllable delay so a fetch can be observed
/// mid-flight (the grid should show a placeholder until it lands).
class _Source {
  _Source(int size) : items = List<int>.generate(size, (i) => i);

  final List<int> items;
  Completer<void>? gate;

  Future<List<int>> page(int offset, int limit) async {
    if (gate != null) await gate!.future;
    final end = (offset + limit).clamp(0, items.length);
    return offset >= items.length ? const [] : items.sublist(offset, end);
  }

  Future<int> count() async => items.length;
}

Widget _host(CatalogWindow<int> window) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 400,
      child: CatalogWindowGrid<int>(
        window: window,
        crossAxisCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
        ),
        itemBuilder: (context, index, item) => Text('item-$item'),
        placeholderBuilder: (context, index) => Text('ph-$index'),
      ),
    ),
  ),
);

void main() {
  testWidgets('renders every on-screen slot as a real item once pages settle', (
    tester,
  ) async {
    final source = _Source(40);
    final window = CatalogWindow<int>(
      fetchPage: source.page,
      fetchCount: source.count,
      pageSize: 12,
    );
    addTearDown(window.dispose);

    await window.load();
    await tester.pumpWidget(_host(window));
    await tester.pumpAndSettle();

    expect(window.totalCount, 40);
    // ensureVisible pulled the pages covering the viewport, so no placeholder
    // survives a settle.
    expect(find.textContaining('ph-'), findsNothing);
    expect(find.text('item-0'), findsOneWidget);
    expect(
      find.text('item-12'),
      findsOneWidget,
    ); // second page loaded on demand
  });

  testWidgets(
    'a slot shows a placeholder until its page lands, then the item',
    (tester) async {
      final source = _Source(20);
      final window = CatalogWindow<int>(
        fetchPage: source.page,
        fetchCount: source.count,
        pageSize: 8,
      );
      addTearDown(window.dispose);

      source.gate = Completer<void>();
      unawaited(window.load());
      await tester.pumpWidget(_host(window));
      await tester.pump();

      expect(find.text('ph-0'), findsOneWidget);
      expect(find.text('item-0'), findsNothing);

      source.gate!.complete();
      await tester.pumpAndSettle();

      expect(find.text('item-0'), findsOneWidget);
      expect(find.text('ph-0'), findsNothing);
    },
  );

  testWidgets('scrolling loads later pages via ensureVisible', (tester) async {
    final source = _Source(400);
    final window = CatalogWindow<int>(
      fetchPage: source.page,
      fetchCount: source.count,
      pageSize: 20,
    );
    addTearDown(window.dispose);

    await window.load();
    await tester.pumpWidget(_host(window));
    await tester.pumpAndSettle();
    final afterFirstPaint = window.residentCount;

    await tester.drag(find.byType(GridView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    // Rows that scrolled into view triggered further page fetches.
    expect(window.residentCount, greaterThan(afterFirstPaint));
    expect(find.textContaining('item-'), findsWidgets);
  });
}
