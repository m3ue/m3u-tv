import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Long-press affordance for the Live TV Multiview button: lets the user
/// drop individual channels, or clear the whole queue, without first
/// entering the Multiview grid (where the same is only reachable per-tile
/// via each tile's own long-press menu).
///
/// Wrapped in a [Consumer] so the channel list stays live while the dialog
/// is open — removing the last channel here should behave the same as
/// removing it from inside the grid, so the dialog closes itself once
/// [multiviewChannelsProvider] goes empty.
Future<void> showMultiviewManageDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (context, ref, _) {
        final channels = ref.watch(multiviewChannelsProvider);
        if (channels.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
          });
          return const SizedBox.shrink();
        }
        final l10n = AppLocalizations.of(context);
        final controller = ref.read(multiviewControllerProvider);
        return AlertDialog(
          title: Text(l10n.multiviewManageTitle),
          content: SizedBox(
            width: 360 * FontSizeScope.scaleOf(context),
            child: DpadRegion(
              memoryKey: 'multiview/manage-dialog',
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: channels.length,
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppIconButton(
                          icon: Icons.close,
                          variant: AppButtonVariant.destructive,
                          tooltip: l10n.multiviewRemoveChannel(channel.name),
                          autofocus: index == 0,
                          onPressed: () => controller.remove(channel.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            DpadRegion(
              memoryKey: 'multiview/manage-dialog-actions',
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  AppButton(
                    label: l10n.multiviewClearAll,
                    variant: AppButtonVariant.destructive,
                    onPressed: controller.clear,
                  ),
                  AppButton(
                    label: l10n.close,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
