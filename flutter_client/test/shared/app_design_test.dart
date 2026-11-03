import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_design.dart';
import 'package:m3u_tv/shared/app_loading_indicator.dart';
import 'package:m3u_tv/shared/app_page_route.dart';
import 'package:m3u_tv/shared/app_switch.dart';
import 'package:material_ui/material_ui.dart';

AppDesign _resolve(
  TargetPlatform platform, {
  String override = '',
  bool isTvOS = false,
  bool isWeb = false,
}) => resolveAppDesign(
  override: override,
  platform: platform,
  isTvOS: isTvOS,
  isWeb: isWeb,
);

Widget _host(AppDesign design, Widget child) => AppDesignScope(
  design: design,
  child: MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  group('resolveAppDesign', () {
    test('defaults to Cupertino on iPhone, iPad and macOS only', () {
      expect(_resolve(TargetPlatform.iOS), AppDesign.cupertino);
      expect(_resolve(TargetPlatform.macOS), AppDesign.cupertino);
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(_resolve(platform), AppDesign.material, reason: '$platform');
      }
    });

    test('keeps Apple TV and the web on Material', () {
      expect(_resolve(TargetPlatform.iOS, isTvOS: true), AppDesign.material);
      expect(_resolve(TargetPlatform.macOS, isWeb: true), AppDesign.material);
    });

    test('M3U_TV_DESIGN overrides the platform default', () {
      expect(
        _resolve(TargetPlatform.macOS, override: 'material'),
        AppDesign.material,
      );
      expect(
        _resolve(TargetPlatform.android, override: 'cupertino', isTvOS: true),
        AppDesign.cupertino,
      );
      expect(
        _resolve(TargetPlatform.iOS, override: 'unknown'),
        AppDesign.cupertino,
      );
    });
  });

  testWidgets('without a scope the shared widgets render Material', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(label: 'Play', onPressed: () {}),
        ),
      ),
    );
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(CupertinoButton), findsNothing);
  });

  group('AppButton', () {
    testWidgets('keeps the Material buttons in the Material design', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AppDesign.material,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Play',
                variant: AppButtonVariant.primary,
                onPressed: () {},
              ),
              AppButton(label: 'Trailer', onPressed: () {}),
            ],
          ),
        ),
      );
      expect(find.byType(ElevatedButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(CupertinoButton), findsNothing);
    });

    testWidgets('renders iOS buttons in the Cupertino design', (tester) async {
      var plays = 0;
      await tester.pumpWidget(
        _host(
          AppDesign.cupertino,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Play',
                icon: Icons.play_arrow,
                variant: AppButtonVariant.primary,
                onPressed: () => plays++,
              ),
              AppButton(label: 'Trailer', onPressed: () {}),
            ],
          ),
        ),
      );
      expect(find.byType(CupertinoButton), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.text('Play'));
      expect(plays, 1);
    });

    testWidgets('loading shows the activity indicator and disables it', (
      tester,
    ) async {
      var presses = 0;
      await tester.pumpWidget(
        _host(
          AppDesign.cupertino,
          AppButton(
            label: 'Connect',
            loading: true,
            onPressed: () => presses++,
          ),
        ),
      );
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(
        tester.widget<CupertinoButton>(find.byType(CupertinoButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(CupertinoButton));
      expect(presses, 0);
    });
  });

  testWidgets('AppIconButton keeps its footprint and label in Cupertino', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        AppDesign.cupertino,
        AppIconButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onPressed: () => presses++,
        ),
      ),
    );
    expect(tester.getSize(find.byType(CupertinoButton)), const Size(56, 56));
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    await tester.tap(find.byType(CupertinoButton));
    expect(presses, 1);
  });

  testWidgets('AppSwitch renders the platform toggle for each design', (
    tester,
  ) async {
    bool? changedTo;
    for (final design in AppDesign.values) {
      changedTo = null;
      await tester.pumpWidget(
        _host(design, AppSwitch(value: false, onChanged: (v) => changedTo = v)),
      );
      final cupertino = design == AppDesign.cupertino;
      expect(
        find.byType(CupertinoSwitch),
        cupertino ? findsOneWidget : findsNothing,
      );
      expect(find.byType(Switch), cupertino ? findsNothing : findsOneWidget);
      await tester.tap(find.byType(AppSwitch));
      await tester.pump();
      expect(changedTo, isTrue, reason: '$design');
    }
  });

  group('AppLoadingIndicator', () {
    testWidgets('is the circular indicator in Material', (tester) async {
      await tester.pumpWidget(
        _host(AppDesign.material, const AppLoadingIndicator(strokeWidth: 2)),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .strokeWidth,
        2,
      );
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('fills a small box and is page-sized elsewhere in Cupertino', (
      tester,
    ) async {
      double radius() => tester
          .widget<CupertinoActivityIndicator>(
            find.byType(CupertinoActivityIndicator),
          )
          .radius;

      await tester.pumpWidget(
        _host(
          AppDesign.cupertino,
          const SizedBox.square(dimension: 20, child: AppLoadingIndicator()),
        ),
      );
      expect(radius(), 10);

      await tester.pumpWidget(
        _host(AppDesign.cupertino, const AppLoadingIndicator()),
      );
      expect(radius(), 16);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('appPageRoute', () {
    Future<BuildContext> pumpHome(WidgetTester tester, AppDesign design) async {
      late BuildContext homeContext;
      await tester.pumpWidget(
        _host(
          design,
          Builder(
            builder: (context) {
              homeContext = context;
              return const Text('Home');
            },
          ),
        ),
      );
      return homeContext;
    }

    Widget detail(BuildContext context) => const ColoredBox(
      color: Color(0xFF09090b),
      child: Center(child: Text('Detail')),
    );

    testWidgets('is the slide route in Material', (tester) async {
      final context = await pumpHome(tester, AppDesign.material);
      final route = appPageRoute<void>(context, builder: detail);
      expect(route, isA<PageRouteBuilder<void>>());
      expect(route, isNot(isA<CupertinoPageRoute<void>>()));
    });

    testWidgets('is an iOS route that pops on an edge swipe in Cupertino', (
      tester,
    ) async {
      final context = await pumpHome(tester, AppDesign.cupertino);
      final route = appPageRoute<void>(context, builder: detail);
      expect(route, isA<CupertinoPageRoute<void>>());

      Navigator.of(context).push(route);
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(600, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });
  });
}
