import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:m3u_tv/shared/app_design.dart';
import 'package:material_ui/material_ui.dart';

/// The one on/off toggle: [Switch] in the Material design, [CupertinoSwitch]
/// in Cupertino.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => AppDesignScope.isCupertino(context)
      ? CupertinoSwitch(value: value, onChanged: onChanged)
      : Switch(value: value, onChanged: onChanged);
}
