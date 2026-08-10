import 'package:flutter/material.dart';

enum AppCalloutVariant { info, warning, error }

/// Persistent inline callout for guidance that must read as important, not
/// as a subtitle (e.g. credential help, feature caveats). Distinct from the
/// transient push-style toasts in `shared/notification_toast.dart`.
class AppCallout extends StatelessWidget {
  const AppCallout({
    super.key,
    required this.message,
    this.variant = AppCalloutVariant.info,
  });

  final String message;
  final AppCalloutVariant variant;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (container, onContainer, icon) = switch (variant) {
      AppCalloutVariant.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        Icons.info_outline,
      ),
      AppCalloutVariant.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        Icons.warning_amber_outlined,
      ),
      AppCalloutVariant.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.error_outline,
      ),
    };

    return Card(
      color: container,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: onContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
