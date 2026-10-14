import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A titled QR code for a link the device can't open itself (a TV with no
/// browser, or no app installed to handle the link), so it can be scanned
/// and opened on a phone instead.
class QrLinkDialog extends StatelessWidget {
  const QrLinkDialog({
    super.key,
    required this.title,
    required this.url,
    required this.memoryKey,
  });

  final String title;
  final String url;

  /// [DpadRegion.memoryKey] for the dialog's focus region.
  final String memoryKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scale = FontSizeScope.scaleOf(context);

    return Dialog(
      child: DpadRegion(
        memoryKey: memoryKey,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: QrImageView(
                  data: url,
                  size: 200 * scale,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l.settingsAppScanQr,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: MaterialLocalizations.of(context).closeButtonLabel,
                autofocus: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
