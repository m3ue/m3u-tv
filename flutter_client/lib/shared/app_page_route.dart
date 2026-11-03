import 'package:material_ui/material_ui.dart';

/// Opaque backing behind every pushed page: the shared TV-layout gradient's
/// dominant end tone. Pages have a transparent `scaffoldBackgroundColor`
/// (the theme relies on AppShell's gradient showing through), so without it
/// a page renders see-through over the old one until its push finishes.
const Color kAppPageBackground = Color(0xFF09090b);

/// The app's page transition: a pure slide in from the right, no fade
/// (Material 3's default fade-through would flash the transparent page).
/// Shared by [appPageRoute] and go_router's `_slidePage`.
Widget appSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) => SlideTransition(
  position: Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
  child: child,
);

/// A full-screen page pushed with [Navigator.push]: [builder]'s content over
/// [kAppPageBackground], sliding in with [appSlideTransition]. Use this
/// rather than a raw [MaterialPageRoute] or [PageRouteBuilder] so every
/// pushed page moves the same way.
Route<T> appPageRoute<T>({required WidgetBuilder builder}) =>
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) => Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: kAppPageBackground),
          builder(context),
        ],
      ),
      transitionsBuilder: appSlideTransition,
    );
