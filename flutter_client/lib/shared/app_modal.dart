import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Opens a dialog. Every dialog in the app goes through this rather than
/// [showDialog] directly, so how dialogs are presented is defined in one
/// place.
@awaitNotRequired
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  barrierColor: barrierColor,
);

/// Opens a modal bottom sheet. Every sheet in the app goes through this
/// rather than [showModalBottomSheet] directly, for the same reason as
/// [showAppDialog].
@awaitNotRequired
Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  BoxConstraints? constraints,
  Color? backgroundColor,
}) => showModalBottomSheet<T>(
  context: context,
  builder: builder,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  showDragHandle: showDragHandle,
  constraints: constraints,
  backgroundColor: backgroundColor,
);
