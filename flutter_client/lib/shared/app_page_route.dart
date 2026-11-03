import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:m3u_tv/shared/app_design.dart';

/// The Material design's full-screen push transition: a pure horizontal
/// slide, no fade. Pages pushed with it paint their own opaque backing,
/// since `scaffoldBackgroundColor` is transparent app-wide (relying on
/// AppShell's shared gradient) and a fading route would briefly render
/// see-through.
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

/// A full-screen page route: [appSlideTransition] in the Material design, an
/// iOS page route (parallax slide and edge swipe-back) in Cupertino.
/// [builder] must paint an opaque backing for the reason on
/// [appSlideTransition].
Route<T> appPageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => AppDesignScope.isCupertino(context)
    ? CupertinoPageRoute<T>(builder: builder)
    : PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            builder(context),
        transitionsBuilder: appSlideTransition,
      );
