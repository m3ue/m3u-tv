import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/cast_strip.dart';
import 'package:material_ui/material_ui.dart';

CastMember _m({required String name, int? id}) =>
    CastMember(name: name, id: id);

Widget _harness({
  required List<CastMember> members,
  ValueChanged<CastMember>? onTapMember,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CastStrip(
        members: members,
        autofocus: true,
        onTapMember: onTapMember,
      ),
    ),
  );
}

void main() {
  group('CastStrip onTapMember', () {
    testWidgets('tapping the focused card fires onTapMember', (tester) async {
      CastMember? tapped;
      final leo = _m(name: 'Leonardo DiCaprio', id: 6193);
      await tester.pumpWidget(
        _harness(
          members: [
            leo,
            _m(name: 'Tom Hardy'),
          ],
          onTapMember: (member) => tapped = member,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Leonardo DiCaprio'));
      await tester.pump();
      expect(tapped, leo);
    });

    testWidgets('Enter fires onTapMember with the currently focused member', (
      tester,
    ) async {
      CastMember? tapped;
      final leo = _m(name: 'Leonardo DiCaprio', id: 6193);
      final tom = _m(name: 'Tom Hardy', id: 2524);
      await tester.pumpWidget(
        _harness(members: [leo, tom], onTapMember: (member) => tapped = member),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(tapped, tom);
    });

    testWidgets('no crash when onTapMember is null and card is tapped', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(members: [_m(name: 'Solo')]));
      await tester.pump();

      await tester.tap(find.text('Solo'));
      await tester.pump();
    });
  });
}
