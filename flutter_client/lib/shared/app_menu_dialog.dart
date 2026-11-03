import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:material_ui/material_ui.dart';

/// A titled list of options (a context menu, a sort picker). Use it (opened
/// with `showAppDialog`) instead of a raw [SimpleDialog]; [children] are
/// usually [AppMenuOption]s.
class AppMenuDialog extends StatelessWidget {
  const AppMenuDialog({
    super.key,
    required this.title,
    required this.children,
    this.width,
  });

  final Widget title;
  final List<Widget> children;

  /// A fixed width (scaled, and kept within the screen) for long pickers;
  /// otherwise the dialog fits its options.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final width = this.width;
    final scaled = width == null
        ? null
        : width * FontSizeScope.scaleOf(context);
    return SimpleDialog(
      title: title,
      constraints: scaled == null
          ? null
          : BoxConstraints(minWidth: scaled, maxWidth: scaled),
      children: children,
    );
  }
}

/// One choice in an [AppMenuDialog]: an icon, a label and an optional
/// [subtitle] in a D-pad ink well. [padding] and [borderRadius] default to
/// the context menus' 24x10 (scaled) inset and square corners.
class AppMenuOption extends StatelessWidget {
  const AppMenuOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
    this.padding,
    this.borderRadius,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final bool autofocus;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scale = FontSizeScope.scaleOf(context);
    final subtitle = this.subtitle;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      borderRadius: borderRadius,
      child: Padding(
        padding:
            padding ??
            EdgeInsets.symmetric(vertical: 10 * scale, horizontal: 24 * scale),
        child: Row(
          children: [
            Icon(icon, size: 20 * scale),
            SizedBox(width: 12 * scale),
            Expanded(
              child: subtitle != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    )
                  : Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
