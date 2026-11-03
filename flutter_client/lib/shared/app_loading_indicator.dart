import 'package:material_ui/material_ui.dart';

/// The app's indeterminate loading spinner. Use it instead of a raw
/// [CircularProgressIndicator] so the spinner is defined in one place.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.strokeWidth, this.color});

  final double? strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      CircularProgressIndicator(strokeWidth: strokeWidth, color: color);
}
