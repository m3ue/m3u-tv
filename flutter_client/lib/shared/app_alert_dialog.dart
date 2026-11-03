import 'package:dpad/dpad.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:material_ui/material_ui.dart';

/// One button of an [AppAlertDialog].
class AppDialogAction {
  const AppDialogAction({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.tonal,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final AppButtonVariant variant;
  final bool autofocus;
}

/// A title / message / buttons confirmation. Use it (opened with
/// `showAppDialog`) instead of building an [AlertDialog] with a row of
/// buttons by hand.
class AppAlertDialog extends StatelessWidget {
  const AppAlertDialog({
    super.key,
    required this.title,
    required this.actions,
    this.message,
    this.memoryKey,
  });

  final String title;
  final String? message;
  final List<AppDialogAction> actions;

  /// The button row's [DpadRegion.memoryKey].
  final String? memoryKey;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    return AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        DpadRegion(
          memoryKey: memoryKey,
          // OverflowBar (not Row) so the buttons stack vertically on a
          // narrow dialog instead of overflowing.
          child: OverflowBar(
            alignment: MainAxisAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              for (final action in actions)
                AppButton(
                  label: action.label,
                  variant: action.variant,
                  autofocus: action.autofocus,
                  onPressed: action.onPressed,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
