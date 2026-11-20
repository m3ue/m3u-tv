import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/series_detail_widgets.dart';
import 'package:m3u_tv/shared/touch_input_scope.dart';
import 'package:material_ui/material_ui.dart';

Widget _rowScrollRegionHarness({
  required ScrollController controller,
  bool? isTouch,
}) {
  final Widget region = RowScrollRegion(
    controller: controller,
    child: const SizedBox(height: 3000, width: 400),
  );
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: isTouch == null
            ? region
            : TouchInputScope(isTouch: isTouch, child: region),
      ),
    ),
  );
}

void main() {
  testWidgets('wide detail page drag-scrolls on touch devices', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _rowScrollRegionHarness(controller: controller, isTouch: true),
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('wide detail page ignores drags without a touch scope (TV)', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_rowScrollRegionHarness(controller: controller));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
  });
}
