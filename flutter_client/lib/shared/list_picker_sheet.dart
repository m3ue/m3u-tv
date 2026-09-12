import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Generic picker for "show all X" overflow scenarios. Mirrors the
/// season picker's two modal forms: a drag-handle bottom sheet on the
/// narrow breakpoint ([show] with `asDialog: false`, the default) and a
/// centered [AlertDialog] on the wide/TV breakpoint (`asDialog: true`).
/// Either way it is one [DpadRegion] containing a title row + capped
/// ListView.
///
/// Used by the cast "Show all" affordances on VOD and Series detail
/// screens; also a natural fit for any future "more items" affordance
/// that needs a scrollable picker. The picker's contents are
/// caller-supplied via [children] - this widget owns only the modal
/// chrome.
///
/// Focus lands on the [autofocusIndex] child (default 0) so D-pad input
/// starts inside the list rather than on the surrounding scrim; when the
/// children are non-interactive (e.g. cast rows) this just seats the
/// scroll position. The list is height-capped with a [ConstrainedBox]
/// (not a [Flexible]) so the layout stays deterministic inside the
/// modal's intrinsic sizing - a Flexible there lets rows overflow the
/// sheet's clip and drop out of hit-testing.
class ListPickerSheet extends StatelessWidget {
  const ListPickerSheet({
    super.key,
    required this.title,
    required this.children,
    this.autofocusIndex = 0,
    this.cancelLabel,
    this.asDialog = false,
  });

  /// Header text in the sheet's title row.
  final String title;

  /// Scrollable row widgets. Caller owns their layout - typically one
  /// ListTile or DpadInkWell per item.
  final List<Widget> children;

  /// Index of the child that receives initial focus when the sheet
  /// opens. Pass -1 to disable autofocus.
  final int autofocusIndex;

  /// Tooltip / semantics label for the close icon button. Falls back
  /// to "Cancel" if null (callers should localize).
  final String? cancelLabel;

  /// Dialog chrome instead of sheet chrome: tighter list metrics, a
  /// slightly lower height cap and an always-visible scrollbar thumb -
  /// matching the season picker's wide-layout dialog.
  final bool asDialog;

  /// Show the picker. Opens a drag-handle bottom sheet by default
  /// (narrow breakpoint), or a centered 460px [AlertDialog] when
  /// [asDialog] is true (wide/TV breakpoint) - the same split the
  /// season picker uses. Either way the inner list is height-capped so
  /// long lists scroll inside the modal instead of pushing it
  /// off-screen.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    int autofocusIndex = 0,
    String? cancelLabel,
    bool asDialog = false,
  }) {
    if (asDialog) {
      return showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          clipBehavior: Clip.antiAlias,
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
          content: SizedBox(
            width: 460 * FontSizeScope.scaleOf(dialogContext),
            child: ListPickerSheet(
              title: title,
              autofocusIndex: autofocusIndex,
              cancelLabel: cancelLabel,
              asDialog: true,
              children: children,
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListPickerSheet(
          title: title,
          autofocusIndex: autofocusIndex,
          cancelLabel: cancelLabel,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: scheme.onSurface,
    );
    // Same metric split as the season picker: 70% cap in the sheet,
    // 65% + visible thumb + tighter bottom padding in the dialog.
    final maxListHeight = viewportHeight * (asDialog ? 0.65 : 0.7);
    final listPadding = asDialog
        ? const EdgeInsets.fromLTRB(12, 4, 12, 4)
        : const EdgeInsets.fromLTRB(12, 4, 12, 12);

    return DpadRegion(
      verticalEdge: DpadEdgeBehavior.stop,
      horizontalEdge: DpadEdgeBehavior.stop,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                AppIconButton(
                  icon: Icons.close,
                  dense: true,
                  tooltip: cancelLabel ?? 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: Scrollbar(
              thumbVisibility: asDialog,
              child: ListView(
                shrinkWrap: true,
                padding: listPadding,
                children: [
                  for (var i = 0; i < children.length; i++)
                    if (i == autofocusIndex)
                      Focus(autofocus: true, child: children[i])
                    else
                      children[i],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
