import 'package:material_ui/material_ui.dart';

/// Icons with an app-wide meaning (the back arrow), kept in one place so
/// their glyph can change everywhere at once.
abstract final class AppIcons {
  static IconData back(BuildContext context) => Icons.arrow_back;
}
