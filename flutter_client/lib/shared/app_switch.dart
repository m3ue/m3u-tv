import 'package:material_ui/material_ui.dart';

/// The app's on/off toggle. Use it instead of a raw [Switch] so the control
/// is defined in one place.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Switch(value: value, onChanged: onChanged);
}
