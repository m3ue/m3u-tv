import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/app_icons.dart';
import 'package:material_ui/material_ui.dart';

/// A page's top bar. Use it instead of a raw [AppBar].
///
/// With [onBack] it shows the app's back button, scaled by [scale] and
/// pushed right by [leadingInset] (the macOS traffic lights). Without it the
/// bar is title-only, implying the platform back button when the route can
/// pop.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.scale = 1,
    this.leadingInset = 0,
  });

  final Widget title;
  final VoidCallback? onBack;
  final double scale;
  final double leadingInset;

  @override
  Size get preferredSize => Size.fromHeight(
    onBack == null ? kToolbarHeight : kToolbarHeight * scale,
  );

  @override
  Widget build(BuildContext context) {
    final onBack = this.onBack;
    if (onBack == null) return AppBar(title: title);
    return AppBar(
      title: title,
      automaticallyImplyLeading: false,
      // The default toolbarHeight is unscaled, which would squeeze
      // AppIconButton's scaled footprint (see item_detail_scaffold.dart).
      toolbarHeight: kToolbarHeight * scale,
      leadingWidth: (56 * scale) + leadingInset,
      leading: Padding(
        padding: EdgeInsets.fromLTRB(
          8 * scale + leadingInset,
          8 * scale,
          8 * scale,
          8 * scale,
        ),
        child: AppIconButton(
          icon: AppIcons.back(context),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onBack,
        ),
      ),
    );
  }
}
