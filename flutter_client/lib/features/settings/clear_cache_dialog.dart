import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dialog_option_tiles.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

/// Asks what "Clear & Refresh" should reset. The default action (focused, and
/// the top card) clears everything, so the existing two-press flow is
/// unchanged; the stacked tiles narrow it to one cache.
///
/// Returns null when dismissed.
Future<CacheClearScope?> showClearCacheDialog(BuildContext context) {
  return showDialog<CacheClearScope>(
    context: context,
    builder: (_) => const _ClearCacheDialog(),
  );
}

class _ClearCacheDialog extends StatelessWidget {
  const _ClearCacheDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final scale = FontSizeScope.scaleOf(context);
    void pick(CacheClearScope scope) => Navigator.of(context).pop(scope);

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480 * scale),
        child: DpadRegion(
          memoryKey: 'clear-cache-dialog',
          verticalEdge: DpadEdgeBehavior.stop,
          horizontalEdge: DpadEdgeBehavior.stop,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.settingsClearCacheTitle,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  l.settingsClearCacheBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                DialogPrimaryOption(
                  icon: Icons.refresh,
                  title: l.settingsClearCacheAll,
                  subtitle: l.settingsClearCacheAllHint,
                  onTap: () => pick(CacheClearScope.all),
                ),
                const SizedBox(height: 8),
                DialogActionTile(
                  icon: Icons.video_library_outlined,
                  label: l.settingsClearCacheContent,
                  subtitle: l.settingsClearCacheContentHint,
                  onTap: () => pick(CacheClearScope.content),
                ),
                const SizedBox(height: 8),
                DialogActionTile(
                  icon: Icons.event_note_outlined,
                  label: l.settingsClearCacheEpg,
                  subtitle: l.settingsClearCacheEpgHint,
                  onTap: () => pick(CacheClearScope.epg),
                ),
                const SizedBox(height: 8),
                DialogActionTile(
                  icon: Icons.image_outlined,
                  label: l.settingsClearCacheImages,
                  subtitle: l.settingsClearCacheImagesHint,
                  onTap: () => pick(CacheClearScope.images),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AppButton(
                      label: l.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      autofocus: true,
                      variant: AppButtonVariant.primary,
                      label: l.settingsClearCacheConfirm,
                      onPressed: () => pick(CacheClearScope.all),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
