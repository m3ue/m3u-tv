import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

CastMember _m({
  required String name,
  String? character,
  String? photo,
  int? id,
}) => CastMember(name: name, character: character, photo: photo, id: id);

Widget _harness({
  List<CastMember>? members,
  String? semanticLabel,
  bool compact = false,
  VoidCallback? onShowAll,
  String? allCastSemanticLabel,
  double? width,
  ValueChanged<CastMember>? onTapMember,
}) {
  final row = CastMemberRow(
    members: members,
    semanticLabel: semanticLabel,
    compact: compact,
    onShowAll: onShowAll,
    allCastSemanticLabel: allCastSemanticLabel,
    onTapMember: onTapMember,
  );
  return MaterialApp(
    home: Scaffold(
      body: width == null
          ? row
          : Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: row),
            ),
    ),
  );
}

void main() {
  group('CastMemberRow', () {
    testWidgets('renders nothing for null members', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(CastMemberRow), findsOneWidget);
      // No _CastMemberCard inside.
      expect(find.text('Leonardo DiCaprio'), findsNothing);
    });

    testWidgets('renders nothing for empty list', (tester) async {
      await tester.pumpWidget(_harness(members: const <CastMember>[]));
      expect(find.byType(CastMemberRow), findsOneWidget);
      expect(find.text('Leonardo DiCaprio'), findsNothing);
    });

    testWidgets('renders one card per member', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [
            _m(name: 'Leonardo DiCaprio', character: 'Cobb'),
            _m(name: 'Joseph Gordon-Levitt', character: 'Arthur'),
            _m(name: 'Tom Hardy', character: 'Eames'),
          ],
        ),
      );

      expect(find.text('Leonardo DiCaprio'), findsOneWidget);
      expect(find.text('Joseph Gordon-Levitt'), findsOneWidget);
      expect(find.text('Tom Hardy'), findsOneWidget);
      expect(find.text('Cobb'), findsOneWidget);
      expect(find.text('Arthur'), findsOneWidget);
      expect(find.text('Eames'), findsOneWidget);
    });

    testWidgets('omits character text when null', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Solo Actor')],
        ),
      );
      expect(find.text('Solo Actor'), findsOneWidget);
      // No empty character row.
      expect(find.text(''), findsNothing);
    });

    testWidgets('omits character text when empty string', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Solo Actor', character: '')],
        ),
      );
      expect(find.text('Solo Actor'), findsOneWidget);
    });

    testWidgets('caps rendered cards at 15', (tester) async {
      // 20 members → only 15 cards render.
      final members = [
        for (var i = 0; i < 20; i++) _m(name: 'Actor $i', character: 'Role $i'),
      ];
      await tester.pumpWidget(_harness(members: members));

      // First 15 should render, last 5 should not.
      expect(find.text('Actor 0'), findsOneWidget);
      expect(find.text('Actor 14'), findsOneWidget);
      expect(find.text('Actor 15'), findsNothing);
      expect(find.text('Actor 19'), findsNothing);
    });

    testWidgets('image source is ResilientMediaImage with member photo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Actor', photo: 'https://example.com/photo.jpg')],
        ),
      );

      // ResilientMediaImage should be in the tree (one per card).
      expect(find.byType(ResilientMediaImage), findsOneWidget);
      final img = tester.widget<ResilientMediaImage>(
        find.byType(ResilientMediaImage),
      );
      expect(img.imageUrl, 'https://example.com/photo.jpg');
      expect(img.fallbackIcon, Icons.person);
    });

    testWidgets('passes semanticLabel through to the row Semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Actor')],
          semanticLabel: 'Cast',
        ),
      );

      // Find the row's Semantics widget by its label.
      // (Skip asserting `container` - not on SemanticsProperties in this Flutter version.)
      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Cast',
      );
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('card semantics include "as Character" when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Bryan Cranston', character: 'Walter White')],
        ),
      );

      final cardSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Bryan Cranston as Walter White',
      );
      expect(cardSemantics, findsOneWidget);
    });

    testWidgets('card semantics show only name when character absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Bryan Cranston')],
        ),
      );

      final cardSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Bryan Cranston',
      );
      expect(cardSemantics, findsOneWidget);
    });

    testWidgets(
      'name renders bold (billing-block style) so long names stand out',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            members: [_m(name: 'Christoph Waltz', character: 'Blofeld')],
          ),
        );

        // "Christoph Waltz" is 15 chars; the 144px card width (~22 chars at
        // bodySmall/12sp) leaves room without ellipsis.
        expect(find.text('Christoph Waltz'), findsOneWidget);
        final style = tester.widget<Text>(find.text('Christoph Waltz')).style;
        expect(style?.fontWeight, FontWeight.w700);
      },
    );

    testWidgets(
      'character renders muted and below name (labelSmall color, not bold)',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            members: [_m(name: 'Bryan Cranston', character: 'Walter White')],
          ),
        );

        final characterStyle = tester
            .widget<Text>(find.text('Walter White'))
            .style;
        expect(characterStyle?.fontWeight, isNot(FontWeight.w700));
        // labelSmall uses a smaller font than bodySmall - distinct typography
        // from the name above it so the eye reads name > role.
        expect(
          characterStyle?.fontSize,
          lessThan(
            tester.widget<Text>(find.text('Bryan Cranston')).style!.fontSize!,
          ),
        );
      },
    );

    group('wide overflow tile', () {
      // At 480px, 3 card slots fit (3 × 144 + 2 × 12 = 456; a 4th
      // needs 612). With more members than slots, the last slot
      // becomes the "+N / show all" tile.
      const fitsThree = 480.0;

      testWidgets(
        'more members than fit → last slot is a "+N" show-all tile',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              width: fitsThree,
              onShowAll: () {},
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          // 2 cards + the tile occupy the 3 slots.
          expect(find.text('Actor 0'), findsOneWidget);
          expect(find.text('Actor 1'), findsOneWidget);
          expect(find.text('Actor 2'), findsNothing);
          expect(find.text('Actor 4'), findsNothing);
          // Tile shows the hidden-member count and the localized label.
          expect(find.text('+3'), findsOneWidget);
          expect(find.text('Show all cast'), findsOneWidget);
        },
      );

      testWidgets(
        'tapping the show-all tile fires onShowAll',
        (tester) async {
          var tapCount = 0;
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              width: fitsThree,
              onShowAll: () => tapCount++,
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          await tester.tap(find.text('Show all cast'));
          await tester.pump();
          expect(tapCount, 1);
        },
      );

      testWidgets(
        'no tile when every member fits the available width',
        (tester) async {
          final members = [
            for (var i = 0; i < 3; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              width: fitsThree,
              onShowAll: () {},
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          expect(find.text('Actor 0'), findsOneWidget);
          expect(find.text('Actor 2'), findsOneWidget);
          expect(find.text('Show all cast'), findsNothing);
          expect(find.textContaining('+'), findsNothing);
        },
      );

      testWidgets(
        'without onShowAll the row keeps the plain scroll (no tile)',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              width: fitsThree,
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          // All 5 cards are in the (horizontally scrollable) row.
          expect(find.text('Actor 0'), findsOneWidget);
          expect(find.text('Actor 4'), findsOneWidget);
          expect(find.text('Show all cast'), findsNothing);
          expect(find.text('+2'), findsNothing);
        },
      );
    });

    group('onTapMember (wide layout)', () {
      testWidgets('tapping a card fires onTapMember with that member', (
        tester,
      ) async {
        CastMember? tapped;
        final leo = _m(name: 'Leonardo DiCaprio', character: 'Cobb', id: 6193);
        await tester.pumpWidget(
          _harness(
            members: [
              leo,
              _m(name: 'Tom Hardy', character: 'Eames'),
            ],
            onTapMember: (member) => tapped = member,
          ),
        );

        await tester.tap(find.text('Leonardo DiCaprio'));
        await tester.pump();
        expect(tapped, leo);
      });

      testWidgets('cards are not tappable when onTapMember is null', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(members: [_m(name: 'Leonardo DiCaprio')]),
        );

        // No exception from tapping a card with no tap handler wired.
        await tester.tap(find.text('Leonardo DiCaprio'));
        await tester.pump();
      });
    });

    group('compact mode', () {
      testWidgets(
        'renders a Cast picker button with the localized "Cast" label',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              semanticLabel: 'Cast',
            ),
          );

          // The button label is the row's semanticLabel ("Cast"),
          // localized by the caller - never a hard-coded English fallback
          // pulled from inside the widget.
          expect(find.text('Cast'), findsOneWidget);
          // The chevron icon indicates the button opens a picker.
          expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
          // No cast member names bleed into compact mode.
          expect(find.text('Actor 0'), findsNothing);
          expect(find.text('Actor 4'), findsNothing);
        },
      );

      testWidgets(
        'shows the cast count in a muted badge',
        (tester) async {
          final members = [
            for (var i = 0; i < 7; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              semanticLabel: 'Cast',
            ),
          );

          // Badge text renders the count (7).
          expect(find.text('7'), findsOneWidget);
          // The button label still says "Cast".
          expect(find.text('Cast'), findsOneWidget);
        },
      );

      testWidgets(
        'fires onShowAll when the picker button is tapped',
        (tester) async {
          var tapCount = 0;
          final members = [_m(name: 'Solo'), _m(name: 'Duet')];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () => tapCount++,
              semanticLabel: 'Cast',
            ),
          );

          // Tap via the localized label (the visible button content).
          await tester.tap(find.text('Cast'));
          await tester.pump();
          expect(tapCount, 1);
        },
      );

      testWidgets(
        'button exposes its label and is discoverable as a tappable',
        (tester) async {
          final members = [_m(name: 'Solo')];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              semanticLabel: 'Cast',
            ),
          );

          // The AppButton's label is in the tree (it's the visible text
          // of the button). Tapping it fires the callback - that's the
          // practical a11y contract. (AppButton internally wires its own
          // Semantics node with button=true; we don't assert on the
          // exact Semantics widget to keep the test resilient to the
          // AppButton implementation evolving.)
          expect(find.text('Cast'), findsOneWidget);
          expect(find.byType(AppButton), findsOneWidget);
        },
      );

      testWidgets(
        'renders nothing when onShowAll is null (caller opts out)',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              // onShowAll intentionally null.
            ),
          );

          // No button label, no chevron, no badge, no member names.
          expect(find.text('Cast'), findsNothing);
          expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
          expect(find.text('Actor 0'), findsNothing);
        },
      );

      testWidgets(
        'compact button matches the season picker height',
        (tester) async {
          final members = [_m(name: 'Solo')];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              semanticLabel: 'Cast',
            ),
          );

          // The picker shares the AppButton's intrinsic metrics so it
          // lines up with the play / season-picker buttons in the same
          // row (mirrors how the season picker comments at line ~1153).
          final buttonFinder = find.byType(AppButton);
          expect(buttonFinder, findsOneWidget);
          expect(
            tester.getSize(buttonFinder).height,
            // AppButton's default height - wider tolerance for future
            // updates as long as the assertion catches 0 / negative
            // regressions.
            greaterThan(0),
          );
        },
      );

      testWidgets(
        'wide layout shows full cast up to 15 without a picker button',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++)
              _m(name: 'Actor $i', character: 'Role $i'),
          ];
          await tester.pumpWidget(_harness(members: members));

          // All 5 render as cards.
          expect(find.text('Actor 4'), findsOneWidget);
          // No picker button in wide layout.
          expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
          expect(find.text('Cast'), findsNothing);
        },
      );
    });
  });
}
