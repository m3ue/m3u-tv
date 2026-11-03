import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:m3u_tv/shared/app_design.dart';
import 'package:material_ui/material_ui.dart';

/// Page-level spinner radius in the Cupertino design, close to Material's
/// default circular indicator footprint.
const double _kPageSpinnerRadius = 16;

/// The one indeterminate loading spinner: [CircularProgressIndicator] in the
/// Material design, [CupertinoActivityIndicator] in Cupertino.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({super.key, this.strokeWidth, this.color});

  /// Material only; the Cupertino spinner has no stroke.
  final double? strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!AppDesignScope.isCupertino(context)) {
      return CircularProgressIndicator(strokeWidth: strokeWidth, color: color);
    }
    // Inline spinners are sized into a small box (a button, a row): fill it.
    // Anywhere roomier gets the page-level size.
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = side > 0 && side < 2 * _kPageSpinnerRadius
            ? side / 2
            : _kPageSpinnerRadius;
        return CupertinoActivityIndicator(radius: radius, color: color);
      },
    );
  }
}
